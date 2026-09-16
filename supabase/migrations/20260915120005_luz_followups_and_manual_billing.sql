begin;
create table public.luz_estimate_followups (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 estimate_id uuid not null references public.estimates(id), version_id uuid not null references public.estimate_versions(id),
 source_message_id uuid not null references public.messages(id), message_id uuid references public.messages(id),
 email_snapshot text not null, sequence int not null check(sequence between 1 and 2),
 due_at timestamptz not null, status text not null default 'scheduled' check(status in ('scheduled','processing','sent','stopped','failed')),
 reason text, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 unique(version_id,sequence)
);
alter table public.luz_estimate_followups enable row level security;
revoke all on public.luz_estimate_followups from public,anon,authenticated;
grant select on public.luz_estimate_followups to authenticated;
grant select,update on public.luz_estimate_followups to service_role;
create index luz_followups_due on public.luz_estimate_followups(due_at) where status='scheduled';
create index luz_followups_org on public.luz_estimate_followups(organization_id,created_at desc);
create policy luz_followup_read on public.luz_estimate_followups for select to authenticated using(private.can_manage_payroll(organization_id));

create function private.schedule_estimate_followups(p_estimate uuid,p_message uuid,p_days int,p_count int) returns void
language plpgsql security definer set search_path='' as $$
declare e public.estimates%rowtype;v public.estimate_versions%rowtype;m public.messages%rowtype;c public.conversations%rowtype;v_email text;i int;
begin
 select * into e from public.estimates where id=p_estimate;
 if auth.uid() is null or e.id is null or not private.can_manage_payroll(e.organization_id) then raise exception 'Not authorized';end if;
 if p_days not between 1 and 30 or p_count not between 1 and 2 or p_days is null or p_count is null then raise exception 'Use 1–30 days and at most two reminders';end if;
 select * into v from public.estimate_versions where id=e.current_version_id;
 select * into m from public.messages where id=p_message;
 select * into c from public.conversations where id=m.conversation_id;
 if m.id is null or c.customer_id<>e.customer_id or c.organization_id<>e.organization_id or m.direction<>'outbound' or m.channel<>'email' or m.status not in ('sent','delivered') or m.sent_at<v.sent_at or m.sent_at is null then raise exception 'A successfully sent estimate email is required';end if;
 if v.status not in ('sent','viewed') or e.status not in ('sent','viewed') then raise exception 'Only estimates awaiting a response can be followed up';end if;
 select lower(trim(email)) into v_email from public.customers where id=e.customer_id;
 if v_email is null or v_email='' then raise exception 'Customer email required';end if;
 for i in 1..p_count loop
 insert into public.luz_estimate_followups(organization_id,estimate_id,version_id,source_message_id,email_snapshot,sequence,due_at,created_by)
 values(e.organization_id,e.id,v.id,m.id,v_email,i,now()+make_interval(days=>p_days*i),auth.uid()) on conflict(version_id,sequence) do nothing;
 end loop;
 perform public.log_audit_event(e.organization_id,'estimate',e.id,'luz_followup_scheduled',null,jsonb_build_object('count',p_count,'interval_days',p_days));
end;$$;
create function public.schedule_estimate_followups(p_estimate uuid,p_message uuid,p_days int,p_count int) returns void language sql security invoker set search_path='' as $$select private.schedule_estimate_followups(p_estimate,p_message,p_days,p_count);$$;
revoke all on function private.schedule_estimate_followups(uuid,uuid,int,int),public.schedule_estimate_followups(uuid,uuid,int,int) from public,anon;
grant execute on function private.schedule_estimate_followups(uuid,uuid,int,int),public.schedule_estimate_followups(uuid,uuid,int,int) to authenticated;

create function private.stop_estimate_followups(p_estimate uuid) returns void language plpgsql security definer set search_path='' as $$
declare e public.estimates%rowtype;
begin select * into e from public.estimates where id=p_estimate;
if auth.uid() is null or not private.can_manage_payroll(e.organization_id) then raise exception 'Not authorized';end if;
update public.luz_estimate_followups set status='stopped',reason='Stopped by staff' where estimate_id=p_estimate and status='scheduled';
end;$$;
create function public.stop_estimate_followups(p_estimate uuid) returns void language sql security invoker set search_path='' as $$select private.stop_estimate_followups(p_estimate);$$;
revoke all on function private.stop_estimate_followups(uuid),public.stop_estimate_followups(uuid) from public,anon;
grant execute on function private.stop_estimate_followups(uuid),public.stop_estimate_followups(uuid) to authenticated;

