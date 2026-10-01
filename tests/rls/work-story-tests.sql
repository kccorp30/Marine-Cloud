-- =========================================================
-- WORK STORY — feed operativo único, filtrado por rol vía RLS
-- =========================================================
-- Verifica la invariante central del brief: UNA sola fuente
-- (domain_events + role_scoped_read_domain_events) alimenta el relato
-- del técnico, de la compañía y del customer, y cada uno recibe
-- exactamente lo que le corresponde SIN que la aplicación filtre nada.
--
-- Recorre la misión real completa con los RPC de producción:
--   asignación → START ROUTE → tracking + primer GPS → llegada →
--   3 fotos BEFORE (1 visible / 2 internas) → inicio de trabajo →
--   progress update visible + foto visible → nota interna →
--   FINISH TODAY'S VISIT (continuar mañana)
--
-- Ejecutar con service_role. Limpia todo al final.
-- =========================================================

begin;

-- ---------- FIXTURE ----------
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('c0de0000-0000-4000-8000-0000000000a1','ws-owner@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c0de0000-0000-4000-8000-0000000000b1','ws-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c0de0000-0000-4000-8000-0000000000c1','ws-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
  on conflict (id) do nothing;

insert into organizations (id, name, slug, status) values
  ('c0de0000-0000-4000-8000-000000000001','WS Story Co','ws-story-co','active') on conflict (id) do nothing;

insert into profiles (id, email, full_name) values
  ('c0de0000-0000-4000-8000-0000000000a1','ws-owner@rls-test.local','WS Owner'),
  ('c0de0000-0000-4000-8000-0000000000b1','ws-tech@rls-test.local','Wanda Tech'),
  ('c0de0000-0000-4000-8000-0000000000c1','ws-cust@rls-test.local','Carl Customer')
  on conflict (id) do update set full_name = excluded.full_name;

insert into organization_memberships (organization_id, profile_id, role, status) values
  ('c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-0000000000a1','company_owner','active'),
  ('c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-0000000000b1','technician','active'),
  ('c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-0000000000c1','customer','active')
  on conflict do nothing;

-- fail-closed: sin plan_module_entitlements el tracking se niega
insert into subscription_plans (id, code, name, status, currency, monthly_price, is_public)
  values ('c0de0000-0000-4000-8000-0000000000d1','WS_TEST','WS Test Plan','active','USD',100,false)
  on conflict (id) do nothing;
insert into plan_module_entitlements (plan_id, module_key, enabled) values
  ('c0de0000-0000-4000-8000-0000000000d1','tracking',true),
  ('c0de0000-0000-4000-8000-0000000000d1','work_orders',true)
  on conflict do nothing;
insert into organization_subscriptions (organization_id, plan_id, status, billing_cycle, subscription_started_at, current_period_started_at, current_period_ends_at)
  values ('c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-0000000000d1','active','monthly', now(), now(), now() + interval '60 days')
  on conflict do nothing;

-- Datos operativos creados por el OWNER real (log_domain_event exige auth.uid())
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0de0000-0000-4000-8000-0000000000a1","role":"authenticated"}';

insert into customers (id, organization_id, profile_id, first_name, last_name, created_by)
  values ('c0de0000-0000-4000-8000-0000000000e1','c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-0000000000c1','Carl','Customer','c0de0000-0000-4000-8000-0000000000a1');
insert into vessels (id, organization_id, current_customer_id, name, marina, service_street_address, created_by)
  values ('c0de0000-0000-4000-8000-0000000000f1','c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-0000000000e1','Sea Story','Marina Uno','12 Dock Rd','c0de0000-0000-4000-8000-0000000000a1');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by)
  values ('c0de0000-0000-4000-8000-000000000f11','c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-0000000000e1','c0de0000-0000-4000-8000-0000000000f1','Engine service','c0de0000-0000-4000-8000-0000000000a1');

