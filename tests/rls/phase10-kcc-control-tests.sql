-- =========================================================
-- tests/rls/phase10-kcc-control-tests.sql
-- =========================================================
-- Suite reproducible de Phase 10. Corre sobre una base con las
-- migraciones 001-155 aplicadas. Última corrida en vivo, de punta a
-- punta desde este archivo: 21 (core) + 17 (hardening final) = 38/38
-- PASS.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('e1100000-0000-0000-0000-000000000001','p10-kccadmin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e1100000-0000-0000-0000-000000000002','p10-owner@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e1100000-0000-0000-0000-000000000003','p10-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e1100000-0000-0000-0000-000000000004','p10-customer@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('e1200000-0000-0000-0000-00000000000a','P10 Bootstrap Org','p10-bootstrap','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('e1100000-0000-0000-0000-000000000001','e1200000-0000-0000-0000-00000000000a','kcc_admin','active'),
  ('e1100000-0000-0000-0000-000000000002','e1200000-0000-0000-0000-00000000000a','company_owner','active'),
  ('e1100000-0000-0000-0000-000000000003','e1200000-0000-0000-0000-00000000000a','technician','active'),
  ('e1100000-0000-0000-0000-000000000004','e1200000-0000-0000-0000-00000000000a','customer','active')
on conflict do nothing;

create temporary table p10_all (test_name text, result text);
grant insert, select on p10_all to authenticated;

-- A. ORGANIZATION MANAGEMENT
set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$ begin begin
  perform create_organization('Should Fail Owner');
  insert into p10_all values ('test_owner_cannot_create_org', 'FAIL (no exception)');
exception when others then insert into p10_all values ('test_owner_cannot_create_org', 'PASS'); end; end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$ begin begin
  perform create_organization('Should Fail Tech');
  insert into p10_all values ('test_technician_cannot_create_org', 'FAIL (no exception)');
exception when others then insert into p10_all values ('test_technician_cannot_create_org', 'PASS'); end; end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000004","role":"authenticated"}';
do $$ begin begin
  perform create_organization('Should Fail Customer');
  insert into p10_all values ('test_customer_cannot_create_org', 'FAIL (no exception)');
exception when others then insert into p10_all values ('test_customer_cannot_create_org', 'PASS'); end; end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select create_organization('P10 Test Company', 'P10 Test Company LLC', null, 'America/New_York', 'USD', 'en', 'Main Dock', '123 Marina Way', 'newowner-p10@rls-test.local');
reset role;
insert into p10_all select 'test_kcc_admin_can_create_org', case when count(*)=1 then 'PASS' else 'FAIL' end from organizations where name='P10 Test Company';
insert into p10_all select 'test_org_settings_created', case when count(*)=1 then 'PASS' else 'FAIL' end from organization_settings where organization_id=(select id from organizations where name='P10 Test Company');
insert into p10_all select 'test_primary_location_created',
  case when (select count(*) from organization_locations where organization_id=(select id from organizations where name='P10 Test Company') and is_primary=true)=1 then 'PASS' else 'FAIL' end;
insert into p10_all select 'test_owner_invitation_created', case when count(*)=1 then 'PASS' else 'FAIL' end from organization_invitations where email='newowner-p10@rls-test.local';

-- B. TENANT ISOLATION
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('e1100000-0000-0000-0000-000000000002', (select id from organizations where name='P10 Test Company'), 'company_owner', 'active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p10_all select 'test_company_owner_cannot_read_compensation', case when count(*)=0 then 'PASS' else 'FAIL' end
from compensation_agreements where organization_id=(select id from organizations where name='P10 Test Company');
do $$ begin begin
  perform create_compensation_agreement((select id from organizations where name='P10 Test Company'), 'fixed', null, 300, 'USD', current_date, null, null);
  insert into p10_all values ('test_company_owner_cannot_create_compensation', 'FAIL (no exception)');
exception when others then insert into p10_all values ('test_company_owner_cannot_create_compensation', 'PASS'); end; end $$;
reset role;

select * from p10_all order by test_name;

-- =========================================================
-- C. STATUS / D. COMPENSATION / E. ATTRIBUTION
-- =========================================================

create temporary table p10b_all (test_name text, result text);
grant insert, select on p10b_all to authenticated;

-- status
set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$ begin begin
  perform set_organization_status((select id from organizations where name='P10 Test Company'), 'suspended');
  insert into p10b_all values ('test_unauthorized_cannot_suspend', 'FAIL (no exception)');
exception when others then insert into p10b_all values ('test_unauthorized_cannot_suspend', 'PASS'); end; end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select set_organization_status((select id from organizations where name='P10 Test Company'), 'suspended');
reset role;
insert into p10b_all select 'test_kcc_admin_can_suspend', case when status='suspended' then 'PASS' else 'FAIL' end from organizations where name='P10 Test Company';

set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p10b_all select 'test_suspended_org_member_loses_access', case when not is_org_member((select id from organizations where name='P10 Test Company')) then 'PASS' else 'FAIL' end;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select set_organization_status((select id from organizations where name='P10 Test Company'), 'active');
reset role;
insert into p10b_all select 'test_kcc_admin_can_reactivate', case when status='active' then 'PASS' else 'FAIL' end from organizations where name='P10 Test Company';

-- compensation
set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select create_compensation_agreement((select id from organizations where name='P10 Test Company'), 'percentage', 15.0, null, 'USD', '2026-01-01', null, 'Standard rate');
reset role;
insert into p10b_all select 'test_valid_percentage_succeeds', case when count(*)=1 then 'PASS' else 'FAIL' end from compensation_agreements where organization_id=(select id from organizations where name='P10 Test Company');

do $$ begin begin
  insert into compensation_agreements (organization_id, compensation_type, percentage_rate, fixed_amount, effective_from)
  values ((select id from organizations where name='P10 Test Company'), 'percentage', 15.0, 500, '2027-01-01');
  insert into p10b_all values ('test_percentage_with_fixed_amount_rejected', 'FAIL (no exception)');
exception when others then insert into p10b_all values ('test_percentage_with_fixed_amount_rejected', 'PASS'); end; end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$ begin begin
  perform create_compensation_agreement((select id from organizations where name='P10 Test Company'), 'fixed', null, 500, 'USD', '2026-06-01', null, 'overlap attempt');
  insert into p10b_all values ('test_overlapping_agreement_rejected', 'FAIL (no exception)');
exception when others then insert into p10b_all values ('test_overlapping_agreement_rejected', 'PASS'); end; end $$;
reset role;

-- attribution
set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('e1300000-0000-0000-0000-000000000001',(select id from organizations where name='P10 Test Company'),'e1100000-0000-0000-0000-000000000002','C','P10','e1100000-0000-0000-0000-000000000002');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('e1400000-0000-0000-0000-000000000001',(select id from organizations where name='P10 Test Company'),'e1300000-0000-0000-0000-000000000001','V P10','e1100000-0000-0000-0000-000000000002');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, kcc_generated, created_by) values ('e1500000-0000-0000-0000-000000000001',(select id from organizations where name='P10 Test Company'),'e1300000-0000-0000-0000-000000000001','e1400000-0000-0000-0000-000000000001','P10 KCC WO', true, 'e1100000-0000-0000-0000-000000000002');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, kcc_generated, created_by) values ('e1500000-0000-0000-0000-000000000002',(select id from organizations where name='P10 Test Company'),'e1300000-0000-0000-0000-000000000001','e1400000-0000-0000-0000-000000000001','P10 Non-KCC WO', false, 'e1100000-0000-0000-0000-000000000002');
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate((select id from organizations where name='P10 Test Company'),'e1300000-0000-0000-0000-000000000001','e1400000-0000-0000-0000-000000000001','e1500000-0000-0000-0000-000000000001', null, 'P10 Est', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'labor', 'Base', 1, 1000.00);
  perform send_estimate(v_est);
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000002","role":"authenticated"}';
select approve_estimate((select id from estimate_versions where title='P10 Est'));
reset role;

