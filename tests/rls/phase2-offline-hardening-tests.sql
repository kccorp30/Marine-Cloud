-- =========================================================
-- tests/rls/phase2-offline-hardening-tests.sql
-- =========================================================
-- Cubre lo que SÍ es verificable server-side de la corrección de
-- offline hardening: autorización, idempotencia real de media/notas/
-- mediciones, y el caso más delicado — idempotencia vs. corrección
-- intencional en checklist_responses (punto 3 del hardening).
--
-- LIMITACIÓN HONESTA: la mecánica de IndexedDB/Blob del lado del
-- cliente (guardar el archivo real offline, drenar la cola al
-- reconectar) se verificó por revisión de código, NO con un test de
-- navegador automatizado — este entorno no tiene un runner de
-- browser real. Ver docs/known-limitations.md.
--
-- Resultados de la última corrida en vivo: TODOS PASS.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('90100000-0000-0000-0000-000000000001','oh-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('90100000-0000-0000-0000-000000000002','oh-tech1@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('90100000-0000-0000-0000-000000000003','oh-tech2@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('90200000-0000-0000-0000-00000000000a','Offline Hardening Org','offline-hardening-org','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('90100000-0000-0000-0000-000000000001','90200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('90100000-0000-0000-0000-000000000002','90200000-0000-0000-0000-00000000000a','technician','active'),
  ('90100000-0000-0000-0000-000000000003','90200000-0000-0000-0000-00000000000a','technician','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"90100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, first_name, last_name, created_by) values ('90300000-0000-0000-0000-000000000001','90200000-0000-0000-0000-00000000000a','Off','Line','90100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('90400000-0000-0000-0000-000000000001','90200000-0000-0000-0000-00000000000a','90300000-0000-0000-0000-000000000001','V','90100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('90500000-0000-0000-0000-000000000001','90200000-0000-0000-0000-00000000000a','90300000-0000-0000-0000-000000000001','90400000-0000-0000-0000-000000000001','WO A','90100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into assignments (organization_id, work_order_id, technician_profile_id, assigned_by) values ('90200000-0000-0000-0000-00000000000a','90500000-0000-0000-0000-000000000001','90100000-0000-0000-0000-000000000002','90100000-0000-0000-0000-000000000001');
reset role;

-- TEST C: técnico no asignado no puede confirmar media para este work order
set local role authenticated;
set local request.jwt.claims = '{"sub":"90100000-0000-0000-0000-000000000003","role":"authenticated"}';
create temporary table test_results (test_name text, result text);
do $$
begin
  begin
    insert into media_assets (organization_id, vessel_id, work_order_id, uploaded_by, category, storage_path, mime_type, client_generated_id)
    values ('90200000-0000-0000-0000-00000000000a','90400000-0000-0000-0000-000000000001','90500000-0000-0000-0000-000000000001','90100000-0000-0000-0000-000000000003','before','fake/path.jpg','image/jpeg', gen_random_uuid());
    insert into test_results values ('test_C_unassigned_technician_media_blocked', 'FAIL (insert succeeded)');
  exception when others then
    insert into test_results values ('test_C_unassigned_technician_media_blocked', 'PASS');
  end;
end $$;
reset role;

-- TEST B + captured_at: reintento del mismo client_generated_id no duplica, y captured_at se preserva
set local role authenticated;
set local request.jwt.claims = '{"sub":"90100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into media_assets (organization_id, vessel_id, work_order_id, uploaded_by, category, storage_path, mime_type, size_bytes, client_generated_id, captured_at)
values ('90200000-0000-0000-0000-00000000000a','90400000-0000-0000-0000-000000000001','90500000-0000-0000-0000-000000000001','90100000-0000-0000-0000-000000000002','before','90200000-0000-0000-0000-00000000000a/90500000-0000-0000-0000-000000000001/before/bbbbbbbb-0000-0000-0000-000000000001.jpg','image/jpeg', 1024, 'bbbbbbbb-0000-0000-0000-000000000001'::uuid, '2026-01-01T10:00:00Z')
on conflict (work_order_id, client_generated_id) do nothing;
insert into media_assets (organization_id, vessel_id, work_order_id, uploaded_by, category, storage_path, mime_type, size_bytes, client_generated_id, captured_at)
values ('90200000-0000-0000-0000-00000000000a','90400000-0000-0000-0000-000000000001','90500000-0000-0000-0000-000000000001','90100000-0000-0000-0000-000000000002','before','90200000-0000-0000-0000-00000000000a/90500000-0000-0000-0000-000000000001/before/bbbbbbbb-0000-0000-0000-000000000001.jpg','image/jpeg', 1024, 'bbbbbbbb-0000-0000-0000-000000000001'::uuid, '2026-01-01T10:00:00Z')
on conflict (work_order_id, client_generated_id) do nothing;
insert into test_results
select 'test_B_photo_retry_no_duplicate', case when count(*)=1 then 'PASS' else 'FAIL' end
from media_assets where client_generated_id = 'bbbbbbbb-0000-0000-0000-000000000001'::uuid;
insert into test_results
select 'test_captured_at_preserved', case when captured_at = '2026-01-01T10:00:00Z'::timestamptz then 'PASS' else 'FAIL' end
from media_assets where client_generated_id = 'bbbbbbbb-0000-0000-0000-000000000001'::uuid;
reset role;

-- TEST D: nota offline idempotente
set local role authenticated;
set local request.jwt.claims = '{"sub":"90100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into work_notes (organization_id, work_order_id, technician_profile_id, body, note_type, client_generated_id)
values ('90200000-0000-0000-0000-00000000000a','90500000-0000-0000-0000-000000000001','90100000-0000-0000-0000-000000000002','offline note','diagnostic','cccccccc-0000-0000-0000-000000000001'::uuid)
on conflict (work_order_id, client_generated_id) do nothing;
insert into work_notes (organization_id, work_order_id, technician_profile_id, body, note_type, client_generated_id)
values ('90200000-0000-0000-0000-00000000000a','90500000-0000-0000-0000-000000000001','90100000-0000-0000-0000-000000000002','offline note RETRY','diagnostic','cccccccc-0000-0000-0000-000000000001'::uuid)
on conflict (work_order_id, client_generated_id) do nothing;
insert into test_results
select 'test_D_offline_note_idempotent', case when count(*)=1 then 'PASS' else 'FAIL' end
from work_notes where client_generated_id = 'cccccccc-0000-0000-0000-000000000001'::uuid;
reset role;

-- TEST E: medición offline idempotente
set local role authenticated;
set local request.jwt.claims = '{"sub":"90100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into measurements (organization_id, vessel_id, work_order_id, technician_profile_id, measurement_type, value, unit, label, client_generated_id)
values ('90200000-0000-0000-0000-00000000000a','90400000-0000-0000-0000-000000000001','90500000-0000-0000-0000-000000000001','90100000-0000-0000-0000-000000000002','reading', 12.4, 'V', 'Bank 1', 'dddddddd-0000-0000-0000-000000000001'::uuid)
on conflict (work_order_id, client_generated_id) do nothing;
insert into measurements (organization_id, vessel_id, work_order_id, technician_profile_id, measurement_type, value, unit, label, client_generated_id)
values ('90200000-0000-0000-0000-00000000000a','90400000-0000-0000-0000-000000000001','90500000-0000-0000-0000-000000000001','90100000-0000-0000-0000-000000000002','reading', 12.4, 'V', 'Bank 1 RETRY', 'dddddddd-0000-0000-0000-000000000001'::uuid)
on conflict (work_order_id, client_generated_id) do nothing;
insert into test_results
select 'test_E_offline_measurement_idempotent', case when count(*)=1 then 'PASS' else 'FAIL' end
from measurements where client_generated_id = 'dddddddd-0000-0000-0000-000000000001'::uuid;
reset role;

-- TEST F: checklist — idempotencia vs corrección intencional (EL caso delicado del hardening)
set local role authenticated;
set local request.jwt.claims = '{"sub":"90100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into checklist_templates (id, organization_id, name) values ('90600000-0000-0000-0000-000000000001','90200000-0000-0000-0000-00000000000a','Checklist') on conflict (id) do nothing;
insert into checklist_template_items (id, template_id, organization_id, label, response_type, display_order) values ('90700000-0000-0000-0000-000000000001','90600000-0000-0000-0000-000000000001','90200000-0000-0000-0000-00000000000a','Terminals clean','pass_fail',1) on conflict (id) do nothing;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"90100000-0000-0000-0000-000000000002","role":"authenticated"}';
-- Respuesta original
insert into checklist_responses (organization_id, work_order_id, template_item_id, technician_profile_id, response_value, client_generated_id, completed_at)
values ('90200000-0000-0000-0000-00000000000a','90500000-0000-0000-0000-000000000001','90700000-0000-0000-0000-000000000001','90100000-0000-0000-0000-000000000002','{"result":"fail"}'::jsonb,'eeeeeeee-0000-0000-0000-000000000001'::uuid, '2026-01-01T10:00:00Z')
on conflict (work_order_id, client_generated_id) do nothing;
-- Reintento de la MISMA respuesta (mismo client_generated_id) — debe ser no-op
insert into checklist_responses (organization_id, work_order_id, template_item_id, technician_profile_id, response_value, client_generated_id, completed_at)
values ('90200000-0000-0000-0000-00000000000a','90500000-0000-0000-0000-000000000001','90700000-0000-0000-0000-000000000001','90100000-0000-0000-0000-000000000002','{"result":"fail"}'::jsonb,'eeeeeeee-0000-0000-0000-000000000001'::uuid, '2026-01-01T10:00:00Z')
on conflict (work_order_id, client_generated_id) do nothing;
-- Corrección intencional POSTERIOR (nuevo client_generated_id, mismo ítem)
insert into checklist_responses (organization_id, work_order_id, template_item_id, technician_profile_id, response_value, client_generated_id, completed_at)
values ('90200000-0000-0000-0000-00000000000a','90500000-0000-0000-0000-000000000001','90700000-0000-0000-0000-000000000001','90100000-0000-0000-0000-000000000002','{"result":"pass"}'::jsonb,'ffffffff-0000-0000-0000-000000000001'::uuid, '2026-01-01T11:00:00Z')
on conflict (work_order_id, client_generated_id) do nothing;

insert into test_results
select 'test_F_checklist_idempotent_and_correction', case when
    (select count(*) from checklist_responses where template_item_id = '90700000-0000-0000-0000-000000000001') = 2
    and (select response_value->>'result' from checklist_responses where template_item_id = '90700000-0000-0000-0000-000000000001' order by completed_at desc limit 1) = 'pass'
  then 'PASS' else 'FAIL' end;
reset role;

select * from test_results order by test_name;

-- CLEANUP
delete from checklist_responses where organization_id = '90200000-0000-0000-0000-00000000000a';
delete from checklist_template_items where organization_id = '90200000-0000-0000-0000-00000000000a';
delete from checklist_templates where organization_id = '90200000-0000-0000-0000-00000000000a';
delete from measurements where organization_id = '90200000-0000-0000-0000-00000000000a';
delete from work_notes where organization_id = '90200000-0000-0000-0000-00000000000a';
delete from media_assets where organization_id = '90200000-0000-0000-0000-00000000000a';
delete from domain_events where organization_id = '90200000-0000-0000-0000-00000000000a';
delete from audit_events where organization_id = '90200000-0000-0000-0000-00000000000a';
delete from assignments where organization_id = '90200000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id = '90200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = '90200000-0000-0000-0000-00000000000a';
delete from customers where organization_id = '90200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id = '90200000-0000-0000-0000-00000000000a';
delete from organizations where id = '90200000-0000-0000-0000-00000000000a';
delete from profiles where email like 'oh-%@rls-test.local';
delete from auth.users where email like 'oh-%@rls-test.local';
select 'cleanup complete' as status;