-- A. La compañía asigna técnico recorriendo la cadena real
select transition_work_order('c0de0000-0000-4000-8000-000000000f11','triage','triage');
select transition_work_order('c0de0000-0000-4000-8000-000000000f11','estimate','estimate');
select transition_work_order('c0de0000-0000-4000-8000-000000000f11','awaiting_approval','awaiting');
select transition_work_order('c0de0000-0000-4000-8000-000000000f11','scheduled','scheduled');
insert into assignments (id, organization_id, work_order_id, technician_profile_id, assigned_by, status)
  values ('c0de0000-0000-4000-8000-00000000a111','c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000f11','c0de0000-0000-4000-8000-0000000000b1','c0de0000-0000-4000-8000-0000000000a1','active');
select transition_work_order('c0de0000-0000-4000-8000-000000000f11','technician_assigned','assigned');
insert into appointments (id, organization_id, work_order_id, scheduled_start, status, purpose)
  values ('c0de0000-0000-4000-8000-00000000ab11','c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000f11', now() + interval '1 hour','scheduled','service');
reset role;

-- D/E/I. START ROUTE + tracking + primer GPS + llegada, como el TÉCNICO
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0de0000-0000-4000-8000-0000000000b1","role":"authenticated"}';
select technician_start_route('c0de0000-0000-4000-8000-000000000f11');
do $$
declare v_session uuid;
begin
  select id into v_session from start_technician_tracking('c0de0000-0000-4000-8000-000000000f11');
  perform submit_technician_location(v_session, 25.7617, -80.1918, 12.5, null, null, now());
end $$;
select id from technician_check_in('c0de0000-0000-4000-8000-00000000ab11', 25.7617, -80.1918, null);

-- K. 3 fotos BEFORE: 1 visible al customer, 2 internas
insert into media_assets (id, organization_id, work_order_id, vessel_id, uploaded_by, category, storage_path, mime_type, visibility, captured_at, caption, client_generated_id) values
 ('c0de0000-0000-4000-8000-00000000a111','c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000f11','c0de0000-0000-4000-8000-0000000000f1','c0de0000-0000-4000-8000-0000000000b1','before','ws/before-1.jpg','image/jpeg','customer_visible',now(),'Hull before work', gen_random_uuid()),
 ('c0de0000-0000-4000-8000-00000000a222','c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000f11','c0de0000-0000-4000-8000-0000000000f1','c0de0000-0000-4000-8000-0000000000b1','before','ws/before-2.jpg','image/jpeg','internal',now(),'Internal only', gen_random_uuid()),
 ('c0de0000-0000-4000-8000-00000000a333','c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000f11','c0de0000-0000-4000-8000-0000000000f1','c0de0000-0000-4000-8000-0000000000b1','before','ws/before-3.jpg','image/jpeg','internal',now(),'Internal only 2', gen_random_uuid());

-- O/Q. Inicio de trabajo + actualización y foto visibles + nota interna
select transition_work_order('c0de0000-0000-4000-8000-000000000f11','diagnosis','diagnosing');
select transition_work_order('c0de0000-0000-4000-8000-000000000f11','work_in_progress','starting work');
select start_time_entry('c0de0000-0000-4000-8000-000000000f11', null, 'work', gen_random_uuid());
insert into progress_updates (id, organization_id, work_order_id, technician_profile_id, body, customer_visible, client_generated_id)
  values ('c0de0000-0000-4000-8000-00000000b111','c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000f11','c0de0000-0000-4000-8000-0000000000b1','Replaced the impeller, flushing the cooling system now.', true, gen_random_uuid());
insert into media_assets (id, organization_id, work_order_id, vessel_id, uploaded_by, category, storage_path, mime_type, visibility, captured_at, caption, client_generated_id)
  values ('c0de0000-0000-4000-8000-00000000a444','c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000f11','c0de0000-0000-4000-8000-0000000000f1','c0de0000-0000-4000-8000-0000000000b1','progress','ws/progress-1.jpg','image/jpeg','customer_visible',now(),'New impeller installed', gen_random_uuid());
