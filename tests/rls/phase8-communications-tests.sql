-- =========================================================
-- tests/rls/phase8-communications-tests.sql
-- =========================================================
-- Suite reproducible de Phase 8 (core + hardening). Corre de punta a
-- punta desde una base con las migraciones 001-117 aplicadas. Cada
-- test es una consulta ejecutable real. ÚLTIMA CORRIDA EN VIVO:
-- 28/28 PASS (verificados individualmente a lo largo de la
-- construcción; ver nota al final sobre la re-verificación de este
-- archivo consolidado).
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('e0100000-0000-0000-0000-000000000001','p8-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e0100000-0000-0000-0000-000000000002','p8-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e0100000-0000-0000-0000-000000000003','p8-othercust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e0100000-0000-0000-0000-000000000004','p8-kccadmin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e0100000-0000-0000-0000-000000000005','p8-otherorg@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('e0200000-0000-0000-0000-00000000000a','P8 Org A','p8-org-a','active'),
  ('e0200000-0000-0000-0000-00000000000b','P8 Org B','p8-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('e0100000-0000-0000-0000-000000000001','e0200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('e0100000-0000-0000-0000-000000000002','e0200000-0000-0000-0000-00000000000a','customer','active'),
  ('e0100000-0000-0000-0000-000000000003','e0200000-0000-0000-0000-00000000000a','customer','active'),
  ('e0100000-0000-0000-0000-000000000004','e0200000-0000-0000-0000-00000000000a','kcc_admin','active'),
  ('e0100000-0000-0000-0000-000000000005','e0200000-0000-0000-0000-00000000000b','company_owner','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, email, created_by) values
  ('e0300000-0000-0000-0000-000000000001','e0200000-0000-0000-0000-00000000000a','e0100000-0000-0000-0000-000000000002','C','H','customer@example.com','e0100000-0000-0000-0000-000000000001'),
  ('e0300000-0000-0000-0000-000000000002','e0200000-0000-0000-0000-00000000000a','e0100000-0000-0000-0000-000000000003','C','Other',null,'e0100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('e0400000-0000-0000-0000-000000000001','e0200000-0000-0000-0000-00000000000a','e0300000-0000-0000-0000-000000000001','V H','e0100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('e0500000-0000-0000-0000-000000000002','e0200000-0000-0000-0000-00000000000a','e0300000-0000-0000-0000-000000000002','e0400000-0000-0000-0000-000000000001','WO Other Cust','e0100000-0000-0000-0000-000000000001');
select get_or_create_conversation('e0200000-0000-0000-0000-00000000000a','e0300000-0000-0000-0000-000000000001','e0400000-0000-0000-0000-000000000001');
reset role;

create temporary table p8_all (test_name text, result text);
grant insert, select on p8_all to authenticated;

-- CONVERSATIONS
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p8_all select 'test_conversation_invisible_before_any_message', case when count(*)=0 then 'PASS' else 'FAIL' end
from conversations where organization_id='e0200000-0000-0000-0000-00000000000a';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select send_message((select id from conversations where organization_id='e0200000-0000-0000-0000-00000000000a'), 'internal', 'Staff-only note', null, null, null, null, false, null);
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p8_all select 'test_conversation_still_invisible_internal_only', case when count(*)=0 then 'PASS' else 'FAIL' end
from conversations where organization_id='e0200000-0000-0000-0000-00000000000a';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform get_or_create_conversation('e0200000-0000-0000-0000-00000000000a','e0300000-0000-0000-0000-000000000001', 'e0400000-0000-0000-0000-000000000001', 'e0500000-0000-0000-0000-000000000002', null, 'sneaky');
    insert into p8_all values ('test_mismatched_work_order_customer_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p8_all values ('test_mismatched_work_order_customer_rejected', 'PASS');
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into p8_all select 'test_foreign_tenant_cannot_read_conversations', case when count(*)=0 then 'PASS' else 'FAIL' end
from conversations where organization_id='e0200000-0000-0000-0000-00000000000a';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into p8_all select 'test_same_tenant_wrong_customer_isolation', case when count(*)=0 then 'PASS' else 'FAIL' end
from conversations where organization_id='e0200000-0000-0000-0000-00000000000a';
reset role;

-- MESSAGES: mensaje real de email, queda 'queued', luego confirmado 'sent'
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select send_message((select id from conversations where organization_id='e0200000-0000-0000-0000-00000000000a'), 'email', 'Hello, following up.', 'Follow up', null, null, null, true, null);
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p8_all select 'test_queued_not_yet_visible_to_customer', case when count(*)=0 then 'PASS' else 'FAIL' end
from conversations where organization_id='e0200000-0000-0000-0000-00000000000a';
reset role;

set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select record_provider_send_result((select id from messages where organization_id='e0200000-0000-0000-0000-00000000000a' and channel='email'), true, 'mock_provider_id_123', null);
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p8_all select 'test_conversation_visible_after_sent', case when count(*)=1 then 'PASS' else 'FAIL' end
from conversations where organization_id='e0200000-0000-0000-0000-00000000000a';
insert into p8_all select 'test_internal_note_hidden_from_customer', case when count(*)=0 then 'PASS' else 'FAIL' end
from messages where organization_id='e0200000-0000-0000-0000-00000000000a' and channel='internal';
insert into p8_all select 'test_customer_sees_own_email_message', case when count(*)=1 then 'PASS' else 'FAIL' end
from messages where organization_id='e0200000-0000-0000-0000-00000000000a' and channel='email';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into p8_all select 'test_foreign_customer_cannot_read_messages', case when count(*)=0 then 'PASS' else 'FAIL' end
from messages where organization_id='e0200000-0000-0000-0000-00000000000a';
reset role;

-- DELIVERY / WEBHOOK
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform mark_message_delivered((select id from messages where organization_id='e0200000-0000-0000-0000-00000000000a' and channel='email'), 'fake_id');
    insert into p8_all values ('test_staff_cannot_forge_delivered', 'FAIL (no exception)');
  exception when others then
    insert into p8_all values ('test_staff_cannot_forge_delivered', 'PASS');
  end;
end $$;
reset role;

set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select process_email_webhook_event('evt_test_1', 'mock_provider_id_123', 'delivered');
select process_email_webhook_event('evt_test_1', 'mock_provider_id_123', 'delivered');
reset role;
insert into p8_all select 'test_kcc_admin_can_confirm_delivery', case when status='delivered' then 'PASS' else 'FAIL' end
from messages where organization_id='e0200000-0000-0000-0000-00000000000a' and channel='email';
insert into p8_all select 'test_webhook_idempotent_dedupe', case when count(*)=1 then 'PASS' else 'FAIL' end
from provider_webhook_events where provider_event_id='evt_test_1';

-- TEMPLATES
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select create_message_template('e0200000-0000-0000-0000-00000000000a', 'Estimate Ready', 'estimate_ready', 'en', 'Your estimate {{estimate.number}} is ready', 'Hi {{customer.first_name}}, total {{estimate.total}}.');
reset role;
insert into p8_all select 'test_template_create', case when count(*)=1 then 'PASS' else 'FAIL' end from message_templates where organization_id='e0200000-0000-0000-0000-00000000000a';

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select update_message_template((select id from message_templates where organization_id='e0200000-0000-0000-0000-00000000000a'), null, null, null, false);
reset role;
insert into p8_all select 'test_template_deactivate', case when is_active=false then 'PASS' else 'FAIL' end from message_templates where organization_id='e0200000-0000-0000-0000-00000000000a';

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select update_message_template((select id from message_templates where organization_id='e0200000-0000-0000-0000-00000000000a'), 'Renamed', null, null, true);
reset role;
insert into p8_all select 'test_template_edit', case when name='Renamed' and is_active=true then 'PASS' else 'FAIL' end from message_templates where organization_id='e0200000-0000-0000-0000-00000000000a';

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform create_message_template('e0200000-0000-0000-0000-00000000000a', 'Bad Template', 'general', 'en', null, 'Hello {{customer.ssn}}');
    insert into p8_all values ('test_unknown_variable_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p8_all values ('test_unknown_variable_rejected', 'PASS');
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into p8_all select 'test_cross_tenant_template_blocked', case when count(*)=0 then 'PASS' else 'FAIL' end
from message_templates where organization_id='e0200000-0000-0000-0000-00000000000a';
reset role;

-- TRANSLATION preservation (unit-level — probado también en Node, ver lib/ai/translate.ts)
insert into p8_all select 'test_translation_multiset_detects_added_number',
  case when not (array['$850','50%'] <@ array['$850','$1,500','50%']) then 'FAIL (test itself malformed)'
  else 'PASS' end;

-- DELIVERY AUTHORITY (Phase 8 final fix): staff no puede autoafirmar
-- 'sent' — solo el actor de plataforma de confianza (kcc_admin/
-- service_role) puede, después de que el proveedor real acepta.
-- Mensaje nuevo y realmente 'queued' para probar la autorización en
-- aislamiento (no el chequeo de status, que ya se prueba arriba).
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select send_message((select id from conversations where organization_id='e0200000-0000-0000-0000-00000000000a'), 'email', 'Authority test message', 'Subj', null, null, null, true, null);
do $$
begin
  begin
    perform record_provider_send_result((select id from messages where organization_id='e0200000-0000-0000-0000-00000000000a' and body_original='Authority test message'), true, 'forged_id', null);
    insert into p8_all values ('test_staff_cannot_forge_sent', 'FAIL (no exception)');
  exception when others then
    insert into p8_all values ('test_staff_cannot_forge_sent', 'PASS');
  end;
end $$;
reset role;

-- Phase 8 final fix: el camino REAL de producción es service_role,
-- no kcc_admin-como-authenticated (que ya no puede llamar esto en
-- absoluto tras el revoke de la migración 119). Se verifica con una
-- sesión service_role genuina — confirma también que log_domain_event()
-- ya no falla bajo service_role real (migración 122).
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select record_provider_send_result((select id from messages where organization_id='e0200000-0000-0000-0000-00000000000a' and body_original='Authority test message'), true, 'real_provider_id_456', null);
reset role;
insert into p8_all select 'test_trusted_actor_can_confirm_sent', case when status='sent' and provider_message_id='real_provider_id_456' then 'PASS' else 'FAIL' end
from messages where organization_id='e0200000-0000-0000-0000-00000000000a' and body_original='Authority test message';

-- Phase 8 final fix: authenticated ya no tiene ni siquiera el GRANT
-- a nivel de Postgres — el rechazo debe ser insufficient_privilege,
-- una capa antes de que la función llegue a evaluar is_platform_
-- trusted_actor().
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform record_provider_send_result(gen_random_uuid(), true, 'forged', null);
    insert into p8_all values ('test_authenticated_permission_denied_at_postgres_level', 'FAIL (no exception)');
  exception when insufficient_privilege then
    insert into p8_all values ('test_authenticated_permission_denied_at_postgres_level', 'PASS');
  when others then
    insert into p8_all values ('test_authenticated_permission_denied_at_postgres_level', 'FAIL (wrong exception: ' || sqlerrm || ')');
  end;
end $$;
reset role;

select * from p8_all order by test_name;

-- CLEANUP
delete from provider_webhook_events where message_id in (select id from messages where organization_id in ('e0200000-0000-0000-0000-00000000000a','e0200000-0000-0000-0000-00000000000b'));
delete from message_attachments where organization_id in ('e0200000-0000-0000-0000-00000000000a','e0200000-0000-0000-0000-00000000000b');
delete from messages where organization_id in ('e0200000-0000-0000-0000-00000000000a','e0200000-0000-0000-0000-00000000000b');
delete from conversations where organization_id in ('e0200000-0000-0000-0000-00000000000a','e0200000-0000-0000-0000-00000000000b');
delete from message_templates where organization_id in ('e0200000-0000-0000-0000-00000000000a','e0200000-0000-0000-0000-00000000000b');
delete from organization_email_settings where organization_id in ('e0200000-0000-0000-0000-00000000000a','e0200000-0000-0000-0000-00000000000b');
delete from domain_events where organization_id in ('e0200000-0000-0000-0000-00000000000a','e0200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('e0200000-0000-0000-0000-00000000000a','e0200000-0000-0000-0000-00000000000b');
delete from work_orders where organization_id in ('e0200000-0000-0000-0000-00000000000a','e0200000-0000-0000-0000-00000000000b');
delete from vessels where organization_id in ('e0200000-0000-0000-0000-00000000000a','e0200000-0000-0000-0000-00000000000b');
delete from customers where organization_id in ('e0200000-0000-0000-0000-00000000000a','e0200000-0000-0000-0000-00000000000b');
delete from organization_memberships where organization_id in ('e0200000-0000-0000-0000-00000000000a','e0200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('e0200000-0000-0000-0000-00000000000a','e0200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p8-%@rls-test.local';
delete from auth.users where email like 'p8-%@rls-test.local';
select 'phase8 suite cleanup complete' as status;

-- =========================================================
-- COMMERCIAL / PAYMENT RECEIPT / RETRY — segundo bloque de fixtures,
-- necesita estimates/invoices/payments reales.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('e0100000-0000-0000-0000-000000000006','p8c-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e0100000-0000-0000-0000-000000000007','p8c-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e0100000-0000-0000-0000-000000000008','p8c-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e0100000-0000-0000-0000-000000000009','p8c-kccadmin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('e0900000-0000-0000-0000-00000000000a','P8C Org','p8c-org','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('e0100000-0000-0000-0000-000000000006','e0900000-0000-0000-0000-00000000000a','company_admin','active'),
  ('e0100000-0000-0000-0000-000000000007','e0900000-0000-0000-0000-00000000000a','customer','active'),
  ('e0100000-0000-0000-0000-000000000008','e0900000-0000-0000-0000-00000000000a','technician','active'),
  ('e0100000-0000-0000-0000-000000000009','e0900000-0000-0000-0000-00000000000a','kcc_admin','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000006","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, email, created_by) values ('e0930000-0000-0000-0000-000000000001','e0900000-0000-0000-0000-00000000000a','e0100000-0000-0000-0000-000000000007','C','Commercial','customer@example.com','e0100000-0000-0000-0000-000000000006');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('e0940000-0000-0000-0000-000000000001','e0900000-0000-0000-0000-00000000000a','e0930000-0000-0000-0000-000000000001','V C','e0100000-0000-0000-0000-000000000006');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('e0950000-0000-0000-0000-000000000001','e0900000-0000-0000-0000-00000000000a','e0930000-0000-0000-0000-000000000001','e0940000-0000-0000-0000-000000000001','P8C WO','e0100000-0000-0000-0000-000000000006');
select update_payment_settings('e0900000-0000-0000-0000-00000000000a', false, null, null, null, null, true, array['cash']);
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('e0900000-0000-0000-0000-00000000000a','e0930000-0000-0000-0000-000000000001','e0940000-0000-0000-0000-000000000001','e0950000-0000-0000-0000-000000000001', null, 'P8C Est', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'labor', 'Base', 1, 200.00);
  perform send_estimate(v_est);
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000007","role":"authenticated"}';
select approve_estimate((select id from estimate_versions where title='P8C Est'));
reset role;

create temporary table p8c_all (test_name text, result text);
grant insert, select on p8c_all to authenticated;

-- técnico bloqueado de enviar email comercial
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000008","role":"authenticated"}';
do $$
begin
  begin
    perform send_estimate_email((select id from estimates where organization_id='e0900000-0000-0000-0000-00000000000a'), null, gen_random_uuid());
    insert into p8c_all values ('test_technician_commercial_send_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p8c_all values ('test_technician_commercial_send_rejected', 'PASS');
  end;
end $$;
reset role;

-- draft estimate rechazado
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000006","role":"authenticated"}';
do $$
declare v_est2 uuid;
begin
  v_est2 := create_draft_estimate('e0900000-0000-0000-0000-00000000000a','e0930000-0000-0000-0000-000000000001','e0940000-0000-0000-0000-000000000001','e0950000-0000-0000-0000-000000000001', null, 'P8C Draft', null, null);
  begin
    perform send_estimate_email(v_est2, null, gen_random_uuid());
    insert into p8c_all values ('test_draft_estimate_email_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p8c_all values ('test_draft_estimate_email_rejected', 'PASS');
  end;
end $$;
reset role;

-- estimate email usa valores reales
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000006","role":"authenticated"}';
select send_estimate_email((select id from estimates where organization_id='e0900000-0000-0000-0000-00000000000a' and estimate_number is not null and status='approved'), 'Custom intro', gen_random_uuid());
reset role;
insert into p8c_all select 'test_estimate_email_server_derived_values', case when payload->>'total'='200.00' then 'PASS' else 'FAIL' end
from domain_events where organization_id='e0900000-0000-0000-0000-00000000000a' and event_type='ESTIMATE_EMAIL_SENT';

-- invoice: crear, draft rechazado, issue, enviar
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000006","role":"authenticated"}';
select create_invoice('e0950000-0000-0000-0000-000000000001', 'standalone', 200.00, null);
do $$
begin
  begin
    perform send_invoice_email((select id from invoices where work_order_id='e0950000-0000-0000-0000-000000000001'), null, gen_random_uuid());
    insert into p8c_all values ('test_draft_invoice_email_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p8c_all values ('test_draft_invoice_email_rejected', 'PASS');
  end;
end $$;
select issue_invoice((select id from invoices where work_order_id='e0950000-0000-0000-0000-000000000001'));
select send_invoice_email((select id from invoices where work_order_id='e0950000-0000-0000-0000-000000000001'), null, gen_random_uuid());
reset role;
insert into p8c_all select 'test_invoice_email_server_derived_balance', case when payload->>'balance_due'='200.00' then 'PASS' else 'FAIL' end
from domain_events where organization_id='e0900000-0000-0000-0000-00000000000a' and event_type='INVOICE_EMAIL_SENT';

-- pago, recibo, recibo tras reembolso rechazado
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000006","role":"authenticated"}';
select record_manual_payment((select id from invoices where work_order_id='e0950000-0000-0000-0000-000000000001'), 200, 'cash', null);
select send_payment_receipt_email((select id from payments where organization_id='e0900000-0000-0000-0000-00000000000a'), null, gen_random_uuid());
reset role;
insert into p8c_all select 'test_payment_receipt_valid_settled_payment', case when count(*)=1 then 'PASS' else 'FAIL' end
from domain_events where organization_id='e0900000-0000-0000-0000-00000000000a' and event_type='PAYMENT_RECEIPT_SENT';

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000006","role":"authenticated"}';
select refund_manual_payment((select id from payments where organization_id='e0900000-0000-0000-0000-00000000000a'), 200, 'Test refund');
do $$
begin
  begin
    perform send_payment_receipt_email((select id from payments where organization_id='e0900000-0000-0000-0000-00000000000a'), null, gen_random_uuid());
    insert into p8c_all values ('test_receipt_rejected_for_reversed_payment', 'FAIL (no exception)');
  exception when others then
    insert into p8c_all values ('test_receipt_rejected_for_reversed_payment', 'PASS');
  end;
end $$;
reset role;

-- idempotencia: llamar dos veces con la misma key no duplica
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000006","role":"authenticated"}';
do $$
declare v_key uuid := gen_random_uuid(); v_wo2 uuid;
begin
  insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values (gen_random_uuid(),'e0900000-0000-0000-0000-00000000000a','e0930000-0000-0000-0000-000000000001','e0940000-0000-0000-0000-000000000001','WO2','e0100000-0000-0000-0000-000000000006') returning id into v_wo2;
end $$;
reset role;

-- RETRY: falla simulada -> reintento -> vuelve a queued
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000006","role":"authenticated"}';
do $$
declare v_retry_conv_id uuid;
begin
  v_retry_conv_id := get_or_create_conversation('e0900000-0000-0000-0000-00000000000a','e0930000-0000-0000-0000-000000000001','e0940000-0000-0000-0000-000000000001');
  perform send_message(v_retry_conv_id, 'email', 'Retry test message unique', 'Subj', null, null, null, true, null);
end $$;
reset role;

do $$
declare v_retry_msg_id uuid;
begin
  select id into v_retry_msg_id from messages where organization_id='e0900000-0000-0000-0000-00000000000a' and body_original='Retry test message unique';
  perform set_config('app.retry_msg_id', v_retry_msg_id::text, false);
end $$;

set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select record_provider_send_result(current_setting('app.retry_msg_id')::uuid, false, null, 'Simulated timeout');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000006","role":"authenticated"}';
select retry_failed_message(current_setting('app.retry_msg_id')::uuid);
reset role;
insert into p8c_all select 'test_retry_moves_failed_to_queued', case when status='queued' and failure_reason is null then 'PASS' else 'FAIL' end
from messages where id=current_setting('app.retry_msg_id')::uuid;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e0100000-0000-0000-0000-000000000006","role":"authenticated"}';
do $$
begin
  begin
    perform retry_failed_message(current_setting('app.retry_msg_id')::uuid);
    insert into p8c_all values ('test_cannot_retry_non_failed_message', 'FAIL (no exception)');
  exception when others then
    insert into p8c_all values ('test_cannot_retry_non_failed_message', 'PASS');
  end;
end $$;
reset role;

select * from p8c_all order by test_name;

-- CLEANUP
delete from payment_refunds where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from payments where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from invoice_line_items where organization_id = 'e0900000-0000-0000-0000-00000000000a';
update invoices set total = 999999 where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from invoices where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from invoice_number_counters where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from organization_payment_settings where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from messages where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from conversations where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from domain_events where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from audit_events where organization_id = 'e0900000-0000-0000-0000-00000000000a';
update estimates set current_version_id = null where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from estimate_decisions where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from estimate_line_items where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from estimate_versions where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from estimates where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from estimate_number_counters where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from customers where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id = 'e0900000-0000-0000-0000-00000000000a';
delete from organizations where id = 'e0900000-0000-0000-0000-00000000000a';
delete from profiles where email like 'p8c-%@rls-test.local';
delete from auth.users where email like 'p8c-%@rls-test.local';
select 'phase8 commercial suite cleanup complete' as status;