-- Service-only claim. A claimed job is never automatically retried after an uncertain delivery.
create function private.claim_luz_followup() returns jsonb language plpgsql security definer set search_path='' as $$
declare j public.luz_estimate_followups%rowtype;e public.estimates%rowtype;v public.estimate_versions%rowtype;m public.messages%rowtype;
 c public.conversations%rowtype;cust public.customers%rowtype;settings public.organization_email_settings%rowtype;v_id uuid;v_body text;v_subject text;
begin
 select * into j from public.luz_estimate_followups where status='scheduled' and due_at<=now() order by due_at for update skip locked limit 1;
 if j.id is null then return null;end if;
 select * into e from public.estimates where id=j.estimate_id;
 select * into v from public.estimate_versions where id=j.version_id;
 select * into m from public.messages where id=j.source_message_id;
 select * into c from public.conversations where id=m.conversation_id;
 select * into cust from public.customers where id=e.customer_id;
 select * into settings from public.organization_email_settings where organization_id=j.organization_id;
 if e.current_version_id<>j.version_id or e.status not in ('sent','viewed') or v.status not in ('sent','viewed') or (v.valid_until is not null and v.valid_until<current_date)
 or not public.is_org_active(j.organization_id) or c.status<>'open' or lower(trim(cust.email)) is distinct from j.email_snapshot
 or m.status not in ('sent','delivered') or settings.enabled is distinct from true or settings.sender_email is null
 or exists(select 1 from public.messages x join public.conversations cv on cv.id=x.conversation_id where cv.customer_id=c.customer_id and cv.organization_id=c.organization_id and ((x.direction='inbound' and x.created_at>=m.sent_at) or x.status in ('bounced','complained')))
 or exists(select 1 from public.luz_estimate_followups other where other.version_id=j.version_id and other.sequence<j.sequence and other.status<>'sent') then
 update public.luz_estimate_followups set status='stopped',reason='Estimate changed, customer responded, or delivery is unavailable' where id=j.id;return jsonb_build_object('skipped',true);end if;
 v_subject:='Your estimate '||e.estimate_number||' — can we help?';
 v_body:='Hi '||coalesce(cust.first_name,'')||E',\n\nYour estimate '||e.estimate_number||' is waiting for your review. The total is '||v.currency||' '||to_char(v.total,'FM999,999,990.00')||E'.\n\nOpen your portal to review the details or reply to this email with any questions. Reply if you would prefer no further follow-up.\n\nLuz · Your marine service team';
 insert into public.messages(organization_id,conversation_id,sender_type,direction,channel,body_original,subject,status,customer_visible,idempotency_key)
 values(j.organization_id,c.id,'system','outbound','email',v_body,v_subject,'queued',true,'luz-followup-'||j.id) returning id into v_id;
 update public.luz_estimate_followups set status='processing',message_id=v_id where id=j.id;
 return jsonb_build_object('jobId',j.id,'messageId',v_id,'conversationId',c.id,'recipient',cust.email,'fromEmail',settings.sender_email,'fromName',settings.sender_name,'signature',settings.signature_text,'subject',v_subject,'body',v_body,'estimateId',e.id);
end;$$;
create function public.claim_luz_followup() returns jsonb language sql security invoker set search_path='' as $$select private.claim_luz_followup();$$;
revoke all on function private.claim_luz_followup(),public.claim_luz_followup() from public,anon,authenticated;
grant usage on schema private to service_role;
grant execute on function private.claim_luz_followup(),public.claim_luz_followup() to service_role;

create function private.record_customer_email_reply(p_provider_id text,p_conversation uuid,p_sender text,p_body text,p_subject text) returns boolean
language plpgsql security definer set search_path='' as $$
declare c public.conversations%rowtype;v_email text;
begin
 select * into c from public.conversations where id=p_conversation;
 select email into v_email from public.customers where id=c.customer_id;
 if c.id is null or lower(trim(v_email)) is distinct from lower(trim(p_sender)) then return false;end if;
 if exists(select 1 from public.messages where provider_message_id='inbound:'||p_provider_id) then return true;end if;
 insert into public.messages(organization_id,conversation_id,sender_type,customer_id,direction,channel,body_original,subject,status,customer_visible,provider_message_id,sent_at)
 values(c.organization_id,c.id,'customer',c.customer_id,'inbound','email',left(p_body,100000),left(p_subject,300),'sent',true,'inbound:'||p_provider_id,now()) on conflict do nothing;
 update public.conversations set last_message_at=now(),updated_at=now(),status='open' where id=c.id;
 update public.luz_estimate_followups j set status='stopped',reason='Customer replied' from public.estimates e where j.estimate_id=e.id and e.customer_id=c.customer_id and e.organization_id=c.organization_id and j.status='scheduled';
 return true;
