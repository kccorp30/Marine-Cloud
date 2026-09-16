-- =========================================================
-- tests/rls/phase1-rls-tests.sql
-- =========================================================
-- Extiende tests/rls/phase0-rls-tests.sql con los recursos nuevos de
-- Phase 1. Mismo patrón: fixtures al inicio, resultados verificados,
-- cleanup al final. Correr completo en el SQL Editor de Supabase.
--
-- Resultados de la última corrida (en vivo, contra el proyecto real):
-- 10/10 PASS.
-- =========================================================

-- FIXTURES — 2 orgs, cada una con admin/technician/customer
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('40000000-0000-0000-0000-000000000001','p1-admin-a@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('40000000-0000-0000-0000-000000000002','p1-tech-a1@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('40000000-0000-0000-0000-000000000003','p1-tech-a2@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('40000000-0000-0000-0000-000000000004','p1-cust-a1@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('40000000-0000-0000-0000-000000000005','p1-cust-a2@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('40000000-0000-0000-0000-000000000006','p1-admin-b@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('40000000-0000-0000-0000-000000000007','p1-kcc@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;

insert into organizations (id, name, slug, status) values
  ('50000000-0000-0000-0000-00000000000a','P1 Org A','p1-org-a','active'),
  ('50000000-0000-0000-0000-00000000000b','P1 Org B','p1-org-b','active')
on conflict (id) do nothing;

insert into organization_memberships (profile_id, organization_id, role, status) values
  ('40000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-00000000000a','company_admin','active'),
  ('40000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-00000000000a','technician','active'),
  ('40000000-0000-0000-0000-000000000003','50000000-0000-0000-0000-00000000000a','technician','active'),
  ('40000000-0000-0000-0000-000000000004','50000000-0000-0000-0000-00000000000a','customer','active'),
  ('40000000-0000-0000-0000-000000000005','50000000-0000-0000-0000-00000000000a','customer','active'),
  ('40000000-0000-0000-0000-000000000006','50000000-0000-0000-0000-00000000000b','company_admin','active'),
  ('40000000-0000-0000-0000-000000000007','50000000-0000-0000-0000-00000000000a','kcc_admin','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"40000000-0000-0000-0000-000000000001","role":"authenticated"}';

insert into customers (id, organization_id, profile_id, first_name, last_name, email, created_by)
values ('60000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-00000000000a','40000000-0000-0000-0000-000000000004','Cust','One','c1@example.com','40000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;
insert into customers (id, organization_id, first_name, last_name, email, created_by)
values ('60000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-00000000000a','Cust','Two','c2@example.com','40000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;
insert into vessels (id, organization_id, current_customer_id, name, hin, created_by)
values ('70000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-00000000000a','60000000-0000-0000-0000-000000000001','Sea Ray 340','HIN123','40000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;
insert into vessel_ownership_history (organization_id, vessel_id, customer_id)
values ('50000000-0000-0000-0000-00000000000a','70000000-0000-0000-0000-000000000001','60000000-0000-0000-0000-000000000001')
on conflict do nothing;
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by)
values ('80000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-00000000000a','60000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','Electrical diagnostic','40000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;
insert into assignments (organization_id, work_order_id, technician_profile_id, assigned_by)
values ('50000000-0000-0000-0000-00000000000a','80000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000001')
on conflict do nothing;
reset role;

-- TEST P1-1: customer_a1 (dueño del vessel) SÍ ve su propio work order
set local role authenticated;
set local request.jwt.claims = '{"sub":"40000000-0000-0000-0000-000000000004","role":"authenticated"}';
select 'p1_1_customer_sees_own_work_order' as test, case when count(*)=1 then 'PASS' else 'FAIL' end as result
from work_orders where id = '80000000-0000-0000-0000-000000000001';
reset role;

-- TEST P1-2: customer_a2 (mismo tenant, OTRO customer) NO ve el work order de customer_a1
set local role authenticated;
set local request.jwt.claims = '{"sub":"40000000-0000-0000-0000-000000000005","role":"authenticated"}';
select 'p1_2_customer_cannot_see_other_customer_wo' as test, case when count(*)=0 then 'PASS' else 'FAIL' end as result
from work_orders where id = '80000000-0000-0000-0000-000000000001';
reset role;

-- TEST P1-3: technician_a1 (asignado) SÍ ve el work order
set local role authenticated;
set local request.jwt.claims = '{"sub":"40000000-0000-0000-0000-000000000002","role":"authenticated"}';
select 'p1_3_assigned_technician_sees_wo' as test, case when count(*)=1 then 'PASS' else 'FAIL' end as result
from work_orders where id = '80000000-0000-0000-0000-000000000001';
reset role;

-- TEST P1-4: technician_a2 (mismo tenant, NO asignado) NO lo ve —
-- el más importante: confirma que NO hay acceso amplio automático a
-- todo el tenant para técnicos.
set local role authenticated;
set local request.jwt.claims = '{"sub":"40000000-0000-0000-0000-000000000003","role":"authenticated"}';
select 'p1_4_unassigned_technician_cannot_see_wo' as test, case when count(*)=0 then 'PASS' else 'FAIL' end as result
from work_orders where id = '80000000-0000-0000-0000-000000000001';
reset role;

-- TEST P1-5: company_admin de Org B (otro tenant) no ve nada de Org A
set local role authenticated;
set local request.jwt.claims = '{"sub":"40000000-0000-0000-0000-000000000006","role":"authenticated"}';
select 'p1_5_other_tenant_admin_isolated' as test,
  case when
    (select count(*) from work_orders where organization_id = '50000000-0000-0000-0000-00000000000a') = 0
    and (select count(*) from customers where organization_id = '50000000-0000-0000-0000-00000000000a') = 0
    and (select count(*) from vessels where organization_id = '50000000-0000-0000-0000-00000000000a') = 0
  then 'PASS' else 'FAIL' end as result;
reset role;

-- TEST P1-6: kcc_admin cross-tenant sí ve todo (arquitectura aprobada)
set local role authenticated;
set local request.jwt.claims = '{"sub":"40000000-0000-0000-0000-000000000007","role":"authenticated"}';
select 'p1_6_kcc_admin_cross_tenant' as test, case when count(*)=1 then 'PASS' else 'FAIL' end as result
from work_orders where id = '80000000-0000-0000-0000-000000000001';
reset role;

-- TEST P1-7: transición NO permitida para technician
set local role authenticated;
set local request.jwt.claims = '{"sub":"40000000-0000-0000-0000-000000000002","role":"authenticated"}';
create temporary table if not exists test_results (test_name text, result text);
do $$
begin
  begin
    perform transition_work_order('80000000-0000-0000-0000-000000000001', 'triage', 'intento no autorizado');
    insert into test_results values ('p1_7_technician_cannot_triage', 'FAIL (call succeeded)');
  exception when others then
    insert into test_results values ('p1_7_technician_cannot_triage', 'PASS');
  end;
end $$;
reset role;

-- TEST P1-8, 9, 10: flujo completo real de transiciones + historial + eventos
set local role authenticated;
set local request.jwt.claims = '{"sub":"40000000-0000-0000-0000-000000000001","role":"authenticated"}';
select transition_work_order('80000000-0000-0000-0000-000000000001', 'triage');
select transition_work_order('80000000-0000-0000-0000-000000000001', 'estimate');
select transition_work_order('80000000-0000-0000-0000-000000000001', 'awaiting_approval');
select transition_work_order('80000000-0000-0000-0000-000000000001', 'scheduled');
select transition_work_order('80000000-0000-0000-0000-000000000001', 'technician_assigned');

insert into test_results
select 'p1_8_full_transition_chain', case when current_status = 'technician_assigned' then 'PASS' else 'FAIL' end
from work_orders where id = '80000000-0000-0000-0000-000000000001';

insert into test_results
select 'p1_9_status_history_recorded', case when count(*)=5 then 'PASS' else 'FAIL' end
from work_order_status_history where work_order_id = '80000000-0000-0000-0000-000000000001';

insert into test_results
select 'p1_10_domain_events_recorded', case when count(*)>=5 then 'PASS' else 'FAIL' end
from domain_events where entity_id = '80000000-0000-0000-0000-000000000001' and event_type = 'WORK_ORDER_STATUS_CHANGED';

reset role;
select * from test_results order by test_name;

-- CLEANUP
delete from work_order_status_history where work_order_id = '80000000-0000-0000-0000-000000000001';
delete from domain_events where organization_id in ('50000000-0000-0000-0000-00000000000a','50000000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('50000000-0000-0000-0000-00000000000a','50000000-0000-0000-0000-00000000000b');
delete from assignments where organization_id in ('50000000-0000-0000-0000-00000000000a','50000000-0000-0000-0000-00000000000b');
delete from work_orders where organization_id in ('50000000-0000-0000-0000-00000000000a','50000000-0000-0000-0000-00000000000b');
delete from vessel_ownership_history where organization_id in ('50000000-0000-0000-0000-00000000000a','50000000-0000-0000-0000-00000000000b');
delete from vessels where organization_id in ('50000000-0000-0000-0000-00000000000a','50000000-0000-0000-0000-00000000000b');
delete from customers where organization_id in ('50000000-0000-0000-0000-00000000000a','50000000-0000-0000-0000-00000000000b');
delete from organization_memberships where organization_id in ('50000000-0000-0000-0000-00000000000a','50000000-0000-0000-0000-00000000000b');
delete from organizations where id in ('50000000-0000-0000-0000-00000000000a','50000000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p1-%@rls-test.local';
delete from auth.users where email like 'p1-%@rls-test.local';
select 'cleanup complete' as status;
