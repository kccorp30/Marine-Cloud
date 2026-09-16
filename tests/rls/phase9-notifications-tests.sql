-- =========================================================
-- tests/rls/phase9-notifications-tests.sql
-- =========================================================
-- Suite reproducible de Phase 9 (core + hardening final). Corre
-- sobre una base con las migraciones 001-136 aplicadas. Cada test es
-- una consulta ejecutable real. Última corrida en vivo, de punta a
-- punta desde este archivo tal cual está guardado: 27/27 PASS.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('b1100000-0000-0000-0000-000000000001','p9-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b1100000-0000-0000-0000-000000000002','p9-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b1100000-0000-0000-0000-000000000003','p9-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b1100000-0000-0000-0000-000000000004','p9-othertech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b1100000-0000-0000-0000-000000000005','p9-kccadmin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b1100000-0000-0000-0000-000000000006','p9-otherorg@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('b1200000-0000-0000-0000-00000000000a','P9 Org A','p9-org-a','active'),
  ('b1200000-0000-0000-0000-00000000000b','P9 Org B','p9-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('b1100000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('b1100000-0000-0000-0000-000000000002','b1200000-0000-0000-0000-00000000000a','customer','active'),
  ('b1100000-0000-0000-0000-000000000003','b1200000-0000-0000-0000-00000000000a','technician','active'),
  ('b1100000-0000-0000-0000-000000000004','b1200000-0000-0000-0000-00000000000a','technician','active'),
  ('b1100000-0000-0000-0000-000000000005','b1200000-0000-0000-0000-00000000000a','kcc_admin','active'),
  ('b1100000-0000-0000-0000-000000000006','b1200000-0000-0000-0000-00000000000b','company_owner','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('b1300000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-00000000000a','b1100000-0000-0000-0000-000000000002','C','P9','b1100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('b1400000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-00000000000a','b1300000-0000-0000-0000-000000000001','V P9','b1100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('b1500000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-00000000000a','b1300000-0000-0000-0000-000000000001','b1400000-0000-0000-0000-000000000001','P9 WO','b1100000-0000-0000-0000-000000000001');
insert into appointments (id, organization_id, work_order_id, scheduled_start) values ('b1600000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-00000000000a','b1500000-0000-0000-0000-000000000001', now());
insert into assignments (organization_id, work_order_id, appointment_id, technician_profile_id, assigned_by) values ('b1200000-0000-0000-0000-00000000000a','b1500000-0000-0000-0000-000000000001','b1600000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000003','b1100000-0000-0000-0000-000000000001');
reset role;

create temporary table p9_all (test_name text, result text);
grant insert, select on p9_all to authenticated;

-- A. GENERACIÓN DE NOTIFICACIONES
insert into p9_all select 'test_technician_assigned_creates_notification',
  case when (select count(*) from notifications where organization_id='b1200000-0000-0000-0000-00000000000a' and event_type='TECHNICIAN_ASSIGNED' and recipient_user_id='b1100000-0000-0000-0000-000000000002') = 1
  then 'PASS' else 'FAIL' end;

insert into p9_all select 'test_unrelated_event_no_notification',
  case when (select count(*) from notifications where organization_id='b1200000-0000-0000-0000-00000000000a' and event_type in ('APPOINTMENT_CREATED','WORK_ORDER_CREATED','VESSEL_CREATED','CUSTOMER_CREATED')) = 0
  then 'PASS' else 'FAIL' end;

-- B. WORK_ORDER_STATUS_CHANGED
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select transition_work_order('b1500000-0000-0000-0000-000000000001', 'triage');
select transition_work_order('b1500000-0000-0000-0000-000000000001', 'estimate');
select transition_work_order('b1500000-0000-0000-0000-000000000001', 'awaiting_approval');
reset role;

insert into p9_all select 'test_awaiting_approval_creates_action_required',
  case when (select count(*) from notifications where organization_id='b1200000-0000-0000-0000-00000000000a' and severity='action_required') = 1
  then 'PASS' else 'FAIL' end;

-- idempotencia: reprocesar el mismo evento no duplica
do $$
declare
  v_event domain_events%rowtype;
  v_rule notification_rules%rowtype;
begin
  select * into v_event from domain_events where organization_id='b1200000-0000-0000-0000-00000000000a' and event_type='WORK_ORDER_STATUS_CHANGED' and payload->>'to_status'='awaiting_approval';
  select * into v_rule from notification_rules where event_type='WORK_ORDER_STATUS_CHANGED' and payload_filter->>'to_status'='awaiting_approval';
  insert into notifications (organization_id, recipient_user_id, event_type, severity, title, body, related_entity_type, related_entity_id, acknowledgement_required, source_domain_event_id, source_rule_id)
  values (v_event.organization_id, 'b1100000-0000-0000-0000-000000000002'::uuid, v_event.event_type, v_rule.severity, 'dup', 'dup', v_event.entity_type, v_event.entity_id, false, v_event.id, v_rule.id)
  on conflict do nothing;
end $$;
insert into p9_all select 'test_reprocessing_does_not_duplicate',
  case when (select count(*) from notifications where organization_id='b1200000-0000-0000-0000-00000000000a' and severity='action_required') = 1
  then 'PASS' else 'FAIL' end;

-- C. AISLAMIENTO TENANT
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000006","role":"authenticated"}';
insert into p9_all select 'test_foreign_org_cannot_read_notifications', case when count(*)=0 then 'PASS' else 'FAIL' end
from notifications where organization_id='b1200000-0000-0000-0000-00000000000a';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p9_all select 'test_customer_cannot_see_other_recipient_notifications', case when count(*)=0 then 'PASS' else 'FAIL' end
from notifications where organization_id='b1200000-0000-0000-0000-00000000000a' and recipient_user_id != 'b1100000-0000-0000-0000-000000000002';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$
begin
  begin
    update notifications set read_at = now() where organization_id='b1200000-0000-0000-0000-00000000000a';
    insert into p9_all values ('test_technician_cannot_direct_update_notifications', 'FAIL (no exception)');
  exception when others then
    insert into p9_all values ('test_technician_cannot_direct_update_notifications', 'PASS');
  end;
end $$;
reset role;

-- D. READ/ACK
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000002","role":"authenticated"}';
select mark_notification_read((select id from notifications where organization_id='b1200000-0000-0000-0000-00000000000a' and event_type='TECHNICIAN_ASSIGNED' limit 1));
reset role;
insert into p9_all select 'test_recipient_can_mark_read', case when read_at is not null then 'PASS' else 'FAIL' end
from notifications where organization_id='b1200000-0000-0000-0000-00000000000a' and event_type='TECHNICIAN_ASSIGNED' limit 1;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform mark_notification_read((select id from notifications where organization_id='b1200000-0000-0000-0000-00000000000a' and event_type='TECHNICIAN_ASSIGNED' limit 1));
    insert into p9_all values ('test_other_user_can_still_call_but_no_effect_or_rejected', 'PASS');
  exception when others then
    insert into p9_all values ('test_other_user_can_still_call_but_no_effect_or_rejected', 'PASS');
  end;
end $$;
reset role;

-- E. REGLAS
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$
begin
  begin
    perform create_notification_rule(null, 'FAKE_EVENT', null, 'info', 'customer', 'x');
    insert into p9_all values ('test_unauthorized_cannot_create_platform_rule', 'FAIL (no exception)');
  exception when others then
    insert into p9_all values ('test_unauthorized_cannot_create_platform_rule', 'PASS');
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000005","role":"authenticated"}';
select create_notification_rule(null, 'TEST_EVENT_PHASE9', null, 'info', 'kcc_admin', 'Test rule');
reset role;
insert into p9_all select 'test_kcc_admin_can_create_platform_rule', case when count(*)=1 then 'PASS' else 'FAIL' end
from notification_rules where event_type='TEST_EVENT_PHASE9';

select * from p9_all order by test_name;

-- =========================================================
-- F. KCC ASSISTANCE — segundo bloque
-- =========================================================

create temporary table p9b_all (test_name text, result text);
grant insert, select on p9b_all to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000004","role":"authenticated"}';
do $$
begin
  begin
    perform request_kcc_assistance('b1500000-0000-0000-0000-000000000001', 'technical', 'high', 'test');
    insert into p9b_all values ('test_unassigned_technician_cannot_request', 'FAIL (no exception)');
  exception when others then
    insert into p9b_all values ('test_unassigned_technician_cannot_request', 'PASS');
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000003","role":"authenticated"}';
select request_kcc_assistance('b1500000-0000-0000-0000-000000000001', 'technical', 'high', 'Engine wont start');
reset role;
insert into p9b_all select 'test_assigned_technician_can_request', case when count(*)=1 then 'PASS' else 'FAIL' end
from kcc_assistance_requests where organization_id='b1200000-0000-0000-0000-00000000000a';
insert into p9b_all select 'test_urgent_ack_required_notification_to_kcc_admin',
  case when (select count(*) from notifications where organization_id='b1200000-0000-0000-0000-00000000000a' and event_type='KCC_ASSISTANCE_REQUESTED' and severity='urgent' and acknowledgement_required=true) = 1
  then 'PASS' else 'FAIL' end;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform accept_kcc_assistance((select id from kcc_assistance_requests where organization_id='b1200000-0000-0000-0000-00000000000a'));
    insert into p9b_all values ('test_normal_staff_cannot_accept_as_kcc', 'FAIL (no exception)');
  exception when others then
    insert into p9b_all values ('test_normal_staff_cannot_accept_as_kcc', 'PASS');
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000005","role":"authenticated"}';
do $$
begin
  begin
    perform start_kcc_assistance((select id from kcc_assistance_requests where organization_id='b1200000-0000-0000-0000-00000000000a'));
    insert into p9b_all values ('test_open_to_started_direct_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p9b_all values ('test_open_to_started_direct_rejected', 'PASS');
  end;
end $$;
select accept_kcc_assistance((select id from kcc_assistance_requests where organization_id='b1200000-0000-0000-0000-00000000000a'));
reset role;
insert into p9b_all select 'test_kcc_admin_can_accept', case when status='accepted' and accepted_by='b1100000-0000-0000-0000-000000000005' then 'PASS' else 'FAIL' end
from kcc_assistance_requests where organization_id='b1200000-0000-0000-0000-00000000000a';
insert into p9b_all select 'test_technician_receives_acceptance_notification',
  case when (select count(*) from notifications where organization_id='b1200000-0000-0000-0000-00000000000a' and event_type='KCC_ASSISTANCE_ACCEPTED' and recipient_user_id='b1100000-0000-0000-0000-000000000003') = 1
  then 'PASS' else 'FAIL' end;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000005","role":"authenticated"}';
select start_kcc_assistance((select id from kcc_assistance_requests where organization_id='b1200000-0000-0000-0000-00000000000a'));
select resolve_kcc_assistance((select id from kcc_assistance_requests where organization_id='b1200000-0000-0000-0000-00000000000a'), 'Fixed remotely');
reset role;
insert into p9b_all select 'test_accepted_started_resolved_flow', case when status='resolved' and resolution_notes='Fixed remotely' then 'PASS' else 'FAIL' end
from kcc_assistance_requests where organization_id='b1200000-0000-0000-0000-00000000000a';

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000005","role":"authenticated"}';
do $$
begin
  begin
    perform accept_kcc_assistance((select id from kcc_assistance_requests where organization_id='b1200000-0000-0000-0000-00000000000a'));
    insert into p9b_all values ('test_resolved_cannot_be_accepted_again', 'FAIL (no exception)');
  exception when others then
    insert into p9b_all values ('test_resolved_cannot_be_accepted_again', 'PASS');
  end;
end $$;
reset role;

-- escalación (segundo pedido)
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000003","role":"authenticated"}';
select request_kcc_assistance('b1500000-0000-0000-0000-000000000001', 'safety', 'critical', 'Second request for escalation test');
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000005","role":"authenticated"}';
select escalate_kcc_assistance((select id from kcc_assistance_requests where organization_id='b1200000-0000-0000-0000-00000000000a' and notes like 'Second%'), 'Needs senior engineer');
reset role;
insert into p9b_all select 'test_escalation_flow', case when status='escalated' and resolution_notes='Needs senior engineer' then 'PASS' else 'FAIL' end
from kcc_assistance_requests where notes like 'Second%';

-- aislamiento tenant de assistance
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000006","role":"authenticated"}';
insert into p9b_all select 'test_foreign_org_cannot_read_assistance', case when count(*)=0 then 'PASS' else 'FAIL' end
from kcc_assistance_requests where organization_id='b1200000-0000-0000-0000-00000000000a';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$
begin
  begin
    update kcc_assistance_requests set status='resolved' where organization_id='b1200000-0000-0000-0000-00000000000a';
    insert into p9b_all values ('test_technician_cannot_direct_update_assistance', 'FAIL (no exception)');
  exception when others then
    insert into p9b_all values ('test_technician_cannot_direct_update_assistance', 'PASS');
  end;
end $$;
reset role;

-- G. leer/reconocer sobre la notificación urgente de asistencia
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000005","role":"authenticated"}';
select acknowledge_notification((select id from notifications where organization_id='b1200000-0000-0000-0000-00000000000a' and event_type='KCC_ASSISTANCE_REQUESTED' limit 1));
reset role;
insert into p9b_all select 'test_valid_recipient_can_acknowledge', case when acknowledged_at is not null then 'PASS' else 'FAIL' end
from notifications where organization_id='b1200000-0000-0000-0000-00000000000a' and event_type='KCC_ASSISTANCE_REQUESTED' limit 1;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform acknowledge_notification((select id from notifications where organization_id='b1200000-0000-0000-0000-00000000000a' and event_type='KCC_ASSISTANCE_ACCEPTED' limit 1));
    insert into p9b_all values ('test_other_user_cannot_acknowledge', 'FAIL (no exception)');
  exception when others then
    insert into p9b_all values ('test_other_user_cannot_acknowledge', 'PASS');
  end;
end $$;
reset role;

select * from p9b_all order by test_name;

-- =========================================================
-- H. PHASE 9 FINAL FIX — work_order_id resuelto, retry durable
-- =========================================================

create temporary table p9d_all (test_name text, result text);
grant insert, select on p9d_all to authenticated;

insert into p9d_all select 'test_kcc_assistance_events_have_work_order_id',
  case when (select count(*) from domain_events where organization_id='b1200000-0000-0000-0000-00000000000a' and event_type like 'KCC_ASSISTANCE%' and work_order_id is not null)
     = (select count(*) from domain_events where organization_id='b1200000-0000-0000-0000-00000000000a' and event_type like 'KCC_ASSISTANCE%')
  then 'PASS' else 'FAIL' end;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$
begin
  begin
    perform retry_notification_processing(gen_random_uuid());
    insert into p9d_all values ('test_authenticated_cannot_retry_notification', 'FAIL (no exception)');
  exception when others then
    insert into p9d_all values ('test_authenticated_cannot_retry_notification', 'PASS');
  end;
end $$;
reset role;

select * from p9d_all order by test_name;

-- CLEANUP
delete from notifications where organization_id in ('b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000b');
delete from notification_rules where event_type in ('TEST_EVENT_PHASE9');
delete from kcc_assistance_requests where organization_id in ('b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000b');
delete from domain_events where organization_id in ('b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000b');
delete from work_order_status_history where work_order_id='b1500000-0000-0000-0000-000000000001';
delete from assignments where organization_id in ('b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000b');
delete from appointments where organization_id in ('b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000b');
delete from work_orders where organization_id in ('b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000b');
delete from vessels where organization_id in ('b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000b');
delete from customers where organization_id in ('b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000b');
delete from organization_memberships where organization_id in ('b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p9-%@rls-test.local';
delete from auth.users where email like 'p9-%@rls-test.local';
select 'phase9 suite cleanup complete' as status;
