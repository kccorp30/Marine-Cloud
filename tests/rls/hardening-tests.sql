-- =========================================================
-- tests/rls/hardening-tests.sql
-- =========================================================
-- Pruebas del hardening de seguridad post-Phase 1. Cubre los 10
-- casos (A-J) pedidos explícitamente, más el hallazgo adicional
-- (TEST J reveló que el bloqueo de columna original nunca funcionó
-- — ver migración 028).
--
-- Resultados de la última corrida en vivo: 10/10 PASS.
-- Además: se re-corrieron completas tests/rls/phase0-rls-tests.sql
-- (11/11 PASS) y tests/rls/phase1-rls-tests.sql (todas PASS) para
-- confirmar cero regresiones.
-- =========================================================

-- FIXTURES
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('a0000000-0000-0000-0000-000000000001','h-admin-a@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a0000000-0000-0000-0000-000000000002','h-tech-a1@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a0000000-0000-0000-0000-000000000003','h-tech-a2@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a0000000-0000-0000-0000-000000000004','h-cust-a1@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a0000000-0000-0000-0000-000000000005','h-cust-a2@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a0000000-0000-0000-0000-000000000006','h-admin-b@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a0000000-0000-0000-0000-000000000007','h-tech-b1@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a0000000-0000-0000-0000-000000000008','h-kcc@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;

insert into organizations (id, name, slug, status) values
  ('b0000000-0000-0000-0000-00000000000a','Hardening Org A','hardening-org-a','active'),
  ('b0000000-0000-0000-0000-00000000000b','Hardening Org B','hardening-org-b','active')
on conflict (id) do nothing;

insert into organization_memberships (profile_id, organization_id, role, status) values
  ('a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-00000000000a','company_admin','active'),
  ('a0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-00000000000a','technician','active'),
  ('a0000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-00000000000a','technician','active'),
  ('a0000000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-00000000000a','customer','active'),
  ('a0000000-0000-0000-0000-000000000005','b0000000-0000-0000-0000-00000000000a','customer','active'),
  ('a0000000-0000-0000-0000-000000000006','b0000000-0000-0000-0000-00000000000b','company_admin','active'),
  ('a0000000-0000-0000-0000-000000000007','b0000000-0000-0000-0000-00000000000b','technician','active'),
  ('a0000000-0000-0000-0000-000000000008','b0000000-0000-0000-0000-00000000000a','kcc_admin','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated"}';

insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values
  ('c0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-000000000004','Cust','One','a0000000-0000-0000-0000-000000000001'),
  ('c0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-000000000005','Cust','Two','a0000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;

insert into vessels (id, organization_id, current_customer_id, name, created_by) values
  ('d0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-00000000000a','c0000000-0000-0000-0000-000000000001','Vessel WO1','a0000000-0000-0000-0000-000000000001'),
  ('d0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-00000000000a','c0000000-0000-0000-0000-000000000001','Vessel WO2','a0000000-0000-0000-0000-000000000001'),
  ('d0000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-00000000000a','c0000000-0000-0000-0000-000000000001','Vessel WO3','a0000000-0000-0000-0000-000000000001'),
  ('d0000000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-00000000000a','c0000000-0000-0000-0000-000000000001','Vessel WO4','a0000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;

insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values
  ('e0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-00000000000a','c0000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-000000000001','WO1 - test A','a0000000-0000-0000-0000-000000000001'),
  ('e0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-00000000000a','c0000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-000000000002','WO2 - test B','a0000000-0000-0000-0000-000000000001'),
  ('e0000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-00000000000a','c0000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-000000000003','WO3 - test C','a0000000-0000-0000-0000-000000000001'),
  ('e0000000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-00000000000a','c0000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-000000000004','WO4 - test D','a0000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;

select transition_work_order('e0000000-0000-0000-0000-000000000001','triage');
select transition_work_order('e0000000-0000-0000-0000-000000000001','estimate');
select transition_work_order('e0000000-0000-0000-0000-000000000001','awaiting_approval');
select transition_work_order('e0000000-0000-0000-0000-000000000001','scheduled');
select transition_work_order('e0000000-0000-0000-0000-000000000001','technician_assigned');

select transition_work_order('e0000000-0000-0000-0000-000000000002','triage');
select transition_work_order('e0000000-0000-0000-0000-000000000002','estimate');
select transition_work_order('e0000000-0000-0000-0000-000000000002','awaiting_approval');
select transition_work_order('e0000000-0000-0000-0000-000000000002','scheduled');
select transition_work_order('e0000000-0000-0000-0000-000000000002','technician_assigned');

select transition_work_order('e0000000-0000-0000-0000-000000000003','triage');
select transition_work_order('e0000000-0000-0000-0000-000000000003','estimate');
select transition_work_order('e0000000-0000-0000-0000-000000000003','awaiting_approval');

select transition_work_order('e0000000-0000-0000-0000-000000000004','triage');
select transition_work_order('e0000000-0000-0000-0000-000000000004','estimate');
select transition_work_order('e0000000-0000-0000-0000-000000000004','awaiting_approval');

insert into assignments (organization_id, work_order_id, technician_profile_id, assigned_by)
values ('b0000000-0000-0000-0000-00000000000a','e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001');
reset role;

-- TEST A: technician asignado ejecuta transición permitida
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select transition_work_order('e0000000-0000-0000-0000-000000000001', 'en_route');
select 'test_A_assigned_technician_can_transition' as test, case when current_status='en_route' then 'PASS' else 'FAIL' end as result
from work_orders where id = 'e0000000-0000-0000-0000-000000000001';
reset role;

-- TEST B: technician del mismo tenant, NO asignado, bloqueado aunque conozca el UUID
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000003","role":"authenticated"}';
create temporary table if not exists test_results (test_name text, result text);
do $$
begin
  begin
    perform transition_work_order('e0000000-0000-0000-0000-000000000002', 'en_route');
    insert into test_results values ('test_B_unassigned_technician_blocked', 'FAIL (call succeeded)');
  exception when others then
    insert into test_results values ('test_B_unassigned_technician_blocked', 'PASS');
  end;
end $$;
reset role;

-- TEST C: customer dueño ejecuta transición permitida
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select transition_work_order('e0000000-0000-0000-0000-000000000003', 'scheduled');
insert into test_results
select 'test_C_owner_customer_can_transition', case when current_status='scheduled' then 'PASS' else 'FAIL' end
from work_orders where id = 'e0000000-0000-0000-0000-000000000003';
reset role;

-- TEST D: otro customer del mismo tenant, NO dueño, bloqueado
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000005","role":"authenticated"}';
do $$
begin
  begin
    perform transition_work_order('e0000000-0000-0000-0000-000000000004', 'scheduled');
    insert into test_results values ('test_D_non_owner_customer_blocked', 'FAIL (call succeeded)');
  exception when others then
    insert into test_results values ('test_D_non_owner_customer_blocked', 'PASS');
  end;
end $$;
reset role;

-- TEST E: admin Org A no puede crear vessel con customer de Org B
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000006","role":"authenticated"}';
insert into customers (id, organization_id, first_name, last_name, created_by)
values ('c0000000-0000-0000-0000-00000000000b','b0000000-0000-0000-0000-00000000000b','Org','B','a0000000-0000-0000-0000-000000000006')
on conflict (id) do nothing;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    insert into vessels (organization_id, current_customer_id, name)
    values ('b0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-00000000000b', 'Cross-tenant vessel');
    insert into test_results values ('test_E_vessel_cross_tenant_customer_blocked', 'FAIL (insert succeeded)');
  exception when foreign_key_violation then
    insert into test_results values ('test_E_vessel_cross_tenant_customer_blocked', 'PASS');
  end;
end $$;
reset role;

-- TEST F: work order de Org A apuntando a customer/vessel de Org B
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    insert into work_orders (organization_id, customer_id, vessel_id, title)
    values ('b0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-00000000000b', 'd0000000-0000-0000-0000-000000000001', 'Cross-tenant WO');
    insert into test_results values ('test_F_work_order_cross_tenant_blocked', 'FAIL (insert succeeded)');
  exception when foreign_key_violation then
    insert into test_results values ('test_F_work_order_cross_tenant_blocked', 'PASS');
  end;
end $$;
reset role;

-- TEST G: no puede asignarse a un work order de Org A un technician que solo pertenece a Org B
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    insert into assignments (organization_id, work_order_id, technician_profile_id, assigned_by)
    values ('b0000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000001');
    insert into test_results values ('test_G_cross_tenant_technician_assignment_blocked', 'FAIL (insert succeeded)');
  exception when others then
    insert into test_results values ('test_G_cross_tenant_technician_assignment_blocked', 'PASS');
  end;
end $$;
reset role;

-- TEST H: kcc_admin conserva acceso cross-tenant expreso
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000006","role":"authenticated"}';
insert into vessels (id, organization_id, current_customer_id, name)
values ('d0000000-0000-0000-0000-00000000000b','b0000000-0000-0000-0000-00000000000b','c0000000-0000-0000-0000-00000000000b','Vessel Org B')
on conflict (id) do nothing;
insert into work_orders (id, organization_id, customer_id, vessel_id, title)
values ('e0000000-0000-0000-0000-00000000000b','b0000000-0000-0000-0000-00000000000b','c0000000-0000-0000-0000-00000000000b','d0000000-0000-0000-0000-00000000000b','WO Org B')
on conflict (id) do nothing;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000008","role":"authenticated"}';
select transition_work_order('e0000000-0000-0000-0000-00000000000b', 'triage');
insert into test_results
select 'test_H_kcc_admin_cross_tenant_transition', case when current_status='triage' then 'PASS' else 'FAIL' end
from work_orders where id = 'e0000000-0000-0000-0000-00000000000b';
reset role;

-- TEST I: dos recursos con UUID válido pero organization_id incompatibles, rechazados por DB
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    insert into appointments (organization_id, work_order_id, scheduled_start)
    values ('b0000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-00000000000b', now());
    insert into test_results values ('test_I_incompatible_org_ids_rejected', 'FAIL (insert succeeded)');
  exception when foreign_key_violation then
    insert into test_results values ('test_I_incompatible_org_ids_rejected', 'PASS');
  end;
end $$;
reset role;

-- TEST J: current_status sigue sin poder modificarse directo por authenticated
-- (ver migración 028 — el bloqueo original NUNCA funcionó hasta esa corrección)
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    update work_orders set current_status = 'completed' where id = 'e0000000-0000-0000-0000-000000000001';
    insert into test_results values ('test_J_current_status_column_locked', 'FAIL (update succeeded)');
  exception when insufficient_privilege then
    insert into test_results values ('test_J_current_status_column_locked', 'PASS');
  end;
end $$;
reset role;

select * from test_results order by test_name;

-- CLEANUP
delete from work_order_status_history where work_order_id in (
  'e0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000002',
  'e0000000-0000-0000-0000-000000000003','e0000000-0000-0000-0000-000000000004',
  'e0000000-0000-0000-0000-00000000000b'
);
delete from domain_events where organization_id in ('b0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('b0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b');
delete from assignments where organization_id in ('b0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b');
delete from work_orders where organization_id in ('b0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b');
delete from vessels where organization_id in ('b0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b');
delete from customers where organization_id in ('b0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b');
delete from organization_memberships where organization_id in ('b0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b');
delete from organizations where id in ('b0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b');
delete from profiles where email like 'h-%@rls-test.local';
delete from auth.users where email like 'h-%@rls-test.local';
select 'cleanup complete' as status;