insert into progress_update_media (progress_update_id, media_id, work_order_id)
  values ('c0de0000-0000-4000-8000-00000000b111','c0de0000-0000-4000-8000-00000000a444','c0de0000-0000-4000-8000-000000000f11');
insert into work_notes (organization_id, work_order_id, technician_profile_id, body, note_type, visibility, client_generated_id)
  values ('c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000f11','c0de0000-0000-4000-8000-0000000000b1','Corrosion worse than quoted','diagnostic','internal', gen_random_uuid());

-- S. FINISH TODAY'S VISIT → continuar mañana
select finish_todays_visit('c0de0000-0000-4000-8000-000000000f11','continue_tomorrow','Impeller replaced. Cooling flush pending.', now() + interval '1 day');
reset role;

-- ---------- CAPTURA DEL FEED POR ROL ----------
-- Exactamente la query que corre getWorkStory(): sin filtro por rol.
create temporary table ws_feed (viewer text, event_type text, entity_id uuid);
grant all on ws_feed to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0de0000-0000-4000-8000-0000000000b1","role":"authenticated"}';
insert into ws_feed select 'technician', event_type, entity_id from domain_events where work_order_id='c0de0000-0000-4000-8000-000000000f11';
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0de0000-0000-4000-8000-0000000000a1","role":"authenticated"}';
insert into ws_feed select 'company', event_type, entity_id from domain_events where work_order_id='c0de0000-0000-4000-8000-000000000f11';
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0de0000-0000-4000-8000-0000000000c1","role":"authenticated"}';
insert into ws_feed select 'customer', event_type, entity_id from domain_events where work_order_id='c0de0000-0000-4000-8000-000000000f11';
reset role;

-- ---------- ASSERTIONS ----------
create temporary table ws_results (test_name text, result text);

insert into ws_results
select 'work_story_single_feed_not_empty_for_every_role',
  case when (select count(distinct viewer) from ws_feed)=3 then 'PASS' else 'FAIL' end;

insert into ws_results
select 'company_sees_all_three_before_photos',
  case when (select count(*) from ws_feed f join media_assets m on m.id=f.entity_id
             where f.viewer='company' and f.event_type='MEDIA_ADDED' and m.category='before')=3
       then 'PASS' else 'FAIL' end;

insert into ws_results
select 'customer_sees_only_customer_visible_before_photo',
  case when (select count(*) from ws_feed f join media_assets m on m.id=f.entity_id
             where f.viewer='customer' and f.event_type='MEDIA_ADDED' and m.category='before')=1
       then 'PASS' else 'FAIL' end;

insert into ws_results
select 'customer_never_sees_an_internal_photo',
  case when (select count(*) from ws_feed f join media_assets m on m.id=f.entity_id
             where f.viewer='customer' and f.event_type='MEDIA_ADDED' and m.visibility<>'customer_visible')=0
       then 'PASS' else 'FAIL' end;

insert into ws_results
select 'customer_sees_customer_visible_progress_photo',
  case when (select count(*) from ws_feed f join media_assets m on m.id=f.entity_id
             where f.viewer='customer' and f.event_type='MEDIA_ADDED' and m.category='progress')=1
       then 'PASS' else 'FAIL' end;

insert into ws_results
select 'customer_never_sees_internal_work_note',
  case when (select count(*) from ws_feed where viewer='customer' and event_type='WORK_NOTE_ADDED')=0
       then 'PASS' else 'FAIL' end;

insert into ws_results
select 'staff_and_technician_do_see_internal_work_note',
  case when (select count(*) from ws_feed where viewer in ('company','technician') and event_type='WORK_NOTE_ADDED')=2
       then 'PASS' else 'FAIL' end;

insert into ws_results
select 'customer_does_not_see_tracking_or_timer_telemetry',
  case when (select count(*) from ws_feed where viewer='customer'
             and event_type in ('TECHNICIAN_TRACKING_STARTED','TIME_ENTRY_STARTED','TECHNICIAN_WORK_STARTED'))=0
       then 'PASS' else 'FAIL' end;