create temporary table p10c_all (test_name text, result text);
grant insert, select on p10c_all to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$ begin begin
  perform attribute_kcc_work('e1500000-0000-0000-0000-000000000002');
  insert into p10c_all values ('test_non_kcc_generated_rejected', 'FAIL (no exception)');
exception when others then insert into p10c_all values ('test_non_kcc_generated_rejected', 'PASS'); end; end $$;

select attribute_kcc_work('e1500000-0000-0000-0000-000000000001');
reset role;

insert into p10c_all select 'test_kcc_generated_resolves_correct_amount',
  case when calculated_kcc_amount = 150.00 and basis_amount = 1000.00 then 'PASS' else 'FAIL' end
from kcc_revenue_attributions where work_order_id='e1500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select attribute_kcc_work('e1500000-0000-0000-0000-000000000001');
reset role;
insert into p10c_all select 'test_idempotent_retry_no_duplicate', case when count(*)=1 then 'PASS' else 'FAIL' end
from kcc_revenue_attributions where work_order_id='e1500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select deactivate_compensation_agreement((select id from compensation_agreements where organization_id=(select id from organizations where name='P10 Test Company') and active=true));
select create_compensation_agreement((select id from organizations where name='P10 Test Company'), 'percentage', 25.0, null, 'USD', current_date, null, 'New rate');
reset role;
insert into p10c_all select 'test_historical_attribution_snapshot_stable', case when calculated_kcc_amount=150.00 then 'PASS' else 'FAIL' end
from kcc_revenue_attributions where work_order_id='e1500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"e1100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$ begin begin
  perform attribute_kcc_work('e1500000-0000-0000-0000-000000000001');
  insert into p10c_all values ('test_ordinary_client_cannot_forge_attribution', 'FAIL (no exception)');
