begin;
-- Payroll settings are separate from the broadly-readable technician skill profile.
-- The old relationship rates are not silently converted to approved payroll terms.
create schema if not exists private;
create or replace function private.can_manage_payroll(p_org uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select auth.uid() is not null and (public.is_kcc_admin() or exists(
 select 1 from public.organization_memberships where profile_id=auth.uid() and organization_id=p_org
 and status='active' and role in ('company_owner','company_admin')));
$$;
revoke all on function private.can_manage_payroll(uuid) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.can_manage_payroll(uuid) to authenticated;

create table public.technician_pay_terms (
 organization_id uuid not null references public.organizations(id),
 profile_id uuid not null references public.profiles(id),
 pay_type text not null check(pay_type in ('hourly','daily')),
 pay_rate numeric(12,2) not null check(pay_rate>=0 and pay_rate<10000000),
 currency text not null check(currency ~ '^[A-Z]{3}$'),
 pay_cycle text not null check(pay_cycle in ('weekly','biweekly','monthly')),
 cycle_anchor date not null,
 updated_at timestamptz not null default now(),
 updated_by uuid not null references public.profiles(id),
 primary key(organization_id,profile_id)
);
alter table public.technician_pay_terms enable row level security;
revoke all on public.technician_pay_terms from public,anon,authenticated;
grant select on public.technician_pay_terms to authenticated;
create policy payroll_read on public.technician_pay_terms for select to authenticated using(
 private.can_manage_payroll(organization_id) or (profile_id=auth.uid() and public.is_org_member(organization_id))
);
create index technician_pay_terms_profile on public.technician_pay_terms(profile_id);

create table public.technician_shifts (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 profile_id uuid not null references public.profiles(id),
 work_date date not null,
 started_at timestamptz not null default now(),
 ended_at timestamptz,
 paused_at timestamptz,
 break_seconds numeric not null default 0 check(break_seconds>=0),
 paid_seconds numeric check(paid_seconds>=0),
 pay_type text check(pay_type in ('hourly','daily')),
 pay_rate numeric(12,2),
 currency text,
 gross_amount numeric(14,2),
 check(ended_at is null or ended_at>=started_at),
 check(ended_at is null or paused_at is null),
 unique(organization_id,profile_id,work_date)
);
create unique index technician_one_open_shift on public.technician_shifts(profile_id) where ended_at is null;
create index technician_shifts_org_date on public.technician_shifts(organization_id,work_date desc);
alter table public.technician_shifts enable row level security;
revoke all on public.technician_shifts from public,anon,authenticated;
grant select on public.technician_shifts to authenticated;
create policy shift_read on public.technician_shifts for select to authenticated using(
 private.can_manage_payroll(organization_id) or (profile_id=auth.uid() and public.is_org_member(organization_id))
);

create function private.save_technician_pay_terms(p_org uuid,p_profile uuid,p_type text,p_rate numeric,p_currency text,p_cycle text,p_anchor date)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.can_manage_payroll(p_org) then raise exception 'Not authorized'; end if;
 if not exists(select 1 from public.organization_memberships where organization_id=p_org and profile_id=p_profile and role='technician' and status='active') then raise exception 'Active technician membership required'; end if;
 insert into public.technician_pay_terms(organization_id,profile_id,pay_type,pay_rate,currency,pay_cycle,cycle_anchor,updated_by)
 values(p_org,p_profile,p_type,p_rate,p_currency,p_cycle,p_anchor,auth.uid())
 on conflict(organization_id,profile_id) do update set pay_type=excluded.pay_type,pay_rate=excluded.pay_rate,currency=excluded.currency,pay_cycle=excluded.pay_cycle,cycle_anchor=excluded.cycle_anchor,updated_by=auth.uid(),updated_at=now();
 perform public.log_audit_event(p_org,'technician_pay_terms',p_profile,'pay_terms_updated',null,jsonb_build_object('pay_type',p_type,'pay_rate',p_rate,'currency',p_currency,'pay_cycle',p_cycle));
end; $$;
create function public.save_technician_pay_terms(p_org uuid,p_profile uuid,p_type text,p_rate numeric,p_currency text,p_cycle text,p_anchor date)
returns void language sql security invoker set search_path='' as $$ select private.save_technician_pay_terms(p_org,p_profile,p_type,p_rate,p_currency,p_cycle,p_anchor); $$;
revoke all on function private.save_technician_pay_terms(uuid,uuid,text,numeric,text,text,date), public.save_technician_pay_terms(uuid,uuid,text,numeric,text,text,date) from public,anon;
grant execute on function private.save_technician_pay_terms(uuid,uuid,text,numeric,text,text,date), public.save_technician_pay_terms(uuid,uuid,text,numeric,text,text,date) to authenticated;

create function private.change_technician_shift(p_org uuid,p_action text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_shift public.technician_shifts%rowtype; v_terms public.technician_pay_terms%rowtype;
 v_day date; v_zone text; v_now timestamptz:=clock_timestamp(); v_seconds numeric;
begin
 if auth.uid() is null or not public.is_org_active(p_org) or not exists(select 1 from public.organization_memberships where organization_id=p_org and profile_id=auth.uid() and role='technician' and status='active') then raise exception 'Active technician membership required'; end if;
 if p_action not in ('start','pause','resume','end') or p_action is null then raise exception 'Invalid shift action'; end if;
 -- Serialize all clock actions for this person, including concurrent requests across tenants.
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
 perform public.log_audit_event(p_org,'technician_shift',v_shift.id,'shift_'||p_action,null,jsonb_build_object('profile_id',auth.uid(),'at',v_now));
 return v_shift.id;
end; $$;
create function public.change_technician_shift(p_org uuid,p_action text) returns uuid
language sql security invoker set search_path='' as $$ select private.change_technician_shift(p_org,p_action); $$;
revoke all on function private.change_technician_shift(uuid,text), public.change_technician_shift(uuid,text) from public,anon;
grant execute on function private.change_technician_shift(uuid,text), public.change_technician_shift(uuid,text) to authenticated;
commit;
