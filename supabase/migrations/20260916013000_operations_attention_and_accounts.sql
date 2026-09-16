begin;

-- 1) Technician workday audit: the shift RPC already verifies an active technician
-- membership. Calling the public audit wrapper afterwards rejected technicians because
-- that wrapper is intentionally staff-only. Keep the authorization narrow by replacing
-- only this RPC and writing the audit row through the trusted internal function after
-- membership validation has succeeded.
create or replace function private.change_technician_shift(p_org uuid,p_action text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_shift public.technician_shifts%rowtype; v_terms public.technician_pay_terms%rowtype;
 v_day date; v_zone text; v_now timestamptz:=clock_timestamp(); v_seconds numeric;
begin
 if auth.uid() is null or not public.is_org_active(p_org) or not exists(select 1 from public.organization_memberships where organization_id=p_org and profile_id=auth.uid() and role='technician' and status='active') then raise exception 'Active technician membership required'; end if;
 if p_action not in ('start','pause','resume','end') or p_action is null then raise exception 'Invalid shift action'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,451));
 select * into v_shift from public.technician_shifts where profile_id=auth.uid() and ended_at is null for update;
 if v_shift.id is not null and v_shift.organization_id<>p_org then raise exception 'Close your shift in the other company first'; end if;
 if p_action='start' then
   if v_shift.id is not null then return v_shift.id; end if;
   select timezone into v_zone from public.organization_settings where organization_id=p_org;
   if v_zone is null then raise exception 'Company timezone must be configured'; end if;
   v_day := (v_now at time zone v_zone)::date;
   if exists(select 1 from public.technician_shifts where profile_id=auth.uid() and organization_id=p_org and work_date=v_day) then raise exception 'Today is already closed. Contact your company administrator for a correction'; end if;
   select * into v_terms from public.technician_pay_terms where organization_id=p_org and profile_id=auth.uid();
   if v_terms.pay_rate is null then raise exception 'Your company must configure your pay terms before you can start your day';end if;
   insert into public.technician_shifts(organization_id,profile_id,work_date,started_at,pay_type,pay_rate,currency)
   values(p_org,auth.uid(),v_day,v_now,v_terms.pay_type,v_terms.pay_rate,v_terms.currency) returning * into v_shift;
 else
   if v_shift.id is null then raise exception 'Start your day first'; end if;
   if p_action='pause' and v_shift.paused_at is null then
     update public.technician_shifts set paused_at=v_now where id=v_shift.id;
   elsif p_action='resume' and v_shift.paused_at is not null then
     update public.technician_shifts set break_seconds=break_seconds+extract(epoch from (v_now-paused_at)),paused_at=null where id=v_shift.id;
   elsif p_action='end' then
     v_seconds:=greatest(0,extract(epoch from (coalesce(v_shift.paused_at,v_now)-v_shift.started_at))-v_shift.break_seconds);
     update public.technician_shifts set ended_at=v_now,paid_seconds=v_seconds,
       break_seconds=break_seconds+case when paused_at is null then 0 else extract(epoch from(v_now-paused_at)) end, paused_at=null,
       gross_amount=case when v_shift.pay_rate is null then null when v_shift.pay_type='daily' then case when v_seconds>0 then v_shift.pay_rate else 0 end else round(v_seconds/3600*v_shift.pay_rate,2) end
     where id=v_shift.id;
   end if;
 end if;
 perform public.log_audit_event_internal(p_org,'technician_shift',v_shift.id,'shift_'||p_action,null,jsonb_build_object('profile_id',auth.uid(),'at',v_now),auth.uid());
 return v_shift.id;
end; $$;

-- 2) Role-targeted operational notifications. A notification row always belongs to one
-- concrete recipient. This prevents client/technician/company notification bleed even if
-- a UI query is accidentally broad.
create or replace function private.notify_company_operations(
  p_org uuid,
  p_event_type text,
  p_severity text,
  p_title text,
  p_body text,
  p_entity_type text,
  p_entity_id uuid,
  p_ack boolean default true
) returns integer
language plpgsql security definer set search_path='' as $$
declare v_count integer:=0; v_member record;
begin
  for v_member in
    select profile_id
    from public.organization_memberships
    where organization_id=p_org and status='active' and role in ('company_owner','company_admin','manager')
  loop
    if not exists(
      select 1 from public.notifications n
      where n.recipient_user_id=v_member.profile_id
        and n.event_type=p_event_type
        and n.related_entity_type=p_entity_type
        and n.related_entity_id=p_entity_id
        and n.created_at > now()-interval '30 days'
    ) then
      insert into public.notifications(
        organization_id,recipient_user_id,event_type,severity,title,body,
        related_entity_type,related_entity_id,acknowledgement_required,
        delivery_channels,delivery_status
      ) values(
        p_org,v_member.profile_id,p_event_type,p_severity,p_title,p_body,
        p_entity_type,p_entity_id,p_ack,array['in_app']::text[],'delivered'
      );
      v_count:=v_count+1;
    end if;
  end loop;
  return v_count;