exception when others then insert into p10c_all values ('test_ordinary_client_cannot_forge_attribution', 'PASS'); end; end $$;
reset role;

select * from p10b_all order by test_name;
select * from p10c_all order by test_name;

-- CLEANUP
delete from kcc_revenue_attributions where organization_id=(select id from organizations where name='P10 Test Company');
delete from compensation_agreements where organization_id=(select id from organizations where name='P10 Test Company');
delete from domain_events where organization_id=(select id from organizations where name='P10 Test Company');
delete from audit_events where organization_id=(select id from organizations where name='P10 Test Company');
update estimates set current_version_id = null where organization_id=(select id from organizations where name='P10 Test Company');
delete from estimate_decisions where organization_id=(select id from organizations where name='P10 Test Company');
delete from estimate_line_items where organization_id=(select id from organizations where name='P10 Test Company');
delete from estimate_versions where organization_id=(select id from organizations where name='P10 Test Company');
delete from estimates where organization_id=(select id from organizations where name='P10 Test Company');
delete from estimate_number_counters where organization_id=(select id from organizations where name='P10 Test Company');
delete from work_orders where organization_id=(select id from organizations where name='P10 Test Company');
delete from vessels where organization_id=(select id from organizations where name='P10 Test Company');
delete from customers where organization_id=(select id from organizations where name='P10 Test Company');
delete from organization_invitations where organization_id=(select id from organizations where name='P10 Test Company');
delete from organization_locations where organization_id=(select id from organizations where name='P10 Test Company');
delete from organization_settings where organization_id=(select id from organizations where name='P10 Test Company');
delete from organization_memberships where organization_id=(select id from organizations where name='P10 Test Company');
delete from organizations where name='P10 Test Company';
-- =========================================================
-- F. HARDENING FINAL — migraciones 151-155
-- =========================================================