end;$$;
create function public.record_customer_email_reply(p_provider_id text,p_conversation uuid,p_sender text,p_body text,p_subject text) returns boolean
language sql security invoker set search_path='' as $$select private.record_customer_email_reply(p_provider_id,p_conversation,p_sender,p_body,p_subject);$$;
revoke all on function private.record_customer_email_reply(text,uuid,text,text,text),public.record_customer_email_reply(text,uuid,text,text,text) from public,anon,authenticated;
grant execute on function private.record_customer_email_reply(text,uuid,text,text,text),public.record_customer_email_reply(text,uuid,text,text,text) to service_role;


create table public.platform_manual_charges (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 subscription_id uuid not null references public.organization_subscriptions(id),billed_month date not null,
 amount numeric(12,2) not null check(amount>0),currency text not null,due_on date not null,
 paid_at timestamptz, payment_reference text, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 unique(organization_id,billed_month),check(extract(day from billed_month)=1)
);
alter table public.platform_manual_charges enable row level security;
revoke all on public.platform_manual_charges from public,anon,authenticated;
grant select on public.platform_manual_charges to authenticated;
create policy platform_charge_read on public.platform_manual_charges for select to authenticated using(private.can_manage_payroll(organization_id));
create function private.manage_monthly_charge(p_org uuid,p_month date,p_due date,p_charge uuid,p_reference text) returns void
language plpgsql security definer set search_path='' as $$
declare sub public.organization_subscriptions%rowtype;charge public.platform_manual_charges%rowtype;
begin
 if auth.uid() is null or not public.is_kcc_admin() then raise exception 'Only KCC Admin can manage platform charges';end if;
 if p_charge is not null then
   select * into charge from public.platform_manual_charges where id=p_charge and organization_id=p_org for update;
   if charge.id is null then raise exception 'Charge not found';end if;
   if length(trim(coalesce(p_reference,'')))<3 then raise exception 'A payment reference is required';end if;
   if charge.paid_at is not null then return;end if;
   update public.platform_manual_charges set paid_at=now(),payment_reference=left(p_reference,300) where id=charge.id;
   perform public.log_audit_event(p_org,'platform_manual_charge',charge.id,'payment_recorded',null,jsonb_build_object('reference',p_reference,'amount',charge.amount));
 else
   select * into sub from public.organization_subscriptions where organization_id=p_org and superseded_at is null;
   if sub.id is null or sub.billing_cycle<>'monthly' or sub.complimentary or sub.status<>'active' or coalesce(sub.price_snapshot,0)<=0 then raise exception 'Configure an active fixed monthly fee first';end if;
   if p_month is null or p_due is null or extract(day from p_month)<>1 or p_due<p_month then raise exception 'Invalid billing period or due date';end if;
   insert into public.platform_manual_charges(organization_id,subscription_id,billed_month,amount,currency,due_on,created_by)
   values(p_org,sub.id,p_month,sub.price_snapshot,sub.currency,p_due,auth.uid()) on conflict(organization_id,billed_month) do nothing;
 end if;
end;$$;
create function public.manage_monthly_charge(p_org uuid,p_month date default null,p_due date default null,p_charge uuid default null,p_reference text default null) returns void language sql security invoker set search_path='' as $$select private.manage_monthly_charge(p_org,p_month,p_due,p_charge,p_reference);$$;
revoke all on function private.manage_monthly_charge(uuid,date,date,uuid,text),public.manage_monthly_charge(uuid,date,date,uuid,text) from public,anon;
grant execute on function private.manage_monthly_charge(uuid,date,date,uuid,text),public.manage_monthly_charge(uuid,date,date,uuid,text) to authenticated;

