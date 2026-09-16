-- =========================================================
-- tests/rls/phase5-company-operations-tests.sql
-- =========================================================
-- Suite reproducible — corre de punta a punta desde una base limpia
-- (con las migraciones 001-059 ya aplicadas). Cada test es una
-- consulta ejecutable real. ÚLTIMA CORRIDA EN VIVO: 18/18 PASS.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('a1100000-0000-0000-0000-000000000001','p5x-ownerA@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a1100000-0000-0000-0000-000000000002','p5x-managerA@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a1100000-0000-0000-0000-000000000003','p5x-techA@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a1100000-0000-0000-0000-000000000004','p5x-custA@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a1100000-0000-0000-0000-000000000005','p5x-ownerB@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a1100000-0000-0000-0000-000000000006','p5x-techB@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('a1200000-0000-0000-0000-00000000000a','P5X Org A','p5x-org-a','active'),
  ('a1200000-0000-0000-0000-00000000000b','P5X Org B','p5x-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (id, profile_id, organization_id, role, status) values
  ('a1300000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-00000000000a','company_owner','active'),
  ('a1300000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000002','a1200000-0000-0000-0000-00000000000a','manager','active'),
  ('a1300000-0000-0000-0000-000000000003','a1100000-0000-0000-0000-000000000003','a1200000-0000-0000-0000-00000000000a','technician','active'),
  ('a1300000-0000-0000-0000-000000000004','a1100000-0000-0000-0000-000000000004','a1200000-0000-0000-0000-00000000000a','customer','active'),
  ('a1300000-0000-0000-0000-000000000005','a1100000-0000-0000-0000-000000000005','a1200000-0000-0000-0000-00000000000b','company_owner','active'),
  ('a1300000-0000-0000-0000-000000000006','a1100000-0000-0000-0000-000000000006','a1200000-0000-0000-0000-00000000000b','technician','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('a1400000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-00000000000a','a1100000-0000-0000-0000-000000000004','C','A','a1100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('a1500000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-00000000000a','a1400000-0000-0000-0000-000000000001','V A','a1100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('a1600000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-00000000000a','a1400000-0000-0000-0000-000000000001','a1500000-0000-0000-0000-000000000001','WO A','a1100000-0000-0000-0000-000000000001');
insert into service_catalog (id, organization_id, name, active, display_order) values ('a1700000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-00000000000a','Engine Diagnostics', true, 0);
reset role;

create temporary table p5_all_results (test_name text, result text);
grant insert, select on p5_all_results to authenticated;

-- TEAM: staff de Org B no lee memberships de Org A
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into p5_all_results select 'test_01_cannot_read_other_tenant_memberships', case when count(*)=0 then 'PASS' else 'FAIL' end
from organization_memberships where organization_id = 'a1200000-0000-0000-0000-00000000000a';
reset role;

-- TEAM: owner de Org A no puede modificar membership de Org B
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform change_member_role('a1300000-0000-0000-0000-000000000006'::uuid, 'manager');
    insert into p5_all_results values ('test_02_cannot_modify_other_tenant_membership', 'FAIL (no exception)');
  exception when others then
    insert into p5_all_results values ('test_02_cannot_modify_other_tenant_membership', 'PASS');
  end;
end $$;
reset role;

-- TEAM: company_admin no puede invitar company_owner
insert into organization_memberships (id, profile_id, organization_id, role, status) values ('a1300000-0000-0000-0000-000000000007','a1100000-0000-0000-0000-000000000003','a1200000-0000-0000-0000-00000000000a','company_admin','active') on conflict do nothing;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$
begin
  begin
    perform invite_team_member('a1200000-0000-0000-0000-00000000000a', 'sneaky@example.com', 'company_owner');
    insert into p5_all_results values ('test_03_admin_cannot_invite_owner', 'FAIL (no exception)');
  exception when others then
    insert into p5_all_results values ('test_03_admin_cannot_invite_owner', 'PASS');
  end;
end $$;
reset role;

-- TEAM: manager no puede invitar a nadie
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    perform invite_team_member('a1200000-0000-0000-0000-00000000000a', 'sneaky2@example.com', 'technician');
    insert into p5_all_results values ('test_04_manager_cannot_invite', 'FAIL (no exception)');
  exception when others then
    insert into p5_all_results values ('test_04_manager_cannot_invite', 'PASS');
  end;
end $$;
reset role;

-- TEAM: nadie puede invitar kcc_admin
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform invite_team_member('a1200000-0000-0000-0000-00000000000a', 'sneaky3@example.com', 'kcc_admin');
    insert into p5_all_results values ('test_05_no_one_can_invite_kcc_admin', 'FAIL (no exception)');
  exception when others then
    insert into p5_all_results values ('test_05_no_one_can_invite_kcc_admin', 'PASS');
  end;
end $$;

-- TEAM: owner no puede cambiar su propio rol, ni siquiera él mismo
do $$
begin
  begin
    perform change_member_role('a1300000-0000-0000-0000-000000000001'::uuid, 'manager');
    insert into p5_all_results values ('test_06_owner_cannot_change_own_role', 'FAIL (no exception)');
  exception when others then
    insert into p5_all_results values ('test_06_owner_cannot_change_own_role', 'PASS');
  end;
end $$;
reset role;

-- APPOINTMENTS: manager de Org A SÍ puede crear una cita propia
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into appointments (id, organization_id, work_order_id, scheduled_start, status) values ('a1800000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-00000000000a','a1600000-0000-0000-0000-000000000001', now() + interval '1 day', 'scheduled');
reset role;
insert into p5_all_results select 'test_07_manager_can_create_own_tenant_appointment', case when count(*)=1 then 'PASS' else 'FAIL' end
from appointments where id = 'a1800000-0000-0000-0000-000000000001';

-- APPOINTMENTS: customer NO puede crear una cita
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000004","role":"authenticated"}';
do $$
begin
  begin
    insert into appointments (organization_id, work_order_id, scheduled_start, status) values ('a1200000-0000-0000-0000-00000000000a','a1600000-0000-0000-0000-000000000001', now() + interval '2 days', 'scheduled');
    insert into p5_all_results values ('test_08_customer_cannot_create_appointment', 'FAIL (insert succeeded)');
  exception when others then
    insert into p5_all_results values ('test_08_customer_cannot_create_appointment', 'PASS');
  end;
end $$;
reset role;

-- APPOINTMENTS: cross-tenant bloqueado (lectura)
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into p5_all_results select 'test_09_cross_tenant_appointment_read_blocked', case when count(*)=0 then 'PASS' else 'FAIL' end
from appointments where id = 'a1800000-0000-0000-0000-000000000001';
reset role;

-- CATALOG: owner de Org B no puede editar el catálogo de Org A
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000005","role":"authenticated"}';
update service_catalog set active = false where id = 'a1700000-0000-0000-0000-000000000001';
reset role;
insert into p5_all_results select 'test_10_cannot_edit_other_tenant_catalog', case when active = true then 'PASS' else 'FAIL' end
from service_catalog where id = 'a1700000-0000-0000-0000-000000000001';

-- SETTINGS: owner de Org B no lee settings de Org A
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into p5_all_results select 'test_11_cannot_read_other_tenant_settings', case when count(*)=0 then 'PASS' else 'FAIL' end
from organization_settings where organization_id = 'a1200000-0000-0000-0000-00000000000a';
reset role;

-- ASSIGNMENTS: manager de Org A no puede asignar técnico de Org B
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    insert into assignments (organization_id, work_order_id, technician_profile_id, assigned_by)
    values ('a1200000-0000-0000-0000-00000000000a','a1600000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000006','a1100000-0000-0000-0000-000000000002');
    insert into p5_all_results values ('test_12_cannot_assign_other_tenant_technician', 'FAIL (insert succeeded)');
  exception when others then
    insert into p5_all_results values ('test_12_cannot_assign_other_tenant_technician', 'PASS');
  end;
end $$;
reset role;

-- WORK ORDERS: transition_work_order sigue funcionando (manager tiene permiso en esta regla específica)
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000002","role":"authenticated"}';
select transition_work_order('a1600000-0000-0000-0000-000000000001', 'triage');
insert into p5_all_results select 'test_13_transition_still_works', case when current_status='triage' then 'PASS' else 'FAIL' end
from work_orders where id = 'a1600000-0000-0000-0000-000000000001';

-- WORK ORDERS: current_status no se puede mutar directo (column lock de Phase 1)
do $$
begin
  begin
    update work_orders set current_status = 'completed' where id = 'a1600000-0000-0000-0000-000000000001';
    insert into p5_all_results values ('test_14_current_status_column_lock_intact', 'FAIL (update succeeded)');
  exception when others then
    insert into p5_all_results values ('test_14_current_status_column_lock_intact', 'PASS');
  end;
end $$;
reset role;

-- PROFILE: update_company_profile no toca slug/status
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select update_company_profile('a1200000-0000-0000-0000-00000000000a', 'Renamed Co', '+1-555-0000', 'x@example.com');
reset role;
insert into p5_all_results select 'test_15_profile_update_protects_slug_status', case when slug='p5x-org-a' and status='active' and name='Renamed Co' then 'PASS' else 'FAIL' end
from organizations where id = 'a1200000-0000-0000-0000-00000000000a';

-- REGRESIÓN Phase 3B: get_assigned_technician_public_info sigue funcionando
update profiles set full_name = 'Tech A' where id = 'a1100000-0000-0000-0000-000000000003';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into assignments (organization_id, work_order_id, technician_profile_id, assigned_by) values ('a1200000-0000-0000-0000-00000000000a','a1600000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000003','a1100000-0000-0000-0000-000000000001');
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into p5_all_results select 'test_16_regression_p3b_technician_rpc', case when full_name='Tech A' then 'PASS' else 'FAIL' end
from get_assigned_technician_public_info('a1600000-0000-0000-0000-000000000001');
reset role;

-- REGRESIÓN Phase 4B: service_requests sigue funcionando (crear + cancelar)
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into service_requests (id, organization_id, customer_id, vessel_id, title, client_generated_id, created_by)
values ('a1900000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-00000000000a','a1400000-0000-0000-0000-000000000001','a1500000-0000-0000-0000-000000000001','Regression SR', gen_random_uuid(), 'a1100000-0000-0000-0000-000000000004');
select cancel_service_request('a1900000-0000-0000-0000-000000000001'::uuid);
reset role;
insert into p5_all_results select 'test_17_regression_p4b_service_request_lifecycle', case when status='cancelled' then 'PASS' else 'FAIL' end
from service_requests where id = 'a1900000-0000-0000-0000-000000000001';

-- BONUS: nadie (ni siquiera vía el flujo normal) puede leer profiles cruzando organización
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into p5_all_results select 'test_18_cross_org_profile_read_still_blocked', case when count(*)=0 then 'PASS' else 'FAIL' end
from profiles where id = 'a1100000-0000-0000-0000-000000000003';
reset role;

select * from p5_all_results order by test_name;

-- CLEANUP
delete from domain_events where organization_id in ('a1200000-0000-0000-0000-00000000000a','a1200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('a1200000-0000-0000-0000-00000000000a','a1200000-0000-0000-0000-00000000000b');
delete from service_requests where organization_id = 'a1200000-0000-0000-0000-00000000000a';
delete from assignments where organization_id = 'a1200000-0000-0000-0000-00000000000a';
delete from appointments where organization_id = 'a1200000-0000-0000-0000-00000000000a';
delete from work_order_status_history where work_order_id = 'a1600000-0000-0000-0000-000000000001';
delete from service_catalog where organization_id = 'a1200000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id = 'a1200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = 'a1200000-0000-0000-0000-00000000000a';
delete from customers where organization_id = 'a1200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id in ('a1200000-0000-0000-0000-00000000000a','a1200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('a1200000-0000-0000-0000-00000000000a','a1200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p5x-%@rls-test.local';
delete from auth.users where email like 'p5x-%@rls-test.local';
select 'phase5 suite cleanup complete' as status;