insert into ws_results
select 'customer_sees_en_route_and_arrived',
  case when (select count(distinct event_type) from ws_feed where viewer='customer'
             and event_type in ('TECHNICIAN_EN_ROUTE','TECHNICIAN_CHECKED_IN'))=2
       then 'PASS' else 'FAIL' end;

insert into ws_results
select 'customer_sees_visit_finished_continuation',
  case when (select count(*) from ws_feed where viewer='customer' and event_type='VISIT_FINISHED')=1
       then 'PASS' else 'FAIL' end;

insert into ws_results
select 'customer_sees_status_changes',
  case when (select count(*) from ws_feed where viewer='customer' and event_type='WORK_ORDER_STATUS_CHANGED')>0
       then 'PASS' else 'FAIL' end;

-- Multi-día: la visita se cierra, el work order NO
insert into ws_results
select 'finish_todays_visit_does_not_complete_work_order',
  case when (select current_status from work_orders where id='c0de0000-0000-4000-8000-000000000f11')='work_in_progress'
       then 'PASS' else 'FAIL' end;

insert into ws_results
select 'finish_todays_visit_records_outcome_and_next_visit',
  case when (select visit_outcome from appointments where id='c0de0000-0000-4000-8000-00000000ab11')='continue_tomorrow'
        and (select count(*) from appointments where work_order_id='c0de0000-0000-4000-8000-000000000f11')=2
       then 'PASS' else 'FAIL' end;

insert into ws_results
select 'first_gps_point_recorded',
  case when (select count(*) from technician_locations where work_order_id='c0de0000-0000-4000-8000-000000000f11')>=1
       then 'PASS' else 'FAIL' end;

select * from ws_results order by test_name;
select case when count(*) filter (where result='FAIL')=0
            then 'WORK STORY: ALL PASS (' || count(*) || ')'
            else 'WORK STORY: ' || count(*) filter (where result='FAIL') || ' FAILED' end as summary
from ws_results;

-- ---------- CLEANUP ----------
delete from progress_update_media where work_order_id='c0de0000-0000-4000-8000-000000000f11';
delete from progress_updates where work_order_id='c0de0000-0000-4000-8000-000000000f11';
delete from work_notes where work_order_id='c0de0000-0000-4000-8000-000000000f11';
delete from media_assets where work_order_id='c0de0000-0000-4000-8000-000000000f11';
delete from technician_locations where work_order_id='c0de0000-0000-4000-8000-000000000f11';
delete from technician_tracking_sessions where work_order_id='c0de0000-0000-4000-8000-000000000f11';
delete from time_entries where work_order_id='c0de0000-0000-4000-8000-000000000f11';
delete from check_ins where work_order_id='c0de0000-0000-4000-8000-000000000f11';
delete from appointments where work_order_id='c0de0000-0000-4000-8000-000000000f11';
delete from assignments where work_order_id='c0de0000-0000-4000-8000-000000000f11';
delete from notifications where organization_id='c0de0000-0000-4000-8000-000000000001';
delete from audit_events where organization_id='c0de0000-0000-4000-8000-000000000001';
delete from domain_events where organization_id='c0de0000-0000-4000-8000-000000000001';
delete from work_order_status_history where work_order_id='c0de0000-0000-4000-8000-000000000f11';
delete from work_orders where id='c0de0000-0000-4000-8000-000000000f11';
delete from vessels where id='c0de0000-0000-4000-8000-0000000000f1';
delete from customers where id='c0de0000-0000-4000-8000-0000000000e1';
delete from organization_subscriptions where organization_id='c0de0000-0000-4000-8000-000000000001';
delete from plan_module_entitlements where plan_id='c0de0000-0000-4000-8000-0000000000d1';
delete from subscription_plans where id='c0de0000-0000-4000-8000-0000000000d1';
delete from organization_memberships where organization_id='c0de0000-0000-4000-8000-000000000001';
delete from organizations where id='c0de0000-0000-4000-8000-000000000001';
delete from profiles where email like 'ws-%@rls-test.local';
delete from auth.users where email like 'ws-%@rls-test.local';

commit;