create table public.technician_payments (
 id uuid primary key default gen_random_uuid(),shift_id uuid not null unique references public.technician_shifts(id),
 organization_id uuid not null references public.organizations(id),profile_id uuid not null references public.profiles(id),
 amount numeric(14,2) not null check(amount>=0),currency text not null,reference text not null,paid_at timestamptz not null default now(),recorded_by uuid not null references public.profiles(id)
);
alter table public.technician_payments enable row level security;
revoke all on public.technician_payments from public,anon,authenticated;
grant select on public.technician_payments to authenticated;
create policy technician_payment_read on public.technician_payments for select to authenticated using(private.can_manage_payroll(organization_id) or (profile_id=auth.uid() and public.is_org_member(organization_id)));
create index technician_payments_org on public.technician_payments(organization_id,paid_at);
create function private.record_technician_payment(p_shift uuid,p_reference text) returns void language plpgsql security definer set search_path='' as $$
declare s public.technician_shifts%rowtype;
begin
 select * into s from public.technician_shifts where id=p_shift for update;
 if auth.uid() is null or s.id is null or not private.can_manage_payroll(s.organization_id) then raise exception 'Not authorized';end if;
 if s.ended_at is null or s.gross_amount is null or s.currency is null then raise exception 'Close the shift with a configured pay rate first';end if;
 if length(trim(coalesce(p_reference,'')))<3 then raise exception 'Payment reference is required';end if;
 insert into public.technician_payments(shift_id,organization_id,profile_id,amount,currency,reference,recorded_by)
 values(s.id,s.organization_id,s.profile_id,s.gross_amount,s.currency,left(p_reference,300),auth.uid()) on conflict(shift_id) do nothing;
 perform public.log_audit_event(s.organization_id,'technician_shift',s.id,'payment_recorded',null,jsonb_build_object('reference',p_reference,'amount',s.gross_amount));
end;$$;
create function public.record_technician_payment(p_shift uuid,p_reference text) returns void language sql security invoker set search_path='' as $$select private.record_technician_payment(p_shift,p_reference);$$;
revoke all on function private.record_technician_payment(uuid,text),public.record_technician_payment(uuid,text) from public,anon;
grant execute on function private.record_technician_payment(uuid,text),public.record_technician_payment(uuid,text) to authenticated;

create table public.company_expenses (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 description text not null check(length(trim(description))>0),amount numeric(14,2) not null check(amount>0),currency text not null check(currency ~ '^[A-Z]{3}$'),
 paid_on date not null,category text not null check(category in ('supplies','travel','overhead','other')),
 reference text not null,created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),
 idempotency_key uuid not null unique
);
alter table public.company_expenses enable row level security;
revoke all on public.company_expenses from public,anon,authenticated;
grant select,insert on public.company_expenses to authenticated;
create policy expense_read on public.company_expenses for select to authenticated using(private.can_manage_payroll(organization_id));
create policy expense_insert on public.company_expenses for insert to authenticated with check(private.can_manage_payroll(organization_id) and created_by=auth.uid());
create index company_expenses_org_date on public.company_expenses(organization_id,paid_on desc);


create function public.get_company_cash_summary(p_org uuid,p_from date,p_to date)
returns table(currency text,collected numeric,refunded numeric,expenses numeric,payroll numeric,net numeric)
language plpgsql security invoker set search_path='' as $$
declare v_zone text;v_start timestamptz;v_end timestamptz;
begin
 if not private.can_manage_payroll(p_org) then raise exception 'Not authorized';end if;
 if p_from is null or p_to is null or p_to<p_from then raise exception 'Invalid date range';end if;
 select timezone into v_zone from public.organization_settings where organization_id=p_org;
 if v_zone is null then raise exception 'Company timezone required';end if;
 v_start:=p_from::timestamp at time zone v_zone;v_end:=(p_to+1)::timestamp at time zone v_zone;
 return query with movements as (
 select p.currency,sum(p.amount) as collected,0::numeric as refunded,0::numeric as expenses,0::numeric as payroll
 from public.payments p where p.organization_id=p_org and p.status in ('settled','reversed') and p.received_at>=v_start and p.received_at<v_end group by p.currency
 union all select p.currency,0,sum(r.amount),0,0 from public.payment_refunds r join public.payments p on p.id=r.payment_id where r.organization_id=p_org and r.status='completed' and r.refunded_at>=v_start and r.refunded_at<v_end group by p.currency
 union all select x.currency,0,0,sum(x.amount),0 from public.company_expenses x where x.organization_id=p_org and x.paid_on between p_from and p_to group by x.currency
 union all select x.currency,0,0,0,sum(x.amount) from public.technician_payments x where x.organization_id=p_org and x.paid_at>=v_start and x.paid_at<v_end group by x.currency
 ) select m.currency,sum(m.collected),sum(m.refunded),sum(m.expenses),sum(m.payroll),sum(m.collected-m.refunded-m.expenses-m.payroll) from movements m group by m.currency;
end;$$;
revoke all on function public.get_company_cash_summary(uuid,date,date) from public,anon;
grant execute on function public.get_company_cash_summary(uuid,date,date) to authenticated;
commit;
