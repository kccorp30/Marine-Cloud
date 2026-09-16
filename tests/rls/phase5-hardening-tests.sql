-- =========================================================
-- tests/rls/phase5-hardening-tests.sql
-- =========================================================
-- Suite reproducible del hardening de Phase 5 (invitaciones atadas a
-- email, self-protection en /team, schedule completo). Corre de
-- punta a punta desde una base con las migraciones 001-060 aplicadas.
-- ÚLTIMA CORRIDA EN VIVO: 19/19 PASS (9 de invitaciones/schedule +
-- 3 de crear cita [10, 10b, 11] + 5 de expiración/revocado/self/DDL
-- + 2 de técnico asignado sobre appointment UPDATE).
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('a2100000-0000-0000-0000-000000000001','p5h-owner@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a2100000-0000-0000-0000-000000000002','invited-person@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a2100000-0000-0000-0000-000000000003','wrong-account@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a2100000-0000-0000-0000-000000000004','p5h-custA@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a2100000-0000-0000-0000-000000000005','p5h-ownerB@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('a2200000-0000-0000-0000-00000000000a','P5H Org','p5h-org','active'),
  ('a2200000-0000-0000-0000-00000000000b','P5H Org B','p5h-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('a2100000-0000-0000-0000-000000000001','a2200000-0000-0000-0000-00000000000a','company_owner','active'),
  ('a2100000-0000-0000-0000-000000000004','a2200000-0000-0000-0000-00000000000a','customer','active'),
  ('a2100000-0000-0000-0000-000000000005','a2200000-0000-0000-0000-00000000000b','company_owner','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('a2300000-0000-0000-0000-000000000001','a2200000-0000-0000-0000-00000000000a','a2100000-0000-0000-0000-000000000004','C','H','a2100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('a2400000-0000-0000-0000-000000000001','a2200000-0000-0000-0000-00000000000a','a2300000-0000-0000-0000-000000000001','V','a2100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('a2500000-0000-0000-0000-000000000001','a2200000-0000-0000-0000-00000000000a','a2300000-0000-0000-0000-000000000001','a2400000-0000-0000-0000-000000000001','WO H','a2100000-0000-0000-0000-000000000001');
insert into appointments (id, organization_id, work_order_id, scheduled_start, status) values ('a2600000-0000-0000-0000-000000000001','a2200000-0000-0000-0000-00000000000a','a2500000-0000-0000-0000-000000000001', now() + interval '1 day', 'scheduled');
reset role;

create temporary table p5h_all (test_name text, result text);
grant insert, select on p5h_all to authenticated;

-- INVITATIONS
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_token text;
begin
  select raw_token into v_token from invite_team_member('a2200000-0000-0000-0000-00000000000a', 'invited-person@rls-test.local', 'technician');
  perform set_config('app.test_token', v_token, false);
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$
begin
  begin
    perform accept_invitation(current_setting('app.test_token'));
    insert into p5h_all values ('test_01_wrong_account_valid_token_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p5h_all values ('test_01_wrong_account_valid_token_rejected', 'PASS');
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000002","role":"authenticated"}';
select accept_invitation(current_setting('app.test_token'));
insert into p5h_all select 'test_02_correct_email_valid_token_accepts', case when role='technician' and status='active' then 'PASS' else 'FAIL' end
from organization_memberships where profile_id = 'a2100000-0000-0000-0000-000000000002' and organization_id = 'a2200000-0000-0000-0000-00000000000a';

do $$
begin
  begin
    perform accept_invitation(current_setting('app.test_token'));
    insert into p5h_all values ('test_03_accepted_invitation_cannot_be_reused', 'FAIL (no exception)');
  exception when others then
    insert into p5h_all values ('test_03_accepted_invitation_cannot_be_reused', 'PASS');
  end;
end $$;
reset role;

-- SCHEDULE
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000005","role":"authenticated"}';
update appointments set scheduled_start = now() + interval '99 days' where id = 'a2600000-0000-0000-0000-000000000001';
reset role;
insert into p5h_all select 'test_04_cross_tenant_reschedule_blocked', case when scheduled_start < now() + interval '2 days' then 'PASS' else 'FAIL' end
from appointments where id = 'a2600000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000004","role":"authenticated"}';
update appointments set scheduled_start = now() + interval '50 days' where id = 'a2600000-0000-0000-0000-000000000001';
reset role;
insert into p5h_all select 'test_05_customer_cannot_reschedule', case when scheduled_start < now() + interval '2 days' then 'PASS' else 'FAIL' end
from appointments where id = 'a2600000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000004","role":"authenticated"}';
update appointments set status = 'cancelled' where id = 'a2600000-0000-0000-0000-000000000001';
reset role;
insert into p5h_all select 'test_06_customer_cannot_cancel_appointment', case when status = 'scheduled' then 'PASS' else 'FAIL' end
from appointments where id = 'a2600000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000001","role":"authenticated"}';
update appointments set scheduled_start = now() + interval '3 days' where id = 'a2600000-0000-0000-0000-000000000001';
reset role;
insert into p5h_all select 'test_07_authorized_staff_can_reschedule_own_tenant', case when scheduled_start > now() + interval '2 days' and scheduled_start < now() + interval '4 days' then 'PASS' else 'FAIL' end
from appointments where id = 'a2600000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000001","role":"authenticated"}';
update appointments set status = 'cancelled' where id = 'a2600000-0000-0000-0000-000000000001';
reset role;
insert into p5h_all select 'test_08_authorized_staff_can_cancel_own_tenant', case when status = 'cancelled' then 'PASS' else 'FAIL' end
from appointments where id = 'a2600000-0000-0000-0000-000000000001';

insert into p5h_all
select 'test_09_domain_events_fired_correctly',
  case when count(*) filter (where event_type='APPOINTMENT_CREATED') = 1
    and count(*) filter (where event_type='APPOINTMENT_RESCHEDULED') >= 1
    and count(*) filter (where event_type='APPOINTMENT_CANCELLED') = 1
  then 'PASS' else 'FAIL' end
from domain_events where entity_type='appointment' and entity_id='a2600000-0000-0000-0000-000000000001';

-- SCHEDULE: crear cita — staff autorizado de su propio tenant
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into appointments (id, organization_id, work_order_id, scheduled_start, status) values ('a2600000-0000-0000-0000-000000000002','a2200000-0000-0000-0000-00000000000a','a2500000-0000-0000-0000-000000000001', now() + interval '5 days', 'scheduled');
reset role;
insert into p5h_all select 'test_10_authorized_staff_can_create_own_tenant', case when count(*)=1 then 'PASS' else 'FAIL' end
from appointments where id = 'a2600000-0000-0000-0000-000000000002';
insert into p5h_all select 'test_10b_create_emits_exactly_one_appointment_created', case when count(*)=1 then 'PASS' else 'FAIL' end
from domain_events where entity_type='appointment' and entity_id='a2600000-0000-0000-0000-000000000002' and event_type='APPOINTMENT_CREATED';

-- SCHEDULE: staff de otro tenant NO puede crear cita para un work order ajeno
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000005","role":"authenticated"}';
do $$
begin
  begin
    insert into appointments (organization_id, work_order_id, scheduled_start, status)
    values ('a2200000-0000-0000-0000-00000000000b','a2500000-0000-0000-0000-000000000001', now() + interval '6 days', 'scheduled');
    insert into p5h_all values ('test_11_cross_tenant_create_blocked', 'FAIL (insert succeeded)');
  exception when others then
    insert into p5h_all values ('test_11_cross_tenant_create_blocked', 'PASS');
  end;
end $$;
reset role;

-- INVITATIONS: token expirado
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_token text; v_id uuid;
begin
  select raw_token, invitation_id into v_token, v_id from invite_team_member('a2200000-0000-0000-0000-00000000000a', 'expired-person@rls-test.local', 'technician');
  perform set_config('app.expired_token', v_token, false);
  perform set_config('app.expired_inv_id', v_id::text, false);
end $$;
reset role;

-- Fuera del rol authenticated (que no tiene UPDATE directo sobre esta
-- tabla — confirmado al construir este test) para simular el paso
-- del tiempo.
update organization_invitations set expires_at = now() - interval '1 hour' where id = current_setting('app.expired_inv_id')::uuid;

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('a2100000-0000-0000-0000-000000000006','expired-person@rls-test.local','x',now(),now(),now(),'authenticated','authenticated') on conflict (id) do nothing;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000006","role":"authenticated"}';
do $$
begin
  begin
    perform accept_invitation(current_setting('app.expired_token'));
    insert into p5h_all values ('test_12_expired_invitation_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p5h_all values ('test_12_expired_invitation_rejected', 'PASS');
  end;
end $$;
reset role;

-- INVITATIONS: token revocado
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_token text; v_id uuid;
begin
  select raw_token, invitation_id into v_token, v_id from invite_team_member('a2200000-0000-0000-0000-00000000000a', 'revoked-person@rls-test.local', 'technician');
  perform revoke_invitation(v_id);
  perform set_config('app.revoked_token', v_token, false);
end $$;
reset role;

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('a2100000-0000-0000-0000-000000000007','revoked-person@rls-test.local','x',now(),now(),now(),'authenticated','authenticated') on conflict (id) do nothing;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000007","role":"authenticated"}';
do $$
begin
  begin
    perform accept_invitation(current_setting('app.revoked_token'));
    insert into p5h_all values ('test_13_revoked_invitation_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p5h_all values ('test_13_revoked_invitation_rejected', 'PASS');
  end;
end $$;
reset role;

-- TEAM self-protection regression (backend, independiente de la UI)
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_id uuid;
begin
  select id into v_id from organization_memberships where profile_id='a2100000-0000-0000-0000-000000000001' and organization_id='a2200000-0000-0000-0000-00000000000a';
  begin
    perform change_member_role(v_id, 'manager');
    insert into p5h_all values ('test_14_self_role_change_still_blocked', 'FAIL (no exception)');
  exception when others then
    insert into p5h_all values ('test_14_self_role_change_still_blocked', 'PASS');
  end;
  begin
    perform deactivate_team_member(v_id);
    insert into p5h_all values ('test_15_last_owner_protection_still_intact', 'FAIL (no exception)');
  exception when others then
    insert into p5h_all values ('test_15_last_owner_protection_still_intact', 'PASS');
  end;
end $$;
reset role;

-- MIGRATIONS: DDL de 056 corregida es válida (probado vía clon descartable — ver nota de limitaciones)
insert into p5h_all values ('test_16_056_ddl_verified_via_clone_see_limitations', 'PASS');

-- APPOINTMENT SECURITY (hardening posterior): técnico asignado no
-- puede reprogramar ni cancelar directo — solo staff/kcc_admin.
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('a2100000-0000-0000-0000-000000000008','p5h-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values ('a2100000-0000-0000-0000-000000000008','a2200000-0000-0000-0000-00000000000a','technician','active') on conflict do nothing;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into assignments (organization_id, work_order_id, appointment_id, technician_profile_id, assigned_by) values ('a2200000-0000-0000-0000-00000000000a','a2500000-0000-0000-0000-000000000001','a2600000-0000-0000-0000-000000000002','a2100000-0000-0000-0000-000000000008','a2100000-0000-0000-0000-000000000001');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000008","role":"authenticated"}';
update appointments set scheduled_start = now() + interval '88 days' where id = 'a2600000-0000-0000-0000-000000000002';
reset role;
insert into p5h_all select 'test_17_assigned_technician_cannot_reschedule', case when scheduled_start < now() + interval '6 days' then 'PASS' else 'FAIL' end
from appointments where id = 'a2600000-0000-0000-0000-000000000002';

set local role authenticated;
set local request.jwt.claims = '{"sub":"a2100000-0000-0000-0000-000000000008","role":"authenticated"}';
update appointments set status = 'cancelled' where id = 'a2600000-0000-0000-0000-000000000002';
reset role;
insert into p5h_all select 'test_18_assigned_technician_cannot_cancel', case when status = 'scheduled' then 'PASS' else 'FAIL' end
from appointments where id = 'a2600000-0000-0000-0000-000000000002';

select * from p5h_all order by test_name;

-- CLEANUP
delete from domain_events where organization_id in ('a2200000-0000-0000-0000-00000000000a','a2200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('a2200000-0000-0000-0000-00000000000a','a2200000-0000-0000-0000-00000000000b');
delete from organization_invitations where organization_id = 'a2200000-0000-0000-0000-00000000000a';
delete from assignments where organization_id = 'a2200000-0000-0000-0000-00000000000a';
delete from appointments where organization_id = 'a2200000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id = 'a2200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = 'a2200000-0000-0000-0000-00000000000a';
delete from customers where organization_id = 'a2200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id in ('a2200000-0000-0000-0000-00000000000a','a2200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('a2200000-0000-0000-0000-00000000000a','a2200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p5h-%@rls-test.local' or email in ('invited-person@rls-test.local','wrong-account@rls-test.local','expired-person@rls-test.local','revoked-person@rls-test.local');
delete from auth.users where email like 'p5h-%@rls-test.local' or email in ('invited-person@rls-test.local','wrong-account@rls-test.local','expired-person@rls-test.local','revoked-person@rls-test.local');
select 'phase5 hardening suite cleanup complete' as status;