end;$$;
revoke all on function private.notify_company_operations(uuid,text,text,text,text,text,uuid,boolean) from public,anon,authenticated;
grant execute on function private.notify_company_operations(uuid,text,text,text,text,text,uuid,boolean) to service_role;

create or replace function private.service_request_attention_trigger() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT' and new.status='submitted' then
    perform private.notify_company_operations(
      new.organization_id,'SERVICE_REQUEST_SUBMITTED',
      case when new.urgency in ('high','urgent') then 'urgent' else 'action_required' end,
      'New service request',
      coalesce(new.title,'A customer requested service'),
      'service_request',new.id,true
    );
  end if;
  return new;
end;$$;
drop trigger if exists trg_service_request_attention on public.service_requests;
create trigger trg_service_request_attention after insert on public.service_requests
for each row execute function private.service_request_attention_trigger();

create or replace function private.estimate_attention_trigger() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.status='approved' and old.status is distinct from new.status then
    perform private.notify_company_operations(
      new.organization_id,'ESTIMATE_APPROVED','action_required',
      'Estimate approved — ready to schedule',
      'The customer approved the estimate. Create or open the work order and assign a technician.',
      'estimate',new.id,true
    );
  elsif new.status='declined' and old.status is distinct from new.status then
    perform private.notify_company_operations(
      new.organization_id,'ESTIMATE_DECLINED','action_required',
      'Estimate declined — review requested',
      'The customer declined an estimate. Review the note and decide the next step.',
      'estimate',new.id,true
    );
  end if;
  return new;
end;$$;
drop trigger if exists trg_estimate_attention on public.estimates;
create trigger trg_estimate_attention after update of status on public.estimates
for each row execute function private.estimate_attention_trigger();

create or replace function private.assignment_attention_trigger() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.status='active' and (tg_op='INSERT' or old.status is distinct from new.status or old.technician_profile_id is distinct from new.technician_profile_id) then
    if not exists(
      select 1 from public.notifications n
      where n.recipient_user_id=new.technician_profile_id
        and n.event_type='TECHNICIAN_ASSIGNED'
        and n.related_entity_type='work_order'
        and n.related_entity_id=new.work_order_id
        and n.created_at>now()-interval '30 days'
    ) then
      insert into public.notifications(
        organization_id,recipient_user_id,event_type,severity,title,body,
        related_entity_type,related_entity_id,acknowledgement_required,
        delivery_channels,delivery_status
      ) values(
        new.organization_id,new.technician_profile_id,'TECHNICIAN_ASSIGNED','action_required',
        'New job assigned','Open the job card to review the vessel, customer, schedule and instructions.',
        'work_order',new.work_order_id,true,array['in_app']::text[],'delivered'
      );
    end if;
  end if;
  return new;
end;$$;
drop trigger if exists trg_assignment_attention on public.assignments;
create trigger trg_assignment_attention after insert or update of status,technician_profile_id on public.assignments
for each row execute function private.assignment_attention_trigger();

-- 3) Company-facing KCC account summary. Raw platform ledger remains KCC-only; this RPC
-- reveals only the organization's own agreement/subscription/open balance and is restricted
-- to company owner/admin (plus KCC admin).
create or replace function public.get_company_kcc_account_summary(p_org uuid)
returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_allowed boolean; v_agreement jsonb; v_subscription jsonb; v_balance jsonb; v_next_due timestamptz;
begin
  v_allowed := public.is_kcc_admin() or exists(
    select 1 from public.organization_memberships
    where organization_id=p_org and profile_id=auth.uid() and status='active' and role in ('company_owner','company_admin')
  );
  if auth.uid() is null or not v_allowed then raise exception 'Not authorized'; end if;

  select to_jsonb(x) into v_agreement from (
    select id,compensation_type,percentage_rate,fixed_amount,currency,effective_from,effective_until,notes
    from public.compensation_agreements
    where organization_id=p_org and active=true
    order by effective_from desc limit 1
  ) x;

  select to_jsonb(x) into v_subscription from (
    select id,status,billing_cycle,currency,price_snapshot,current_period_ends_at,complimentary,custom_terms
    from public.organization_subscriptions
    where organization_id=p_org and superseded_at is null
    order by created_at desc limit 1
  ) x;

  select jsonb_build_object(
    'currency',coalesce(max(currency),'USD'),
    'open_balance',coalesce(sum(balance_due) filter(where status not in ('paid','void')),0),
    'open_charges',count(*) filter(where status not in ('paid','void')),
    'overdue_charges',count(*) filter(where status not in ('paid','void') and due_at<now()),
    'next_due_at',min(due_at) filter(where status not in ('paid','void'))
  ) into v_balance
  from public.platform_billing_charges
  where organization_id=p_org;

  return jsonb_build_object('agreement',v_agreement,'subscription',v_subscription,'balance',v_balance);
