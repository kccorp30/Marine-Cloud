-- Optional company branding for the command center. Apply after migrations/000..268.
-- Preserves all existing organization mutation restrictions and RLS policies.
begin;
create or replace function public.update_company_logo(p_organization_id uuid, p_logo text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not (public.is_kcc_admin() or exists (
    select 1 from public.organization_memberships m join public.organizations o on o.id=m.organization_id
    where m.organization_id=p_organization_id and m.profile_id=auth.uid()
      and m.role in ('company_owner','company_admin') and m.status='active'
      and o.status='active' and o.deleted_at is null
  )) then raise exception 'Company branding is not authorized'; end if;
  if p_logo is null or length(p_logo)>150000 or p_logo !~ '^data:image/webp;base64,[A-Za-z0-9+/=]+$' then
    raise exception 'Invalid logo';
  end if;
  update public.organizations set branding_json=jsonb_set(coalesce(branding_json,'{}'::jsonb),'{logo_url}',to_jsonb(p_logo)),updated_at=now()
  where id=p_organization_id;
end;
$$;
revoke all on function public.update_company_logo(uuid,text) from public,anon;
grant execute on function public.update_company_logo(uuid,text) to authenticated;

-- Reuse the notification engine: assignments notify the actual assigned technicians.
insert into public.notification_rules (organization_id,event_type,severity,recipient_strategy,title_template,body_template,acknowledgement_required)
select null,'TECHNICIAN_ASSIGNED','action_required','assigned_technician','New work assignment','Open your assigned work order to review instructions and your day plan.',true
where not exists(select 1 from public.notification_rules where organization_id is null and event_type='TECHNICIAN_ASSIGNED' and recipient_strategy='assigned_technician' and is_active);

insert into public.notification_rules (organization_id,event_type,severity,recipient_strategy,title_template,body_template,acknowledgement_required)
select null,'APPOINTMENT_RESCHEDULED','action_required','assigned_technician','Schedule updated','Your appointment was rescheduled. Review your day plan before traveling.',true
where not exists(select 1 from public.notification_rules where organization_id is null and event_type='APPOINTMENT_RESCHEDULED' and recipient_strategy='assigned_technician' and is_active);


-- Link a newly activated customer using the verified account identity only.
-- Ambiguous email matches never auto-link; the company must resolve them.
create or replace function public.link_customer_account(p_organization_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_email text; v_customer uuid; v_count int;
begin
 if auth.uid() is null or not exists(select 1 from organization_memberships where organization_id=p_organization_id and profile_id=auth.uid() and role='customer' and status='active') then raise exception 'Customer membership required'; end if;
 select lower(trim(email)) into v_email from auth.users where id=auth.uid() and email_confirmed_at is not null;
 if v_email is null then raise exception 'Verified email required'; end if;
 select count(*) into v_count from customers where organization_id=p_organization_id and lower(trim(email))=v_email;
 if v_count<>1 then raise exception 'The company must finish linking your customer record'; end if;
 select id into v_customer from customers where organization_id=p_organization_id and lower(trim(email))=v_email and (profile_id is null or profile_id=auth.uid()) for update;
 if v_customer is null then raise exception 'Customer record is already linked'; end if;
 update customers set profile_id=auth.uid() where id=v_customer;
 return v_customer;
end; $$;
revoke all on function public.link_customer_account(uuid) from public,anon;
grant execute on function public.link_customer_account(uuid) to authenticated;
commit;
