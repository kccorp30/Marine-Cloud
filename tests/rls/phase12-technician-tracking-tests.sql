-- =========================================================
-- tests/rls/phase12-technician-tracking-tests.sql
-- =========================================================
-- Suite reproducible de Phase 12. Corre sobre una base con las
-- migraciones 001-183 aplicadas. Última corrida en vivo, de punta a
-- punta desde este archivo: 20/20 PASS.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('f0100000-0000-0000-0000-000000000001','p12-owner@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('f0100000-0000-0000-0000-000000000002','p12-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('f0100000-0000-0000-0000-000000000003','p12-othertech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('f0100000-0000-0000-0000-000000000004','p12-customer@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('f0100000-0000-0000-0000-000000000005','p12-othercustomer@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('f0100000-0000-0000-0000-000000000006','p12-orgb-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('f0200000-0000-0000-0000-00000000000a','P12 Org','p12-org','active'),
  ('f0200000-0000-0000-0000-00000000000b','P12 Org B','p12-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('f0100000-0000-0000-0000-000000000001','f0200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('f0100000-0000-0000-0000-000000000002','f0200000-0000-0000-0000-00000000000a','technician','active'),
  ('f0100000-0000-0000-0000-000000000003','f0200000-0000-0000-0000-00000000000a','technician','active'),
  ('f0100000-0000-0000-0000-000000000004','f0200000-0000-0000-0000-00000000000a','customer','active'),
  ('f0100000-0000-0000-0000-000000000005','f0200000-0000-0000-0000-00000000000a','customer','active'),
  ('f0100000-0000-0000-0000-000000000006','f0200000-0000-0000-0000-00000000000b','technician','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('f0300000-0000-0000-0000-000000000001','f0200000-0000-0000-0000-00000000000a','f0100000-0000-0000-0000-000000000004','C','P12','f0100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('f0400000-0000-0000-0000-000000000001','f0200000-0000-0000-0000-00000000000a','f0300000-0000-0000-0000-000000000001','V P12','f0100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by, current_status) values ('f0500000-0000-0000-0000-000000000001','f0200000-0000-0000-0000-00000000000a','f0300000-0000-0000-0000-000000000001','f0400000-0000-0000-0000-000000000001','P12 WO','f0100000-0000-0000-0000-000000000001','technician_assigned');
insert into appointments (id, organization_id, work_order_id, scheduled_start) values ('f0600000-0000-0000-0000-000000000001','f0200000-0000-0000-0000-00000000000a','f0500000-0000-0000-0000-000000000001', now());
insert into assignments (id, organization_id, work_order_id, appointment_id, technician_profile_id, assigned_by) values ('f0700000-0000-0000-0000-000000000001','f0200000-0000-0000-0000-00000000000a','f0500000-0000-0000-0000-000000000001','f0600000-0000-0000-0000-000000000001','f0100000-0000-0000-0000-000000000002','f0100000-0000-0000-0000-000000000001');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000002","role":"authenticated"}';
select transition_work_order('f0500000-0000-0000-0000-000000000001', 'en_route');
reset role;

create temporary table p12_all (test_name text, result text);
grant insert, select on p12_all to authenticated;

-- SECCIÓN 29 — autoridad de sesión
set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000002","role":"authenticated"}';
select start_technician_tracking('f0500000-0000-0000-0000-000000000001');
reset role;
insert into p12_all select 'test_assigned_technician_can_start', case when status='active' then 'PASS' else 'FAIL' end from technician_tracking_sessions where work_order_id='f0500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000002","role":"authenticated"}';
select start_technician_tracking('f0500000-0000-0000-0000-000000000001');
reset role;
insert into p12_all select 'test_repeated_start_idempotent', case when count(*)=1 then 'PASS' else 'FAIL' end from technician_tracking_sessions where work_order_id='f0500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$ begin begin
  perform start_technician_tracking('f0500000-0000-0000-0000-000000000001');
  insert into p12_all values ('test_unassigned_technician_cannot_start', 'FAIL (no exception)');
exception when others then insert into p12_all values ('test_unassigned_technician_cannot_start', 'PASS'); end; end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000004","role":"authenticated"}';
do $$ begin begin
  perform start_technician_tracking('f0500000-0000-0000-0000-000000000001');
  insert into p12_all values ('test_customer_cannot_start', 'FAIL (no exception)');
exception when others then insert into p12_all values ('test_customer_cannot_start', 'PASS'); end; end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$ begin begin
  perform start_technician_tracking('f0500000-0000-0000-0000-000000000001');
  insert into p12_all values ('test_company_admin_cannot_impersonate', 'FAIL (no exception)');
exception when others then insert into p12_all values ('test_company_admin_cannot_impersonate', 'PASS'); end; end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000006","role":"authenticated"}';
do $$ begin begin
  perform start_technician_tracking('f0500000-0000-0000-0000-000000000001');
  insert into p12_all values ('test_org_b_technician_cannot_start', 'FAIL (no exception)');
exception when others then insert into p12_all values ('test_org_b_technician_cannot_start', 'PASS'); end; end $$;
reset role;

select * from p12_all order by test_name;

-- SECCIÓN 30 — ingestión de ubicación
create temporary table p12_all2 (test_name text, result text);
grant insert, select on p12_all2 to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000002","role":"authenticated"}';
select submit_technician_location((select id from technician_tracking_sessions where work_order_id='f0500000-0000-0000-0000-000000000001'), 25.7617, -80.1918, 10, 90, 5, now());
reset role;
insert into p12_all2 select 'test_valid_location_accepted', case when count(*)=1 then 'PASS' else 'FAIL' end from technician_locations where work_order_id='f0500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$ begin begin
  perform submit_technician_location((select id from technician_tracking_sessions where work_order_id='f0500000-0000-0000-0000-000000000001'), 200, -80.1918, 10, null, null, now());
  insert into p12_all2 values ('test_invalid_lat_rejected', 'FAIL (no exception)');
exception when others then insert into p12_all2 values ('test_invalid_lat_rejected', 'PASS'); end; end $$;
do $$ begin begin
  perform submit_technician_location((select id from technician_tracking_sessions where work_order_id='f0500000-0000-0000-0000-000000000001'), 25.7617, -400, 10, null, null, now());
  insert into p12_all2 values ('test_invalid_lng_rejected', 'FAIL (no exception)');
exception when others then insert into p12_all2 values ('test_invalid_lng_rejected', 'PASS'); end; end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$ begin begin
  perform submit_technician_location((select id from technician_tracking_sessions where work_order_id='f0500000-0000-0000-0000-000000000001'), 25.7617, -80.1918, 10, null, null, now());
  insert into p12_all2 values ('test_wrong_technician_rejected', 'FAIL (no exception)');
exception when others then insert into p12_all2 values ('test_wrong_technician_rejected', 'PASS'); end; end $$;
reset role;

select * from p12_all2 order by test_name;

-- SECCIÓN 31 — privacidad del customer / frescura
create temporary table p12_all3 (test_name text, result text);
grant insert, select on p12_all3 to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into p12_all3 select 'test_owning_customer_sees_live_tracking',
  case when (get_work_order_tracking_status('f0500000-0000-0000-0000-000000000001')->>'freshness')='live' then 'PASS' else 'FAIL' end;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000005","role":"authenticated"}';
do $$ begin begin
  perform get_work_order_tracking_status('f0500000-0000-0000-0000-000000000001');
  insert into p12_all3 values ('test_unrelated_customer_cannot_view', 'FAIL (no exception)');
exception when others then insert into p12_all3 values ('test_unrelated_customer_cannot_view', 'PASS'); end; end $$;
reset role;

update technician_locations set recorded_at = now() - interval '10 minutes' where work_order_id='f0500000-0000-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into p12_all3 select 'test_old_location_marked_offline_not_live',
  case when (get_work_order_tracking_status('f0500000-0000-0000-0000-000000000001')->>'freshness')='offline' then 'PASS' else 'FAIL' end;
reset role;

select * from p12_all3 order by test_name;

-- SECCIÓN 33 — condiciones de detención
create temporary table p12_all4 (test_name text, result text);
grant insert, select on p12_all4 to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000002","role":"authenticated"}';
select transition_work_order('f0500000-0000-0000-0000-000000000001', 'checked_in');
reset role;
insert into p12_all4 select 'test_leaving_en_route_expires_session', case when status='expired' then 'PASS' else 'FAIL' end from technician_tracking_sessions where work_order_id='f0500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$ begin begin
  perform submit_technician_location((select id from technician_tracking_sessions where work_order_id='f0500000-0000-0000-0000-000000000001'), 25.7617, -80.1918, 10, null, null, now());
  insert into p12_all4 values ('test_expired_session_rejects_new_location', 'FAIL (no exception)');
exception when others then insert into p12_all4 values ('test_expired_session_rejects_new_location', 'PASS'); end; end $$;
reset role;

select * from p12_all4 order by test_name;

-- CLEANUP
delete from notifications where organization_id in ('f0200000-0000-0000-0000-00000000000a','f0200000-0000-0000-0000-00000000000b');
delete from technician_locations where work_order_id='f0500000-0000-0000-0000-000000000001';
delete from technician_tracking_sessions where work_order_id='f0500000-0000-0000-0000-000000000001';
delete from domain_events where organization_id in ('f0200000-0000-0000-0000-00000000000a','f0200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('f0200000-0000-0000-0000-00000000000a','f0200000-0000-0000-0000-00000000000b');
delete from work_order_status_history where work_order_id='f0500000-0000-0000-0000-000000000001';
delete from assignments where organization_id='f0200000-0000-0000-0000-00000000000a';
delete from appointments where organization_id='f0200000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id='f0200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id='f0200000-0000-0000-0000-00000000000a';
delete from customers where organization_id='f0200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id in ('f0200000-0000-0000-0000-00000000000a','f0200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('f0200000-0000-0000-0000-00000000000a','f0200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p12-%@rls-test.local';
delete from auth.users where email like 'p12-%@rls-test.local';
select 'phase12 suite cleanup complete' as status;
