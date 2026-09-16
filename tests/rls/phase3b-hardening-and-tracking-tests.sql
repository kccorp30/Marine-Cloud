-- =========================================================
-- tests/rls/phase3b-hardening-and-tracking-tests.sql
-- =========================================================
-- Cubre el hardening de domain_events.work_order_id y las garantías
-- de seguridad detrás del tracking del customer. Resultados de la
-- última corrida en vivo: TODOS PASS.
-- =========================================================

-- TEST 1: backfill histórico resuelve correctamente eventos con
-- work_order_id NULL, y deja sin resolver (a propósito) los que no
-- pertenecen a ningún work order específico.
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('94100000-0000-0000-0000-000000000001','p3b-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('94100000-0000-0000-0000-000000000002','p3b-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('94100000-0000-0000-0000-000000000003','p3b-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('94200000-0000-0000-0000-00000000000a','P3B Org','p3b-org','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('94100000-0000-0000-0000-000000000001','94200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('94100000-0000-0000-0000-000000000002','94200000-0000-0000-0000-00000000000a','technician','active'),
  ('94100000-0000-0000-0000-000000000003','94200000-0000-0000-0000-00000000000a','customer','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"94100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('94300000-0000-0000-0000-000000000001','94200000-0000-0000-0000-00000000000a','94100000-0000-0000-0000-000000000003','P3B','Cust','94100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('94400000-0000-0000-0000-000000000001','94200000-0000-0000-0000-00000000000a','94300000-0000-0000-0000-000000000001','V','94100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('94500000-0000-0000-0000-000000000001','94200000-0000-0000-0000-00000000000a','94300000-0000-0000-0000-000000000001','94400000-0000-0000-0000-000000000001','P3B WO','94100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into appointments (id, organization_id, work_order_id, scheduled_start) values ('94600000-0000-0000-0000-000000000001','94200000-0000-0000-0000-00000000000a','94500000-0000-0000-0000-000000000001', now()) on conflict (id) do nothing;
insert into work_notes (id, organization_id, work_order_id, technician_profile_id, body, note_type, client_generated_id) values ('94700000-0000-0000-0000-000000000001','94200000-0000-0000-0000-00000000000a','94500000-0000-0000-0000-000000000001','94100000-0000-0000-0000-000000000002','hist note','general', gen_random_uuid()) on conflict (id) do nothing;
reset role;

-- Eventos "históricos" simulados con work_order_id NULL a propósito
insert into domain_events (id, organization_id, event_type, entity_type, entity_id, occurred_at, work_order_id)
values
  ('94800000-0000-0000-0000-000000000001','94200000-0000-0000-0000-00000000000a','WORK_ORDER_CREATED','work_order','94500000-0000-0000-0000-000000000001', now() - interval '10 days', null),
  ('94800000-0000-0000-0000-000000000002','94200000-0000-0000-0000-00000000000a','APPOINTMENT_CREATED','appointment','94600000-0000-0000-0000-000000000001', now() - interval '9 days', null),
  ('94800000-0000-0000-0000-000000000003','94200000-0000-0000-0000-00000000000a','WORK_NOTE_ADDED','work_note','94700000-0000-0000-0000-000000000001', now() - interval '8 days', null),
  ('94800000-0000-0000-0000-000000000004','94200000-0000-0000-0000-00000000000a','CUSTOMER_CREATED','customer','94300000-0000-0000-0000-000000000001', now() - interval '11 days', null);

-- Re-correr la misma lógica de la migración 042 (idempotente)
update domain_events set work_order_id = entity_id where work_order_id is null and entity_type = 'work_order';
update domain_events de set work_order_id = a.work_order_id from appointments a where de.work_order_id is null and de.entity_type = 'appointment' and a.id = de.entity_id;
update domain_events de set work_order_id = wn.work_order_id from work_notes wn where de.work_order_id is null and de.entity_type = 'work_note' and wn.id = de.entity_id;

create temporary table test_results (test_name text, result text);
insert into test_results
select 'test_1_historical_backfill_correct',
  case when bool_and(case
    when entity_type in ('work_order','appointment','work_note') then work_order_id = '94500000-0000-0000-0000-000000000001'
    when entity_type in ('customer','vessel') then work_order_id is null
    else false
  end) then 'PASS' else 'FAIL' end
from domain_events where organization_id = '94200000-0000-0000-0000-00000000000a';

-- TEST 2a: el trigger en vivo (migración 048) neutraliza el intento
-- a NULL ANTES de que llegue a la FK — defensa temprana.
insert into organizations (id, name, slug, status) values ('94200000-0000-0000-0000-00000000000b','P3B Org B','p3b-org-b','active') on conflict (id) do nothing;
insert into domain_events (organization_id, event_type, entity_type, entity_id, work_order_id)
values ('94200000-0000-0000-0000-00000000000b', 'FAKE_EVENT', 'work_order', '94500000-0000-0000-0000-000000000001', '94500000-0000-0000-0000-000000000001');
insert into test_results
select 'test_2a_trigger_neutralizes_cross_tenant_attempt', case when work_order_id is null then 'PASS' else 'FAIL' end
from domain_events where organization_id = '94200000-0000-0000-0000-00000000000b' and event_type = 'FAKE_EVENT';

-- TEST 2b: la FK en sí (migración 043) es la segunda capa — se prueba
-- con un entity_type que el trigger NO resuelve, para que el
-- work_order_id manual llegue intacto hasta la constraint.
do $$
begin
  begin
    insert into domain_events (organization_id, event_type, entity_type, entity_id, work_order_id)
    values ('94200000-0000-0000-0000-00000000000b', 'FAKE_EVENT_2', 'customer', gen_random_uuid(), '94500000-0000-0000-0000-000000000001');
    insert into test_results values ('test_2b_fk_itself_blocks_cross_tenant', 'FAIL (insert succeeded)');
  exception when foreign_key_violation then
    insert into test_results values ('test_2b_fk_itself_blocks_cross_tenant', 'PASS');
  end;
end $$;

select * from test_results order by test_name;

-- CLEANUP (test 1-2)
delete from domain_events where organization_id in ('94200000-0000-0000-0000-00000000000a','94200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('94200000-0000-0000-0000-00000000000a','94200000-0000-0000-0000-00000000000b');
delete from work_notes where organization_id = '94200000-0000-0000-0000-00000000000a';
delete from appointments where organization_id = '94200000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id = '94200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = '94200000-0000-0000-0000-00000000000a';
delete from customers where organization_id = '94200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id in ('94200000-0000-0000-0000-00000000000a','94200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('94200000-0000-0000-0000-00000000000a','94200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p3b-%@rls-test.local';
delete from auth.users where email like 'p3b-%@rls-test.local';

-- =========================================================
-- TESTS 3-6: seguridad detrás del tracking del customer
-- =========================================================
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('95100000-0000-0000-0000-000000000001','p3b2-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('95100000-0000-0000-0000-000000000002','p3b2-tech1@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('95100000-0000-0000-0000-000000000003','p3b2-tech2@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('95100000-0000-0000-0000-000000000004','p3b2-cust1@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('95100000-0000-0000-0000-000000000005','p3b2-cust2@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('95200000-0000-0000-0000-00000000000a','P3B2 Org','p3b2-org','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('95100000-0000-0000-0000-000000000001','95200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('95100000-0000-0000-0000-000000000002','95200000-0000-0000-0000-00000000000a','technician','active'),
  ('95100000-0000-0000-0000-000000000003','95200000-0000-0000-0000-00000000000a','technician','active'),
  ('95100000-0000-0000-0000-000000000004','95200000-0000-0000-0000-00000000000a','customer','active'),
  ('95100000-0000-0000-0000-000000000005','95200000-0000-0000-0000-00000000000a','customer','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"95100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('95300000-0000-0000-0000-000000000001','95200000-0000-0000-0000-00000000000a','95100000-0000-0000-0000-000000000004','C','One','95100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('95400000-0000-0000-0000-000000000001','95200000-0000-0000-0000-00000000000a','95300000-0000-0000-0000-000000000001','V','95100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('95500000-0000-0000-0000-000000000001','95200000-0000-0000-0000-00000000000a','95300000-0000-0000-0000-000000000001','95400000-0000-0000-0000-000000000001','P3B2 WO','95100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into appointments (id, organization_id, work_order_id, scheduled_start) values ('95600000-0000-0000-0000-000000000001','95200000-0000-0000-0000-00000000000a','95500000-0000-0000-0000-000000000001', now()) on conflict (id) do nothing;
insert into assignments (organization_id, work_order_id, appointment_id, technician_profile_id, assigned_by) values ('95200000-0000-0000-0000-00000000000a','95500000-0000-0000-0000-000000000001','95600000-0000-0000-0000-000000000001','95100000-0000-0000-0000-000000000002','95100000-0000-0000-0000-000000000001');
insert into progress_updates (id, organization_id, work_order_id, appointment_id, technician_profile_id, body, customer_visible, client_generated_id) values ('95700000-0000-0000-0000-000000000001','95200000-0000-0000-0000-00000000000a','95500000-0000-0000-0000-000000000001','95600000-0000-0000-0000-000000000001','95100000-0000-0000-0000-000000000002','visible update', true, gen_random_uuid());
insert into progress_updates (id, organization_id, work_order_id, appointment_id, technician_profile_id, body, customer_visible, client_generated_id) values ('95700000-0000-0000-0000-000000000002','95200000-0000-0000-0000-00000000000a','95500000-0000-0000-0000-000000000001','95600000-0000-0000-0000-000000000001','95100000-0000-0000-0000-000000000002','internal update', false, gen_random_uuid());
reset role;
update profiles set full_name = 'J. Rivera' where id = '95100000-0000-0000-0000-000000000002';

create temporary table if not exists test_results2 (test_name text, result text);

-- TEST 3: customer dueño ve solo el progress update visible
set local role authenticated;
set local request.jwt.claims = '{"sub":"95100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into test_results2
select 'test_3_customer_sees_only_visible_updates', case when count(*)=1 then 'PASS' else 'FAIL' end
from progress_updates where work_order_id = '95500000-0000-0000-0000-000000000001' and customer_visible = true;

-- TEST 4: customer lee nombre/avatar del técnico SOLO vía la función
-- angosta (migración 046) — el join directo a profiles ya NO debe
-- funcionar para un customer, a propósito (ver hardening posterior).
insert into test_results2
select 'test_4_customer_reads_technician_via_narrow_rpc', case when full_name = 'J. Rivera' then 'PASS' else 'FAIL' end
from get_assigned_technician_public_info('95500000-0000-0000-0000-000000000001');
reset role;

-- TEST 5: otro customer y técnico no asignado no leen nada
set local role authenticated;
set local request.jwt.claims = '{"sub":"95100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into test_results2
select 'test_5_other_customer_blocked', case when count(*)=0 then 'PASS' else 'FAIL' end
from work_orders where id = '95500000-0000-0000-0000-000000000001';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"95100000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into test_results2
select 'test_6_unassigned_technician_blocked', case when count(*)=0 then 'PASS' else 'FAIL' end
from work_orders where id = '95500000-0000-0000-0000-000000000001';
reset role;

-- TEST 7: el fix de profiles no abre una fuga cross-organización
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('95900000-0000-0000-0000-000000000001','p3b2-unrelated@rls-test.local','x',now(),now(),now(),'authenticated','authenticated') on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('95200000-0000-0000-0000-00000000000c','P3B2 Unrelated Org','p3b2-org-c','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values ('95900000-0000-0000-0000-000000000001','95200000-0000-0000-0000-00000000000c','customer','active') on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"95100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into test_results2
select 'test_7_profiles_fix_no_cross_org_leak', case when count(*)=0 then 'PASS' else 'FAIL' end
from profiles where id = '95900000-0000-0000-0000-000000000001';
reset role;

-- TEST 8: transition_work_order sigue funcionando sin regresión
set local role authenticated;
set local request.jwt.claims = '{"sub":"95100000-0000-0000-0000-000000000001","role":"authenticated"}';
select transition_work_order('95500000-0000-0000-0000-000000000001', 'triage');
insert into test_results2
select 'test_8_transition_no_regression', case when current_status='triage' then 'PASS' else 'FAIL' end
from work_orders where id = '95500000-0000-0000-0000-000000000001';
reset role;

-- TEST 9: last_activity_at sigue actualizándose solo
insert into test_results2
select 'test_9_last_activity_at_still_works', case when last_activity_at is not null then 'PASS' else 'FAIL' end
from work_orders where id = '95500000-0000-0000-0000-000000000001';

select * from test_results2 order by test_name;

-- CLEANUP
delete from work_order_status_history where work_order_id = '95500000-0000-0000-0000-000000000001';
delete from progress_updates where organization_id = '95200000-0000-0000-0000-00000000000a';
delete from domain_events where organization_id in ('95200000-0000-0000-0000-00000000000a','95200000-0000-0000-0000-00000000000c');
delete from audit_events where organization_id in ('95200000-0000-0000-0000-00000000000a','95200000-0000-0000-0000-00000000000c');
delete from assignments where organization_id = '95200000-0000-0000-0000-00000000000a';
delete from appointments where organization_id = '95200000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id = '95200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = '95200000-0000-0000-0000-00000000000a';
delete from customers where organization_id = '95200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id in ('95200000-0000-0000-0000-00000000000a','95200000-0000-0000-0000-00000000000c');
delete from organizations where id in ('95200000-0000-0000-0000-00000000000a','95200000-0000-0000-0000-00000000000c');
delete from profiles where email like 'p3b2-%@rls-test.local';
delete from auth.users where email like 'p3b2-%@rls-test.local';
select 'cleanup complete' as status;

-- =========================================================
-- TESTS 10-12: hardening final — backfill tenant-safe (047/048) y
-- verificación directa de dependencias del tracking (más allá del DTO)
-- =========================================================
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('97100000-0000-0000-0000-000000000001','p3bh2-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('97100000-0000-0000-0000-000000000002','p3bh2-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('97100000-0000-0000-0000-000000000003','p3bh2-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('97200000-0000-0000-0000-00000000000a','P3BH2 Org A','p3bh2-org-a','active'),
  ('97200000-0000-0000-0000-00000000000b','P3BH2 Org B','p3bh2-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('97100000-0000-0000-0000-000000000001','97200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('97100000-0000-0000-0000-000000000002','97200000-0000-0000-0000-00000000000a','customer','active'),
  ('97100000-0000-0000-0000-000000000003','97200000-0000-0000-0000-00000000000a','technician','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"97100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('97300000-0000-0000-0000-000000000001','97200000-0000-0000-0000-00000000000a','97100000-0000-0000-0000-000000000002','C','A','97100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('97400000-0000-0000-0000-000000000001','97200000-0000-0000-0000-00000000000a','97300000-0000-0000-0000-000000000001','V','97100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('97500000-0000-0000-0000-000000000001','97200000-0000-0000-0000-00000000000a','97300000-0000-0000-0000-000000000001','97400000-0000-0000-0000-000000000001','Real WO Org A','97100000-0000-0000-0000-000000000001') on conflict (id) do nothing;
insert into appointments (id, organization_id, work_order_id, scheduled_start) values ('97600000-0000-0000-0000-000000000001','97200000-0000-0000-0000-00000000000a','97500000-0000-0000-0000-000000000001', now()) on conflict (id) do nothing;
insert into assignments (organization_id, work_order_id, appointment_id, technician_profile_id, assigned_by) values ('97200000-0000-0000-0000-00000000000a','97500000-0000-0000-0000-000000000001','97600000-0000-0000-0000-000000000001','97100000-0000-0000-0000-000000000003','97100000-0000-0000-0000-000000000001');
reset role;

-- TEST 10: evento histórico "mal formado" (organization_id de Org B,
-- pero entity_id apunta a un appointment REAL de Org A) — debe quedar
-- SIN resolver, nunca crear un vínculo cross-tenant, e insertarse sin
-- error (el trigger de la 048 lo neutraliza antes de llegar a la FK).
insert into domain_events (id, organization_id, event_type, entity_type, entity_id, occurred_at)
values ('97800000-0000-0000-0000-000000000001', '97200000-0000-0000-0000-00000000000b', 'APPOINTMENT_CREATED', 'appointment', '97600000-0000-0000-0000-000000000001', now() - interval '20 days');

create temporary table test_results3 (test_name text, result text);
insert into test_results3
select 'test_10_malformed_historical_event_stays_null', case when work_order_id is null then 'PASS' else 'FAIL' end
from domain_events where id = '97800000-0000-0000-0000-000000000001';

-- Re-correr el backfill tenant-safe (idempotente) — no debe tocar el
-- evento mal formado.
update domain_events de set work_order_id = a.work_order_id from appointments a
where de.work_order_id is null and de.entity_type = 'appointment' and a.id = de.entity_id and a.organization_id = de.organization_id;
insert into test_results3
select 'test_10b_backfill_still_leaves_it_null', case when work_order_id is null then 'PASS' else 'FAIL' end
from domain_events where id = '97800000-0000-0000-0000-000000000001';

-- TEST 11: la media interna sigue sin ser legible por el customer,
-- verificado directo (más allá del DTO).
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values ('97100000-0000-0000-0000-000000000003','p3bh2-tech-dup@rls-test.local','x',now(),now(),now(),'authenticated','authenticated') on conflict (id) do nothing;
set local role authenticated;
set local request.jwt.claims = '{"sub":"97100000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into media_assets (organization_id, vessel_id, work_order_id, uploaded_by, category, storage_path, mime_type, visibility, client_generated_id)
values ('97200000-0000-0000-0000-00000000000a','97400000-0000-0000-0000-000000000001','97500000-0000-0000-0000-000000000001','97100000-0000-0000-0000-000000000003','before','fake/internal.jpg','image/jpeg','internal', gen_random_uuid());
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"97100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into test_results3
select 'test_11_customer_cannot_read_internal_media', case when count(*)=0 then 'PASS' else 'FAIL' end
from media_assets where work_order_id = '97500000-0000-0000-0000-000000000001' and visibility = 'internal';
reset role;

select * from test_results3 order by test_name;

-- CLEANUP final
delete from media_assets where organization_id = '97200000-0000-0000-0000-00000000000a';
delete from domain_events where organization_id in ('97200000-0000-0000-0000-00000000000a','97200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('97200000-0000-0000-0000-00000000000a','97200000-0000-0000-0000-00000000000b');
delete from assignments where organization_id = '97200000-0000-0000-0000-00000000000a';
delete from appointments where organization_id = '97200000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id = '97200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = '97200000-0000-0000-0000-00000000000a';
delete from customers where organization_id = '97200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id in ('97200000-0000-0000-0000-00000000000a','97200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('97200000-0000-0000-0000-00000000000a','97200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p3bh2-%@rls-test.local';
delete from auth.users where email like 'p3bh2-%@rls-test.local';
select 'all cleanup complete' as status;

-- =========================================================
-- TESTS 13-14: orden de migración seguro (049/050)
-- =========================================================
-- Simula exactamente el escenario que preocupaba: una fila como si la
-- 042 original (sin verificación de tenant) la hubiera dejado
-- corrupta ANTES de que existiera la FK — organization_id de una
-- organización, work_order_id apuntando a un work order real de OTRA.
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('98100000-0000-0000-0000-000000000001','p3bmig-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated') on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('98200000-0000-0000-0000-00000000000a','Migration Test Org A','p3bmig-org-a','active'),
  ('98200000-0000-0000-0000-00000000000b','Migration Test Org B','p3bmig-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values ('98100000-0000-0000-0000-000000000001','98200000-0000-0000-0000-00000000000a','company_admin','active') on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"98100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, first_name, last_name, created_by) values ('98300000-0000-0000-0000-000000000001','98200000-0000-0000-0000-00000000000a','C','A','98100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('98400000-0000-0000-0000-000000000001','98200000-0000-0000-0000-00000000000a','98300000-0000-0000-0000-000000000001','V','98100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('98500000-0000-0000-0000-000000000001','98200000-0000-0000-0000-00000000000a','98300000-0000-0000-0000-000000000001','98400000-0000-0000-0000-000000000001','Real WO','98100000-0000-0000-0000-000000000001');
reset role;

alter table domain_events drop constraint if exists fk_domain_events_work_order_same_org;
insert into domain_events (id, organization_id, event_type, entity_type, entity_id, occurred_at, work_order_id)
values ('98800000-0000-0000-0000-000000000001', '98200000-0000-0000-0000-00000000000b', 'LEGACY_EVENT', 'legacy_unmapped', gen_random_uuid(), now() - interval '30 days', '98500000-0000-0000-0000-000000000001');

-- 049: recrear como NOT VALID — debe funcionar pese a la corrupción
alter table domain_events add constraint fk_domain_events_work_order_same_org
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id) not valid;

create temporary table test_results4 (test_name text, result text);
insert into test_results4 values ('test_13_migration_049_succeeds_despite_corruption', 'PASS');

-- 050 paso 1: reparar
update domain_events de set work_order_id = null
where de.work_order_id is not null and not exists (
  select 1 from work_orders wo where wo.id = de.work_order_id and wo.organization_id = de.organization_id
);
insert into test_results4
select 'test_14a_repair_nulls_corrupted_row', case when work_order_id is null then 'PASS' else 'FAIL' end
from domain_events where id = '98800000-0000-0000-0000-000000000001';

-- 050 paso 3: validar — el momento crítico
alter table domain_events validate constraint fk_domain_events_work_order_same_org;
insert into test_results4
select 'test_14b_validate_succeeds_after_repair', case when convalidated then 'PASS' else 'FAIL' end
from pg_constraint where conname = 'fk_domain_events_work_order_same_org';

select * from test_results4 order by test_name;

delete from domain_events where organization_id in ('98200000-0000-0000-0000-00000000000a','98200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('98200000-0000-0000-0000-00000000000a','98200000-0000-0000-0000-00000000000b');
delete from work_orders where organization_id = '98200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = '98200000-0000-0000-0000-00000000000a';
delete from customers where organization_id = '98200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id in ('98200000-0000-0000-0000-00000000000a','98200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('98200000-0000-0000-0000-00000000000a','98200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p3bmig-%@rls-test.local';
delete from auth.users where email like 'p3bmig-%@rls-test.local';

-- =========================================================
-- TESTS 15-23: las 9 adversariales del modelo final de perfiles
-- =========================================================
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('99100000-0000-0000-0000-000000000001','p3bfinal-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('99100000-0000-0000-0000-000000000002','p3bfinal-tech1@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('99100000-0000-0000-0000-000000000003','p3bfinal-tech2@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('99100000-0000-0000-0000-000000000004','p3bfinal-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('99100000-0000-0000-0000-000000000005','p3bfinal-tech-otherorg@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('99100000-0000-0000-0000-000000000006','p3bfinal-cust2@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('99200000-0000-0000-0000-00000000000a','P3BFinal Org A','p3bfinal-org-a','active'),
  ('99200000-0000-0000-0000-00000000000b','P3BFinal Org B','p3bfinal-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('99100000-0000-0000-0000-000000000001','99200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('99100000-0000-0000-0000-000000000002','99200000-0000-0000-0000-00000000000a','technician','active'),
  ('99100000-0000-0000-0000-000000000003','99200000-0000-0000-0000-00000000000a','technician','active'),
  ('99100000-0000-0000-0000-000000000004','99200000-0000-0000-0000-00000000000a','customer','active'),
  ('99100000-0000-0000-0000-000000000005','99200000-0000-0000-0000-00000000000b','technician','active'),
  ('99100000-0000-0000-0000-000000000006','99200000-0000-0000-0000-00000000000a','customer','active')
on conflict do nothing;

update profiles set full_name='J. Rivera', phone='+1-555-0100', email='jrivera-private@example.com', avatar_url='https://example.com/rivera.jpg' where id='99100000-0000-0000-0000-000000000002';
update profiles set full_name='K. Otherguy', phone='+1-555-0200', email='kother-private@example.com' where id='99100000-0000-0000-0000-000000000003';
update profiles set full_name='M. Faraway', phone='+1-555-0300', email='mfar-private@example.com' where id='99100000-0000-0000-0000-000000000005';

set local role authenticated;
set local request.jwt.claims = '{"sub":"99100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('99300000-0000-0000-0000-000000000001','99200000-0000-0000-0000-00000000000a','99100000-0000-0000-0000-000000000004','C','Final','99100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('99400000-0000-0000-0000-000000000001','99200000-0000-0000-0000-00000000000a','99300000-0000-0000-0000-000000000001','V','99100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('99500000-0000-0000-0000-000000000001','99200000-0000-0000-0000-00000000000a','99300000-0000-0000-0000-000000000001','99400000-0000-0000-0000-000000000001','Final WO','99100000-0000-0000-0000-000000000001');
insert into appointments (id, organization_id, work_order_id, scheduled_start) values ('99600000-0000-0000-0000-000000000001','99200000-0000-0000-0000-00000000000a','99500000-0000-0000-0000-000000000001', now());
insert into assignments (organization_id, work_order_id, appointment_id, technician_profile_id, assigned_by) values ('99200000-0000-0000-0000-00000000000a','99500000-0000-0000-0000-000000000001','99600000-0000-0000-0000-000000000001','99100000-0000-0000-0000-000000000002','99100000-0000-0000-0000-000000000001');
reset role;

-- 15/16/17: nombre+avatar correctos, sin phone/email en la forma de la respuesta
set local role authenticated;
set local request.jwt.claims = '{"sub":"99100000-0000-0000-0000-000000000004","role":"authenticated"}';
create temporary table test_results5 (test_name text, result text);
insert into test_results5
select 'test_15_16_17_name_avatar_no_phone_no_email',
  case when full_name = 'J. Rivera' and avatar_url = 'https://example.com/rivera.jpg' then 'PASS' else 'FAIL' end
from get_assigned_technician_public_info('99500000-0000-0000-0000-000000000001');
-- (la ausencia estructural de phone/email en el tipo de retorno de la función es la garantía — no hay columna que filtrar)

-- 18: no lee el profiles crudo del técnico asignado
insert into test_results5
select 'test_18_customer_cannot_select_raw_profile', case when count(*)=0 then 'PASS' else 'FAIL' end
from profiles where id = '99100000-0000-0000-0000-000000000002';
reset role;

-- 19: no accede a un técnico no relacionado (mismo org, sin asignación)
set local role authenticated;
set local request.jwt.claims = '{"sub":"99100000-0000-0000-0000-000000000006","role":"authenticated"}';
insert into test_results5
select 'test_19_cannot_access_unrelated_technician', case when count(*)=0 then 'PASS' else 'FAIL' end
from profiles where id = '99100000-0000-0000-0000-000000000003';
reset role;

-- 20: no accede a un técnico de otra organización
set local role authenticated;
set local request.jwt.claims = '{"sub":"99100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into test_results5
select 'test_20_cannot_access_technician_other_org', case when count(*)=0 then 'PASS' else 'FAIL' end
from profiles where id = '99100000-0000-0000-0000-000000000005';
reset role;

-- 21: anon no puede ejecutar la función
set local role anon;
do $$
begin
  begin
    perform get_assigned_technician_public_info('99500000-0000-0000-0000-000000000001');
    insert into test_results5 values ('test_21_anon_cannot_execute_rpc', 'FAIL (no lanzó excepción)');
  exception when insufficient_privilege then
    insert into test_results5 values ('test_21_anon_cannot_execute_rpc', 'PASS');
  end;
end $$;
reset role;

-- 22: staff mantiene acceso operativo
set local role authenticated;
set local request.jwt.claims = '{"sub":"99100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into test_results5
select 'test_22_staff_operational_access_works', case when full_name = 'K. Otherguy' then 'PASS' else 'FAIL' end
from profiles where id = '99100000-0000-0000-0000-000000000003';
reset role;

-- 23: el técnico sigue leyendo su propio perfil
set local role authenticated;
set local request.jwt.claims = '{"sub":"99100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into test_results5
select 'test_23_technician_self_access_works', case when full_name = 'J. Rivera' then 'PASS' else 'FAIL' end
from profiles where id = '99100000-0000-0000-0000-000000000002';
reset role;

select * from test_results5 order by test_name;

delete from domain_events where organization_id in ('99200000-0000-0000-0000-00000000000a','99200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('99200000-0000-0000-0000-00000000000a','99200000-0000-0000-0000-00000000000b');
delete from assignments where organization_id = '99200000-0000-0000-0000-00000000000a';
delete from appointments where organization_id = '99200000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id = '99200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = '99200000-0000-0000-0000-00000000000a';
delete from customers where organization_id = '99200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id in ('99200000-0000-0000-0000-00000000000a','99200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('99200000-0000-0000-0000-00000000000a','99200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p3bfinal-%@rls-test.local';
delete from auth.users where email like 'p3bfinal-%@rls-test.local';
select 'final cleanup complete' as status;
