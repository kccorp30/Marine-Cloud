-- =========================================================
-- tests/rls/phase3-timeline-tests.sql
-- =========================================================
-- Visibilidad por rol del timeline (domain_events). Corregido en esta
-- fase: la política de Phase 0 le daba a CUALQUIER miembro de la
-- org acceso a TODOS los eventos, sin filtrar por work order ni
-- visibilidad — nunca se explotó porque nada leía domain_events desde
-- la UI hasta ahora.
--
-- Resultados de la última corrida en vivo: 6/6 PASS.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('92100000-0000-0000-0000-000000000001','t3-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('92100000-0000-0000-0000-000000000002','t3-tech1@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('92100000-0000-0000-0000-000000000003','t3-tech2@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('92100000-0000-0000-0000-000000000004','t3-cust1@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('92100000-0000-0000-0000-000000000005','t3-cust2@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('92200000-0000-0000-0000-00000000000a','T3 Org','t3-org','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('92100000-0000-0000-0000-000000000001','92200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('92100000-0000-0000-0000-000000000002','92200000-0000-0000-0000-00000000000a','technician','active'),
  ('92100000-0000-0000-0000-000000000003','92200000-0000-0000-0000-00000000000a','technician','active'),
  ('92100000-0000-0000-0000-000000000004','92200000-0000-0000-0000-00000000000a','customer','active'),
  ('92100000-0000-0000-0000-000000000005','92200000-0000-0000-0000-00000000000a','customer','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"92100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('92300000-0000-0000-0000-000000000001','92200000-0000-0000-0000-00000000000a','92100000-0000-0000-0000-000000000004','T3','Cust1','92100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('92400000-0000-0000-0000-000000000001','92200000-0000-0000-0000-00000000000a','92300000-0000-0000-0000-000000000001','V','92100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('92500000-0000-0000-0000-000000000001','92200000-0000-0000-0000-00000000000a','92300000-0000-0000-0000-000000000001','92400000-0000-0000-0000-000000000001','T3 WO','92100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into assignments (organization_id, work_order_id, technician_profile_id, assigned_by) values ('92200000-0000-0000-0000-00000000000a','92500000-0000-0000-0000-000000000001','92100000-0000-0000-0000-000000000002','92100000-0000-0000-0000-000000000001');
select transition_work_order('92500000-0000-0000-0000-000000000001','triage');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"92100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into work_notes (organization_id, work_order_id, technician_profile_id, body, note_type, visibility, client_generated_id)
values ('92200000-0000-0000-0000-00000000000a','92500000-0000-0000-0000-000000000001','92100000-0000-0000-0000-000000000002','internal note','diagnostic','internal', gen_random_uuid());
insert into progress_updates (organization_id, work_order_id, technician_profile_id, body, customer_visible, client_generated_id)
values ('92200000-0000-0000-0000-00000000000a','92500000-0000-0000-0000-000000000001','92100000-0000-0000-0000-000000000002','visible update', true, gen_random_uuid());
select start_time_entry('92500000-0000-0000-0000-000000000001', null, 'work', gen_random_uuid());
reset role;

create temporary table test_results (test_name text, result text);

-- TEST 1: customer dueño ve SOLO eventos customer-visible (4 de los 7 reales)
set local role authenticated;
set local request.jwt.claims = '{"sub":"92100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into test_results
select 'test_1_customer_sees_only_visible_events',
  case when count(*) = 4 and bool_and(event_type not in ('WORK_NOTE_ADDED','TIME_ENTRY_STARTED','TECHNICIAN_WORK_STARTED')) then 'PASS' else 'FAIL' end
from domain_events where work_order_id = '92500000-0000-0000-0000-000000000001';
reset role;

-- TEST 2: técnico asignado ve TODO (7 eventos, incluyendo internos)
set local role authenticated;
set local request.jwt.claims = '{"sub":"92100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into test_results
select 'test_2_assigned_technician_sees_everything', case when count(*) = 7 then 'PASS' else 'FAIL' end
from domain_events where work_order_id = '92500000-0000-0000-0000-000000000001';
reset role;

-- TEST 3: técnico NO asignado no ve nada
set local role authenticated;
set local request.jwt.claims = '{"sub":"92100000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into test_results
select 'test_3_unassigned_technician_sees_nothing', case when count(*) = 0 then 'PASS' else 'FAIL' end
from domain_events where work_order_id = '92500000-0000-0000-0000-000000000001';
reset role;

-- TEST 4: otro customer no ve nada
set local role authenticated;
set local request.jwt.claims = '{"sub":"92100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into test_results
select 'test_4_other_customer_sees_nothing', case when count(*) = 0 then 'PASS' else 'FAIL' end
from domain_events where work_order_id = '92500000-0000-0000-0000-000000000001';
reset role;

-- TEST 5: staff ve todo
set local role authenticated;
set local request.jwt.claims = '{"sub":"92100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into test_results
select 'test_5_staff_sees_everything', case when count(*) = 7 then 'PASS' else 'FAIL' end
from domain_events where work_order_id = '92500000-0000-0000-0000-000000000001';
reset role;

-- TEST 6: last_activity_at se actualiza solo, vía trigger
insert into test_results
select 'test_6_last_activity_updates_automatically', case when last_activity_at is not null then 'PASS' else 'FAIL' end
from work_orders where id = '92500000-0000-0000-0000-000000000001';

select * from test_results order by test_name;

-- CLEANUP
delete from time_entries where organization_id = '92200000-0000-0000-0000-00000000000a';
delete from work_notes where organization_id = '92200000-0000-0000-0000-00000000000a';
delete from progress_updates where organization_id = '92200000-0000-0000-0000-00000000000a';
delete from work_order_status_history where work_order_id = '92500000-0000-0000-0000-000000000001';
delete from domain_events where organization_id = '92200000-0000-0000-0000-00000000000a';
delete from audit_events where organization_id = '92200000-0000-0000-0000-00000000000a';
delete from assignments where organization_id = '92200000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id = '92200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = '92200000-0000-0000-0000-00000000000a';
delete from customers where organization_id = '92200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id = '92200000-0000-0000-0000-00000000000a';
delete from organizations where id = '92200000-0000-0000-0000-00000000000a';
delete from profiles where email like 't3-%@rls-test.local';
delete from auth.users where email like 't3-%@rls-test.local';
select 'cleanup complete' as status;