end;$$;
revoke all on function public.get_company_kcc_account_summary(uuid) from public,anon;
grant execute on function public.get_company_kcc_account_summary(uuid) to authenticated;


-- 4) Customer support conversation starter. Customers can open a secure portal conversation
-- without being granted staff message privileges. The first inbound message is written inside
-- this validated SECURITY DEFINER function and immediately creates a company attention event.
create or replace function public.start_customer_support_conversation(
  p_org uuid,
  p_vessel uuid,
  p_subject text,
  p_body text
) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_customer public.customers%rowtype; v_conversation uuid; v_message uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if length(trim(coalesce(p_subject,'')))<2 or length(trim(coalesce(p_body,'')))<2 then raise exception 'Subject and message are required'; end if;
  select * into v_customer from public.customers where organization_id=p_org and profile_id=auth.uid() limit 1;
  if v_customer.id is null or not exists(
    select 1 from public.organization_memberships where organization_id=p_org and profile_id=auth.uid() and role='customer' and status='active'
  ) then raise exception 'Active customer access required'; end if;
  if p_vessel is not null and not exists(
    select 1 from public.vessels where id=p_vessel and organization_id=p_org and current_customer_id=v_customer.id
  ) then raise exception 'Vessel does not belong to this customer'; end if;

  insert into public.conversations(organization_id,customer_id,vessel_id,subject,status,created_by,last_message_at)
  values(p_org,v_customer.id,p_vessel,left(trim(p_subject),180),'open',auth.uid(),now())
  returning id into v_conversation;

  insert into public.messages(
    organization_id,conversation_id,sender_type,customer_id,direction,channel,
    body_original,subject,status,customer_visible,sent_at
  ) values(
    p_org,v_conversation,'customer',v_customer.id,'inbound','email',
    left(trim(p_body),5000),left(trim(p_subject),180),'sent',true,now()
  ) returning id into v_message;

  perform private.notify_company_operations(
    p_org,'CUSTOMER_MESSAGE_RECEIVED','action_required','New customer message',
    left(trim(p_subject)||' — '||trim(p_body),500),
    'conversation',v_conversation,true
  );
  perform public.log_audit_event_internal(p_org,'conversation',v_conversation,'customer_support_opened',null,jsonb_build_object('message_id',v_message),auth.uid());
  return v_conversation;
end;$$;
revoke all on function public.start_customer_support_conversation(uuid,uuid,text,text) from public,anon;
grant execute on function public.start_customer_support_conversation(uuid,uuid,text,text) to authenticated;


create or replace function public.customer_reply_conversation(p_conversation uuid,p_body text)
returns uuid
language plpgsql security definer set search_path='' as $$
declare c public.conversations%rowtype; cust public.customers%rowtype; v_message uuid;
begin
  if auth.uid() is null or length(trim(coalesce(p_body,'')))<1 then raise exception 'Message is required'; end if;
  select * into c from public.conversations where id=p_conversation and status='open';
  if c.id is null then raise exception 'Conversation not found'; end if;
  select * into cust from public.customers where id=c.customer_id and organization_id=c.organization_id and profile_id=auth.uid();
  if cust.id is null then raise exception 'Not authorized'; end if;
  insert into public.messages(
    organization_id,conversation_id,sender_type,customer_id,direction,channel,
    body_original,status,customer_visible,sent_at
  ) values(c.organization_id,c.id,'customer',cust.id,'inbound','email',left(trim(p_body),5000),'sent',true,now())
  returning id into v_message;
  update public.conversations set last_message_at=now(),updated_at=now(),status='open' where id=c.id;
  perform private.notify_company_operations(
    c.organization_id,'CUSTOMER_MESSAGE_RECEIVED','action_required','Customer replied',
    left(trim(p_body),500),'conversation',c.id,false
  );
  return v_message;
end;$$;
revoke all on function public.customer_reply_conversation(uuid,text) from public,anon;
grant execute on function public.customer_reply_conversation(uuid,text) to authenticated;

commit;