create temporary table p10h_all (test_name text, result text);
grant insert, select on p10h_all to authenticated;

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('e3100000-0000-0000-0000-000000000001','p10h-kccadmin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e3100000-0000-0000-0000-000000000002','p10h-owner@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e3100000-0000-0000-0000-000000000003','p10h-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e3100000-0000-0000-0000-000000000004','p10h-customer@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('e3200000-0000-0000-0000-00000000000a','P10H Org','p10h-org','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('e3100000-0000-0000-0000-000000000001','e3200000-0000-0000-0000-00000000000a','kcc_admin','active'),
  ('e3100000-0000-0000-0000-000000000002','e3200000-0000-0000-0000-00000000000a','company_owner','active'),
  ('e3100000-0000-0000-0000-000000000003','e3200000-0000-0000-0000-00000000000a','technician','active'),
  ('e3100000-0000-0000-0000-000000000004','e3200000-0000-0000-0000-00000000000a','customer','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e3100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('e3300000-0000-0000-0000-000000000001','e3200000-0000-0000-0000-00000000000a','e3100000-0000-0000-0000-000000000004','C','P10H','e3100000-0000-0000-0000-000000000002');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('e3400000-0000-0000-0000-000000000001','e3200000-0000-0000-0000-00000000000a','e3300000-0000-0000-0000-000000000001','V P10H','e3100000-0000-0000-0000-000000000002');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('e3500000-0000-0000-0000-000000000001','e3200000-0000-0000-0000-00000000000a','e3300000-0000-0000-0000-000000000001','e3400000-0000-0000-0000-000000000001','P10H WO','e3100000-0000-0000-0000-000000000002');
insert into appointments (id, organization_id, work_order_id, scheduled_start) values ('e3600000-0000-0000-0000-000000000001','e3200000-0000-0000-0000-00000000000a','e3500000-0000-0000-0000-000000000001', now());
insert into assignments (organization_id, work_order_id, appointment_id, technician_profile_id, assigned_by) values ('e3200000-0000-0000-0000-00000000000a','e3500000-0000-0000-0000-000000000001','e3600000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000003','e3100000-0000-0000-0000-000000000002');
insert into time_entries (id, organization_id, work_order_id, technician_profile_id, entry_type, client_generated_id) values ('e3700000-0000-0000-0000-000000000001','e3200000-0000-0000-0000-00000000000a','e3500000-0000-0000-0000-000000000001','e3100000-0000-0000-0000-000000000003','work', gen_random_uuid());
reset role;

-- kcc_generated: escrituras directas imposibles incluso para kcc_admin
set local role authenticated;
set local request.jwt.claims = '{"sub":"e3100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$ begin begin
  insert into work_orders (organization_id, customer_id, vessel_id, title, kcc_generated, created_by)
  values ('e3200000-0000-0000-0000-00000000000a','e3300000-0000-0000-0000-000000000001','e3400000-0000-0000-0000-000000000001','Forged', true, 'e3100000-0000-0000-0000-000000000001');
  insert into p10h_all values ('test_kcc_admin_direct_insert_true_rejected', 'FAIL (no exception)');
exception when others then insert into p10h_all values ('test_kcc_admin_direct_insert_true_rejected', 'PASS'); end; end $$;
do $$ begin begin
  update work_orders set kcc_generated=true where id='e3500000-0000-0000-0000-000000000001';
  insert into p10h_all values ('test_kcc_admin_direct_update_rejected', 'FAIL (no exception)');
exception when others then insert into p10h_all values ('test_kcc_admin_direct_update_rejected', 'PASS'); end; end $$;

-- trusted RPC: sin acuerdo, ambos revierten
do $$ begin begin
  perform set_work_order_kcc_generated('e3500000-0000-0000-0000-000000000001', true);
  insert into p10h_all values ('test_no_agreement_rollback', 'FAIL (no exception)');
exception when others then insert into p10h_all values ('test_no_agreement_rollback', 'PASS'); end; end $$;
insert into p10h_all select 'test_flag_stayed_false_after_rollback', case when kcc_generated=false then 'PASS' else 'FAIL' end from work_orders where id='e3500000-0000-0000-0000-000000000001';

-- con acuerdo: atómico, revocación, reactivación
select create_compensation_agreement('e3200000-0000-0000-0000-00000000000a', 'percentage', 20.0, null, 'USD', current_date, null, 'P10H rate');
select set_work_order_kcc_generated('e3500000-0000-0000-0000-000000000001', true);
reset role;
insert into p10h_all select 'test_trusted_rpc_atomic_flag_and_attribution',
  case when (select kcc_generated from work_orders where id='e3500000-0000-0000-0000-000000000001')=true
   and (select count(*) from kcc_revenue_attributions where work_order_id='e3500000-0000-0000-0000-000000000001' and status='snapshot')=1
  then 'PASS' else 'FAIL' end;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e3100000-0000-0000-0000-000000000001","role":"authenticated"}';
select set_work_order_kcc_generated('e3500000-0000-0000-0000-000000000001', false);
reset role;
insert into p10h_all select 'test_revoke_on_false',
  case when status='revoked' and revoked_at is not null and revoked_by='e3100000-0000-0000-0000-000000000001' then 'PASS' else 'FAIL' end
from kcc_revenue_attributions where work_order_id='e3500000-0000-0000-0000-000000000001';
insert into p10h_all select 'test_revoke_audit_evidence',
  case when (select count(*) from domain_events where organization_id='e3200000-0000-0000-0000-00000000000a' and event_type='KCC_ATTRIBUTION_REVOKED')=1 then 'PASS' else 'FAIL' end;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e3100000-0000-0000-0000-000000000001","role":"authenticated"}';
select set_work_order_kcc_generated('e3500000-0000-0000-0000-000000000001', true);
reset role;
insert into p10h_all select 'test_reactivation_preserves_original_rate', case when compensation_rate=20.0 and status='snapshot' and revoked_at is null then 'PASS' else 'FAIL' end
from kcc_revenue_attributions where work_order_id='e3500000-0000-0000-0000-000000000001';
insert into p10h_all select 'test_reactivation_no_duplicate_row', case when count(*)=1 then 'PASS' else 'FAIL' end from kcc_revenue_attributions where work_order_id='e3500000-0000-0000-0000-000000000001';

-- suspensión: bloquea time_entries/técnico/customer, kcc_admin retiene
set local role authenticated;
set local request.jwt.claims = '{"sub":"e3100000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into p10h_all select 'test_before_suspend_tech_sees_time_entry', case when count(*)=1 then 'PASS' else 'FAIL' end from time_entries where id='e3700000-0000-0000-0000-000000000001';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e3100000-0000-0000-0000-000000000001","role":"authenticated"}';
select set_organization_status('e3200000-0000-0000-0000-00000000000a', 'suspended');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e3100000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into p10h_all select 'test_suspend_blocks_technician_time_entries', case when count(*)=0 then 'PASS' else 'FAIL' end from time_entries where id='e3700000-0000-0000-0000-000000000001';
insert into p10h_all select 'test_suspend_blocks_technician_work_order_access', case when count(*)=0 then 'PASS' else 'FAIL' end from work_orders where id='e3500000-0000-0000-0000-000000000001';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e3100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into p10h_all select 'test_suspend_blocks_customer_access', case when count(*)=0 then 'PASS' else 'FAIL' end from customers where id='e3300000-0000-0000-0000-000000000001';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e3100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into p10h_all select 'test_kcc_admin_retains_access_during_suspension', case when count(*)=1 then 'PASS' else 'FAIL' end from work_orders where id='e3500000-0000-0000-0000-000000000001';
select set_organization_status('e3200000-0000-0000-0000-00000000000a', 'active');
reset role;

-- ubicaciones: editar, desactivar, invariante de primaria
set local role authenticated;
set local request.jwt.claims = '{"sub":"e3100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into organization_locations (id, organization_id, name, is_primary) values ('e3800000-0000-0000-0000-000000000001','e3200000-0000-0000-0000-00000000000a','Dock A', true);
insert into organization_locations (id, organization_id, name, is_primary) values ('e3800000-0000-0000-0000-000000000002','e3200000-0000-0000-0000-00000000000a','Dock B', false);
select edit_location('e3800000-0000-0000-0000-000000000002', 'Dock B Renamed', '456 Rd', null);
select deactivate_location('e3800000-0000-0000-0000-000000000001', 'e3800000-0000-0000-0000-000000000002');
reset role;
insert into p10h_all select 'test_location_edit', case when name='Dock B Renamed' and address='456 Rd' then 'PASS' else 'FAIL' end from organization_locations where id='e3800000-0000-0000-0000-000000000002';
insert into p10h_all select 'test_location_deactivate_and_primary_replacement',
  case when (select is_primary from organization_locations where id='e3800000-0000-0000-0000-000000000002')=true
   and (select deleted_at is not null from organization_locations where id='e3800000-0000-0000-0000-000000000001')
   and (select count(*) from organization_locations where organization_id='e3200000-0000-0000-0000-00000000000a' and is_primary=true)=1
  then 'PASS' else 'FAIL' end;

-- auditoría de cambio de rol (trigger genérico ya existente)
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('e3100000-0000-0000-0000-000000000005','p10h-manager@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('e3100000-0000-0000-0000-000000000005','e3200000-0000-0000-0000-00000000000a','manager','active')
on conflict do nothing;
set local role authenticated;
set local request.jwt.claims = '{"sub":"e3100000-0000-0000-0000-000000000001","role":"authenticated"}';
select change_member_role((select id from organization_memberships where profile_id='e3100000-0000-0000-0000-000000000005' and organization_id='e3200000-0000-0000-0000-00000000000a'), 'company_admin');
reset role;
insert into p10h_all select 'test_membership_role_change_produces_audit_event',
  case when (select count(*) from audit_events where entity_type='organization_memberships' and organization_id='e3200000-0000-0000-0000-00000000000a')>=1 then 'PASS' else 'FAIL' end;

select * from p10h_all order by test_name;

delete from notifications where organization_id='e3200000-0000-0000-0000-00000000000a';
delete from kcc_revenue_attributions where organization_id='e3200000-0000-0000-0000-00000000000a';
delete from compensation_agreements where organization_id='e3200000-0000-0000-0000-00000000000a';
delete from organization_locations where organization_id='e3200000-0000-0000-0000-00000000000a';
delete from domain_events where organization_id='e3200000-0000-0000-0000-00000000000a';
delete from audit_events where organization_id='e3200000-0000-0000-0000-00000000000a';
delete from time_entries where organization_id='e3200000-0000-0000-0000-00000000000a';
delete from assignments where organization_id='e3200000-0000-0000-0000-00000000000a';
delete from appointments where organization_id='e3200000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id='e3200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id='e3200000-0000-0000-0000-00000000000a';
delete from customers where organization_id='e3200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id='e3200000-0000-0000-0000-00000000000a';
delete from organizations where id='e3200000-0000-0000-0000-00000000000a';
delete from profiles where email like 'p10h-%@rls-test.local';
delete from auth.users where email like 'p10h-%@rls-test.local';

delete from audit_events where organization_id='e1200000-0000-0000-0000-00000000000a';
delete from domain_events where organization_id='e1200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id='e1200000-0000-0000-0000-00000000000a';
delete from organizations where id='e1200000-0000-0000-0000-00000000000a';
delete from profiles where email like 'p10-%@rls-test.local';
delete from auth.users where email like 'p10-%@rls-test.local';
select 'phase10 suite cleanup complete' as status;
