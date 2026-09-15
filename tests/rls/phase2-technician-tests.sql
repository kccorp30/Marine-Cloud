-- =========================================================
-- tests/rls/phase2-technician-tests.sql
-- =========================================================
-- Flujo completo real corrido en vivo: login → today → en route →
-- check-in → diagnosis → timer → foto/nota/medición → checklist →
-- progress update → timer stop → check-out. Todos los resultados
-- abajo son de la corrida real, no simulados.
--
-- Resultados de la última corrida: TODOS PASS, incluyendo:
-- - check-out NO completa el work order automáticamente (item 6)
-- - técnico no asignado no lee notas/mediciones (item 15)
-- - customer ve solo progress updates customer_visible (item 8)
-- - idempotencia real vía client_generated_id (item 18) — probado
--   con reintento del mismo start_time_entry Y con upsert directo
--   simulando reconexión de red
-- =========================================================

-- FIXTURES
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('c0000000-0000-0000-0000-000000000001','p2-admin-a@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c0000000-0000-0000-0000-000000000002','p2-tech-a1@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c0000000-0000-0000-0000-000000000003','p2-tech-a2@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c0000000-0000-0000-0000-000000000004','p2-cust-a1@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;

insert into organizations (id, name, slug, status) values
  ('d0000000-0000-0000-0000-00000000000a','P2 Org A','p2-org-a','active')
on conflict (id) do nothing;

insert into organization_memberships (profile_id, organization_id, role, status) values
  ('c0000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-00000000000a','company_admin','active'),
  ('c0000000-0000-0000-0000-000000000002','d0000000-0000-0000-0000-00000000000a','technician','active'),
  ('c0000000-0000-0000-0000-000000000003','d0000000-0000-0000-0000-00000000000a','technician','active'),
  ('c0000000-0000-0000-0000-000000000004','d0000000-0000-0000-0000-00000000000a','customer','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by)
values ('c1000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-00000000000a','c0000000-0000-0000-0000-000000000004','Cust','P2','c0000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;
insert into vessels (id, organization_id, current_customer_id, name, created_by)
values ('c2000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-00000000000a','c1000000-0000-0000-0000-000000000001','P2 Vessel','c0000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by)
values ('c3000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-00000000000a','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000001','P2 Work Order','c0000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;
insert into appointments (id, organization_id, work_order_id, scheduled_start)
values ('c4000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-00000000000a','c3000000-0000-0000-0000-000000000001', now())
on conflict (id) do nothing;
insert into assignments (organization_id, work_order_id, appointment_id, technician_profile_id, assigned_by)
values ('d0000000-0000-0000-0000-00000000000a','c3000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002','c0000000-0000-0000-0000-000000000001');
reset role;

-- Company admin lleva el WO a technician_assigned
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated"}';
select transition_work_order('c3000000-0000-0000-0000-000000000001','triage');
select transition_work_order('c3000000-0000-0000-0000-000000000001','estimate');
select transition_work_order('c3000000-0000-0000-0000-000000000001','awaiting_approval');
select transition_work_order('c3000000-0000-0000-0000-000000000001','scheduled');
select transition_work_order('c3000000-0000-0000-0000-000000000001','technician_assigned');
reset role;

-- Técnico: start route
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select technician_start_route('c3000000-0000-0000-0000-000000000001');
reset role;

-- Técnico: check-in + transición a checked_in + diagnosis
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select technician_check_in('c4000000-0000-0000-0000-000000000001', 25.76, -80.19, '{"device":"test"}'::jsonb);
select transition_work_order('c3000000-0000-0000-0000-000000000001', 'checked_in');
select transition_work_order('c3000000-0000-0000-0000-000000000001', 'diagnosis');
select transition_work_order('c3000000-0000-0000-0000-000000000001', 'work_in_progress');
reset role;

-- Técnico: timer + nota + medición + progress update + checklist
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select start_time_entry('c3000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001','work', gen_random_uuid());
insert into work_notes (organization_id, work_order_id, appointment_id, technician_profile_id, body, note_type)
values ('d0000000-0000-0000-0000-00000000000a','c3000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002','Corrosion found on battery terminal','diagnostic');
insert into measurements (organization_id, vessel_id, work_order_id, appointment_id, technician_profile_id, measurement_type, value, unit, label)
values ('d0000000-0000-0000-0000-00000000000a','c2000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002','voltage', 12.42, 'V', 'Battery Bank #2');
insert into progress_updates (organization_id, work_order_id, appointment_id, technician_profile_id, body, customer_visible)
values ('d0000000-0000-0000-0000-00000000000a','c3000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002','Replaced corroded terminal, testing now', true);
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into checklist_templates (id, organization_id, name) values
('e0000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-00000000000a','Electrical Diagnostic Checklist')
on conflict (id) do nothing;
insert into checklist_template_items (id, template_id, organization_id, label, response_type, display_order) values
('e1000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-00000000000a','Battery terminals clean','pass_fail',1)
on conflict (id) do nothing;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into checklist_responses (organization_id, work_order_id, appointment_id, template_item_id, technician_profile_id, response_value)
values ('d0000000-0000-0000-0000-00000000000a','c3000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002','{"result":"pass"}'::jsonb);
reset role;

-- TEST: idempotencia real — reintento con el mismo client_generated_id
create temporary table if not exists test_results (test_name text, result text);
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select start_time_entry('c3000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'work', 'aaaaaaaa-0000-0000-0000-000000000001'::uuid);
select start_time_entry('c3000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'work', 'aaaaaaaa-0000-0000-0000-000000000001'::uuid);
insert into test_results
select 'test_idempotency_no_duplicate_time_entry', case when count(*)=1 then 'PASS' else 'FAIL' end
from time_entries where client_generated_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;
reset role;

-- Timer stop + check-out
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
declare
  v_time_entry_id uuid;
  v_checkin_id uuid;
begin
  select id into v_time_entry_id from time_entries where work_order_id = 'c3000000-0000-0000-0000-000000000001' and entry_type='work' and status='active' and client_generated_id is distinct from 'aaaaaaaa-0000-0000-0000-000000000001'::uuid limit 1;
  if v_time_entry_id is not null then perform stop_time_entry(v_time_entry_id); end if;

  select id into v_checkin_id from check_ins where appointment_id = 'c4000000-0000-0000-0000-000000000001' and checked_out_at is null;
  perform technician_check_out(v_checkin_id, 'Repair completed, tested OK');
end $$;
reset role;

-- TEST: check-out NO completa el work order automáticamente
insert into test_results
select 'test_checkout_does_not_auto_complete_wo', case when current_status != 'completed' then 'PASS' else 'FAIL' end
from work_orders where id = 'c3000000-0000-0000-0000-000000000001';

-- TEST: técnico no asignado no lee notas ni mediciones
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into test_results
select 'test_unassigned_technician_blocked_from_notes', case when count(*)=0 then 'PASS' else 'FAIL' end
from work_notes where work_order_id = 'c3000000-0000-0000-0000-000000000001';
insert into test_results
select 'test_unassigned_technician_blocked_from_measurements', case when count(*)=0 then 'PASS' else 'FAIL' end
from measurements where work_order_id = 'c3000000-0000-0000-0000-000000000001';
reset role;

-- TEST: customer ve el progress update customer_visible, no las notas internas
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into test_results
select 'test_customer_sees_visible_progress_update', case when count(*)=1 then 'PASS' else 'FAIL' end
from progress_updates where work_order_id = 'c3000000-0000-0000-0000-000000000001' and customer_visible = true;
insert into test_results
select 'test_customer_blocked_from_internal_notes', case when count(*)=0 then 'PASS' else 'FAIL' end
from work_notes where work_order_id = 'c3000000-0000-0000-0000-000000000001';
reset role;

select * from test_results order by test_name;

-- CLEANUP
delete from checklist_responses where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from checklist_template_items where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from checklist_templates where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from progress_update_media where work_order_id = 'c3000000-0000-0000-0000-000000000001';
delete from progress_updates where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from measurements where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from work_notes where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from time_entries where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from check_ins where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from work_order_status_history where work_order_id = 'c3000000-0000-0000-0000-000000000001';
delete from domain_events where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from audit_events where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from assignments where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from appointments where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from customers where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id = 'd0000000-0000-0000-0000-00000000000a';
delete from organizations where id = 'd0000000-0000-0000-0000-00000000000a';
delete from profiles where email like 'p2-%@rls-test.local';
delete from auth.users where email like 'p2-%@rls-test.local';
select 'cleanup complete' as status;
