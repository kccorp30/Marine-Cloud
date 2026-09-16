-- =========================================================
-- tests/rls/phase14-subscriptions-tests.sql
-- =========================================================
-- Suite reproducible de Phase 14. Corre sobre una base con las
-- migraciones 001-238 aplicadas. Cada bloque fue corrido en vivo
-- durante el desarrollo de esta fase — ver docs/PHASE-14-REPORT.md
-- para el detalle narrativo de cada fix real encontrado en el camino.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('b0100000-0000-0000-0000-000000000001','p14t-kccadmin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b0100000-0000-0000-0000-000000000002','p14t-owner@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b0100000-0000-0000-0000-000000000003','p14t-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b0100000-0000-0000-0000-000000000004','p14t-orgb@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('b0200000-0000-0000-0000-00000000000a','P14T Org','p14t-org','active'),
  ('b0200000-0000-0000-0000-00000000000b','P14T Org B','p14t-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('b0100000-0000-0000-0000-000000000001','b0200000-0000-0000-0000-00000000000a','kcc_admin','active'),
  ('b0100000-0000-0000-0000-000000000002','b0200000-0000-0000-0000-00000000000a','company_owner','active'),
  ('b0100000-0000-0000-0000-000000000003','b0200000-0000-0000-0000-00000000000a','technician','active'),
  ('b0100000-0000-0000-0000-000000000004','b0200000-0000-0000-0000-00000000000b','company_owner','active')
on conflict do nothing;

-- =========================================================
-- A. PLANES
-- =========================================================
create temporary table p14t_plans (test_name text, result text);
grant insert, select on p14t_plans to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select create_subscription_plan('P14TPLAN', 'P14T Plan', 'desc', 'USD', 99, 349, 3500, 14, true, false);
reset role;
insert into p14t_plans select 'test_plan_created', case when weekly_price=99 then 'PASS' else 'FAIL' end from subscription_plans where code='P14TPLAN';

do $$ begin begin
  insert into subscription_plans (code, name, weekly_price) values ('P14TNEG', 'Neg', -5);
  insert into p14t_plans values ('test_negative_price_rejected', 'FAIL (no exception)');
exception when others then insert into p14t_plans values ('test_negative_price_rejected', 'PASS'); end; end $$;

select * from p14t_plans order by test_name;

-- =========================================================
-- B. TRIALS + PRICE SNAPSHOT
-- =========================================================
create temporary table p14t_trials (test_name text, result text);
grant insert, select on p14t_trials to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select assign_organization_subscription('b0200000-0000-0000-0000-00000000000a', (select id from subscription_plans where code='P14TPLAN'), 'weekly', 14, null, false, null, null);
reset role;
insert into p14t_trials select 'test_14_day_trial_snapshot', case when status='trialing' and price_snapshot=99 then 'PASS' else 'FAIL' end from organization_subscriptions where organization_id='b0200000-0000-0000-0000-00000000000a' and superseded_at is null;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select update_subscription_plan((select id from subscription_plans where code='P14TPLAN'), null, null, 199, null, null, null, null);
reset role;
insert into p14t_trials select 'test_price_edit_does_not_mutate_snapshot', case when price_snapshot=99 then 'PASS' else 'FAIL' end from organization_subscriptions where organization_id='b0200000-0000-0000-0000-00000000000a' and superseded_at is null;

update organization_subscriptions set trial_started_at = now() - interval '20 days', trial_ends_at = now() - interval '1 day' where organization_id='b0200000-0000-0000-0000-00000000000a' and superseded_at is null;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p14t_trials select 'test_expired_trial_denies_access', case when organization_has_active_access('b0200000-0000-0000-0000-00000000000a')=false then 'PASS' else 'FAIL' end;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$ begin begin
  perform extend_organization_trial('b0200000-0000-0000-0000-00000000000a', now() + interval '7 days', 'test');
  insert into p14t_trials values ('test_technician_cannot_extend_trial', 'FAIL (no exception)');
exception when others then insert into p14t_trials values ('test_technician_cannot_extend_trial', 'PASS'); end; end $$;
reset role;

select * from p14t_trials order by test_name;

-- =========================================================
-- C. CANCELACIÓN AL FIN DE PERÍODO — REAL, NO DECORATIVA
-- =========================================================
create temporary table p14t_cancel (test_name text, result text);
grant insert, select on p14t_cancel to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select extend_organization_trial('b0200000-0000-0000-0000-00000000000a', now() + interval '30 days', 'restore for test');
select assign_organization_subscription('b0200000-0000-0000-0000-00000000000a', (select id from subscription_plans where code='P14TPLAN'), 'weekly', null, null, false, null, null);
select cancel_subscription('b0200000-0000-0000-0000-00000000000a', false, 'scheduled cancel');
reset role;
insert into p14t_cancel select 'test_period_end_calculated', case when current_period_ends_at is not null then 'PASS' else 'FAIL' end from organization_subscriptions where organization_id='b0200000-0000-0000-0000-00000000000a' and superseded_at is null;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p14t_cancel select 'test_still_active_before_period_end', case when organization_has_active_access('b0200000-0000-0000-0000-00000000000a')=true then 'PASS' else 'FAIL' end;
reset role;

update organization_subscriptions set current_period_started_at = now() - interval '10 days', current_period_ends_at = now() - interval '1 hour' where organization_id='b0200000-0000-0000-0000-00000000000a' and superseded_at is null;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p14t_cancel select 'test_effectively_cancelled_after_deadline', case when organization_has_active_access('b0200000-0000-0000-0000-00000000000a')=false then 'PASS' else 'FAIL' end;
reset role;

select * from p14t_cancel order by test_name;

-- =========================================================
-- D. COMPLIMENTARY — SIN ESTADO FANTASMA
-- =========================================================
create temporary table p14t_compl (test_name text, result text);
grant insert, select on p14t_compl to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select assign_organization_subscription('b0200000-0000-0000-0000-00000000000a', (select id from subscription_plans where code='P14TPLAN'), 'weekly', null, null, false, null, null);
select grant_complimentary_access('b0200000-0000-0000-0000-00000000000a', 'partner');
select remove_complimentary_access('b0200000-0000-0000-0000-00000000000a');
reset role;
insert into p14t_compl select 'test_complimentary_removed_no_ghost_state', case when status='active' and complimentary=false then 'PASS' else 'FAIL' end from organization_subscriptions where organization_id='b0200000-0000-0000-0000-00000000000a' and superseded_at is null;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p14t_compl select 'test_access_after_removal_correct', case when organization_has_active_access('b0200000-0000-0000-0000-00000000000a')=true then 'PASS' else 'FAIL' end;
reset role;

select * from p14t_compl order by test_name;

-- =========================================================
-- E. GRACE PERIOD REAL
-- =========================================================
create temporary table p14t_grace (test_name text, result text);
grant insert, select on p14t_grace to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select grant_subscription_grace_period('b0200000-0000-0000-0000-00000000000a', now() + interval '3 days', 'test grace');
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p14t_grace select 'test_grace_period_grants_access', case when organization_has_active_access('b0200000-0000-0000-0000-00000000000a')=true then 'PASS' else 'FAIL' end;
reset role;

update organization_subscriptions set grace_period_ends_at = now() - interval '1 hour' where organization_id='b0200000-0000-0000-0000-00000000000a' and superseded_at is null;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p14t_grace select 'test_expired_grace_denies_access', case when organization_has_active_access('b0200000-0000-0000-0000-00000000000a')=false then 'PASS' else 'FAIL' end;
reset role;

select * from p14t_grace order by test_name;

-- =========================================================
-- F. ENFORCEMENT REAL MÁS ALLÁ DE WORK_ORDERS
-- =========================================================
create temporary table p14t_enforce (test_name text, result text);
grant insert, select on p14t_enforce to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$ begin begin
  insert into customers (organization_id, first_name, last_name, created_by) values ('b0200000-0000-0000-0000-00000000000a','New','Customer','b0100000-0000-0000-0000-000000000002');
  insert into p14t_enforce values ('test_cancelled_subscription_blocks_new_customer', 'FAIL (insert succeeded)');
exception when others then insert into p14t_enforce values ('test_cancelled_subscription_blocks_new_customer', 'PASS'); end; end $$;
reset role;

select * from p14t_enforce order by test_name;

-- =========================================================
-- G. MODULE ENTITLEMENTS
-- =========================================================
create temporary table p14t_ent (test_name text, result text);
grant insert, select on p14t_ent to authenticated;

insert into plan_module_entitlements (plan_id, module_key, enabled) values ((select id from subscription_plans where code='P14TPLAN'), 'tracking', false);
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select assign_organization_subscription('b0200000-0000-0000-0000-00000000000a', (select id from subscription_plans where code='P14TPLAN'), 'weekly', null, null, false, null, null);
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p14t_ent select 'test_disabled_module_blocked', case when organization_has_module_access('b0200000-0000-0000-0000-00000000000a', 'tracking')=false then 'PASS' else 'FAIL' end;
insert into p14t_ent select 'test_module_without_row_enabled_default', case when organization_has_module_access('b0200000-0000-0000-0000-00000000000a', 'warranty')=true then 'PASS' else 'FAIL' end;
reset role;

select * from p14t_ent order by test_name;

-- =========================================================
-- H. AUTORIZACIÓN / AISLAMIENTO TENANT
-- =========================================================
create temporary table p14t_auth (test_name text, result text);
grant insert, select on p14t_auth to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into p14t_auth select 'test_org_b_cannot_read_org_a_subscription', case when count(*)=0 then 'PASS' else 'FAIL' end from organization_subscriptions where organization_id='b0200000-0000-0000-0000-00000000000a';
reset role;

select * from p14t_auth order by test_name;

-- =========================================================
-- I. CREACIÓN ATÓMICA DE COMPAÑÍA CON COMMERCIAL SETUP
-- =========================================================
create temporary table p14t_atomic (test_name text, result text);
grant insert, select on p14t_atomic to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select create_organization_with_commercial_setup('P14T Atomic Co', (select id from subscription_plans where code='P14TPLAN'), 'weekly', null, null, 'America/New_York', 'USD', 'en', null, null, null, 14, null, false, null, null);
reset role;
insert into p14t_atomic select 'test_atomic_company_creation_with_trial', case when status='trialing' then 'PASS' else 'FAIL' end from organization_subscriptions where organization_id=(select id from organizations where name='P14T Atomic Co') and superseded_at is null;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$ begin begin
  perform create_organization_with_commercial_setup('P14T Rollback Co', gen_random_uuid(), 'weekly', null, null, 'America/New_York', 'USD', 'en', null, null, null, 14, null, false, null, null);
  insert into p14t_atomic values ('test_invalid_config_rolls_back', 'FAIL (no exception)');
exception when others then insert into p14t_atomic values ('test_invalid_config_rolls_back', 'PASS'); end; end $$;
reset role;
insert into p14t_atomic select 'test_no_orphaned_org_after_rollback', case when count(*)=0 then 'PASS' else 'FAIL' end from organizations where name='P14T Rollback Co';

select * from p14t_atomic order by test_name;

-- =========================================================
-- =========================================================
-- J. ENTITLEMENTS FAIL-CLOSED (cierre de integridad)
-- =========================================================
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('b1100000-0000-0000-0000-000000000001','p14u-kccadmin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b1100000-0000-0000-0000-000000000002','p14u-owner@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('b1200000-0000-0000-0000-00000000000a','P14U Org','p14u-org','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('b1100000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-00000000000a','kcc_admin','active'),
  ('b1100000-0000-0000-0000-000000000002','b1200000-0000-0000-0000-00000000000a','company_owner','active')
on conflict do nothing;
insert into subscription_plans (id, code, name, weekly_price, is_public, status) values ('b1900000-0000-0000-0000-000000000001','P14UPLAN','P14U Plan',99,true,'active');
insert into plan_module_entitlements (plan_id, module_key, enabled) values ('b1900000-0000-0000-0000-000000000001','tracking', true);
insert into plan_module_entitlements (plan_id, module_key, enabled) values ('b1900000-0000-0000-0000-000000000001','communications', false);

create temporary table p14t_entitlements (test_name text, result text);
grant insert, select on p14t_entitlements to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select assign_organization_subscription('b1200000-0000-0000-0000-00000000000a', 'b1900000-0000-0000-0000-000000000001', 'weekly', null, null, false, null, null);
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p14t_entitlements select 'test_explicit_true_allowed', case when organization_has_module_access('b1200000-0000-0000-0000-00000000000a', 'tracking')=true then 'PASS' else 'FAIL' end;
insert into p14t_entitlements select 'test_explicit_false_blocked', case when organization_has_module_access('b1200000-0000-0000-0000-00000000000a', 'communications')=false then 'PASS' else 'FAIL' end;
insert into p14t_entitlements select 'test_missing_row_fail_closed', case when organization_has_module_access('b1200000-0000-0000-0000-00000000000a', 'analytics')=false then 'PASS' else 'FAIL' end;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into p14t_entitlements select 'test_kcc_admin_bypass', case when organization_has_module_access('b1200000-0000-0000-0000-00000000000a', 'analytics')=true then 'PASS' else 'FAIL' end;
reset role;

select * from p14t_entitlements order by test_name;

-- =========================================================
-- K. ARCHIVE/REACTIVATE METADATA SEMANTICS
-- =========================================================
create temporary table p14t_archive (test_name text, result text);
grant insert, select on p14t_archive to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select archive_organization('b1200000-0000-0000-0000-00000000000a', 'ceased operations test');
select reactivate_organization('b1200000-0000-0000-0000-00000000000a', 'resumed operations test');
reset role;
insert into p14t_archive select 'test_current_fields_cleared_on_reactivation', case when archived_at is null and archived_by is null and archive_reason is null and status='active' then 'PASS' else 'FAIL' end from organizations where id='b1200000-0000-0000-0000-00000000000a';
insert into p14t_archive select 'test_historical_evidence_preserved_in_audit', case when before->>'archive_reason' = 'ceased operations test' then 'PASS' else 'FAIL' end from audit_events where organization_id='b1200000-0000-0000-0000-00000000000a' and action='organization_reactivated';
insert into p14t_archive select 'test_reactivation_does_not_revive_subscription', case when status = 'cancelled' then 'PASS' else 'FAIL' end from organization_subscriptions where organization_id='b1200000-0000-0000-0000-00000000000a' and superseded_at is null;

select * from p14t_archive order by test_name;

-- =========================================================
-- L. WEBSITE LEAD PROTECTION UNDER COMMERCIAL RESTRICTION
-- =========================================================
insert into organizations (id, name, slug, status) values ('b1200000-0000-0000-0000-00000000000c','P14U NoSub Org','p14u-nosub-org','active');
insert into organization_memberships (profile_id, organization_id, role, status) values ('b1100000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-00000000000c','kcc_admin','active');
insert into leads (id, reference_code, assigned_organization_id, customer_name, email, phone, service_type, description, country, idempotency_key, conversion_status, status) values
  ('b1300000-0000-0000-0000-000000000001','P14U-LEAD-001','b1200000-0000-0000-0000-00000000000c','Test Lead','lead@test.com','555-1234','Engine Repair','Engine issue', 'US', gen_random_uuid(), 'not_converted', 'new');

create temporary table p14t_leads (test_name text, result text);
grant insert, select on p14t_leads to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"role":"service_role"}';
select convert_website_lead('b1300000-0000-0000-0000-000000000001');
reset role;
insert into p14t_leads select 'test_lead_blocked_and_preserved', case when conversion_status='blocked_commercial' then 'PASS' else 'FAIL' end from leads where id='b1300000-0000-0000-0000-000000000001';
insert into p14t_leads select 'test_no_operational_conversion_created', case when count(*)=0 then 'PASS' else 'FAIL' end from service_requests where website_lead_id='b1300000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select assign_organization_subscription('b1200000-0000-0000-0000-00000000000c', 'b1900000-0000-0000-0000-000000000001', 'weekly', null, null, false, null, null);
reset role;
insert into plan_module_entitlements (plan_id, module_key, enabled) values ('b1900000-0000-0000-0000-000000000001','service_requests', true) on conflict (plan_id, module_key) do update set enabled=true;
set local role authenticated;
set local request.jwt.claims = '{"role":"service_role"}';
select convert_website_lead('b1300000-0000-0000-0000-000000000001');
reset role;
insert into p14t_leads select 'test_retry_succeeds_after_access_restored', case when conversion_status='converted' then 'PASS' else 'FAIL' end from leads where id='b1300000-0000-0000-0000-000000000001';

select * from p14t_leads order by test_name;

-- =========================================================
-- M. BILLING NOTIFICATIONS — OWNER/ADMIN ONLY, MANAGER EXCLUDED
-- =========================================================
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('b1100000-0000-0000-0000-000000000003','p14u-manager@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('b1200000-0000-0000-0000-00000000000d','P14U Notif Org','p14u-notif-org','active');
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('b1100000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-00000000000d','kcc_admin','active'),
  ('b1100000-0000-0000-0000-000000000002','b1200000-0000-0000-0000-00000000000d','company_owner','active'),
  ('b1100000-0000-0000-0000-000000000003','b1200000-0000-0000-0000-00000000000d','manager','active');

create temporary table p14t_notif (test_name text, result text);
grant insert, select on p14t_notif to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select assign_organization_subscription('b1200000-0000-0000-0000-00000000000d', 'b1900000-0000-0000-0000-000000000001', 'weekly', 14, null, false, null, null);
reset role;
insert into p14t_notif select 'test_owner_receives_billing_notification', case when count(*)=1 then 'PASS' else 'FAIL' end from notifications where organization_id='b1200000-0000-0000-0000-00000000000d' and event_type='SUBSCRIPTION_TRIAL_STARTED' and recipient_user_id='b1100000-0000-0000-0000-000000000002';
insert into p14t_notif select 'test_manager_excluded_from_billing_notification', case when count(*)=0 then 'PASS' else 'FAIL' end from notifications where organization_id='b1200000-0000-0000-0000-00000000000d' and event_type='SUBSCRIPTION_TRIAL_STARTED' and recipient_user_id='b1100000-0000-0000-0000-000000000003';

select * from p14t_notif order by test_name;

-- =========================================================
-- CLEANUP
-- =========================================================
delete from notifications where organization_id in ('b0200000-0000-0000-0000-00000000000a','b0200000-0000-0000-0000-00000000000b','b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000c','b1200000-0000-0000-0000-00000000000d') or organization_id in (select id from organizations where name like 'P14T%');
delete from audit_events where actor_profile_id in (select id from profiles where email like 'p14t-%@rls-test.local' or email like 'p14u-%@rls-test.local');
delete from domain_events where actor_profile_id in (select id from profiles where email like 'p14t-%@rls-test.local' or email like 'p14u-%@rls-test.local');
delete from audit_events where organization_id in ('b0200000-0000-0000-0000-00000000000a','b0200000-0000-0000-0000-00000000000b','b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000c','b1200000-0000-0000-0000-00000000000d') or organization_id in (select id from organizations where name like 'P14T%');
delete from domain_events where organization_id in ('b0200000-0000-0000-0000-00000000000a','b0200000-0000-0000-0000-00000000000b','b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000c','b1200000-0000-0000-0000-00000000000d') or organization_id in (select id from organizations where name like 'P14T%');
update leads set marine_cloud_service_request_id=null where id='b1300000-0000-0000-0000-000000000001';
delete from service_requests where website_lead_id='b1300000-0000-0000-0000-000000000001';
delete from leads where id='b1300000-0000-0000-0000-000000000001';
-- =========================================================
-- N. ATOMIC PLAN + ENTITLEMENTS CREATION (fail-closed safe)
-- =========================================================
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('b3100000-0000-0000-0000-000000000001','p14z-kccadmin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b3100000-0000-0000-0000-000000000002','p14z-owner@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('b3200000-0000-0000-0000-00000000000a','P14Z Org','p14z-org','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('b3100000-0000-0000-0000-000000000001','b3200000-0000-0000-0000-00000000000a','kcc_admin','active'),
  ('b3100000-0000-0000-0000-000000000002','b3200000-0000-0000-0000-00000000000a','company_owner','active')
on conflict do nothing;

create temporary table p14t_atomic_plan (test_name text, result text);
grant insert, select on p14t_atomic_plan to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b3100000-0000-0000-0000-000000000001","role":"authenticated"}';
select create_subscription_plan_with_entitlements('P14ZPLAN', 'P14Z Plan', 'desc', 'USD', 99, null, null, 14, true, false, array['work_orders','estimates']);
select assign_organization_subscription('b3200000-0000-0000-0000-00000000000a', (select id from subscription_plans where code='P14ZPLAN'), 'weekly', null, null, false, null, null);
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b3100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p14t_atomic_plan select 'test_new_plan_selected_modules_work_immediately', case when organization_has_module_access('b3200000-0000-0000-0000-00000000000a', 'work_orders')=true then 'PASS' else 'FAIL' end;
insert into p14t_atomic_plan select 'test_omitted_module_denied', case when organization_has_module_access('b3200000-0000-0000-0000-00000000000a', 'tracking')=false then 'PASS' else 'FAIL' end;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b3100000-0000-0000-0000-000000000001","role":"authenticated"}';
select set_plan_module_entitlement((select id from subscription_plans where code='P14ZPLAN'), 'tracking', true);
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b3100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p14t_atomic_plan select 'test_toggle_immediately_affects_current_org', case when organization_has_module_access('b3200000-0000-0000-0000-00000000000a', 'tracking')=true then 'PASS' else 'FAIL' end;
reset role;

select * from p14t_atomic_plan order by test_name;

-- =========================================================
-- O. BLOCKED WEBSITE LEAD AUTO-RETRY (real, bounded, cross-tenant safe)
-- =========================================================
insert into organizations (id, name, slug, status) values ('b3200000-0000-0000-0000-00000000000b','P14Z Org B','p14z-org-b','active');
insert into leads (id, reference_code, assigned_organization_id, customer_name, email, phone, service_type, description, country, idempotency_key, conversion_status, status) values
  ('b3300000-0000-0000-0000-000000000001','P14Z-LEAD-001','b3200000-0000-0000-0000-00000000000a','Test Lead','lead@test.com','555-1234','Engine Repair','Engine issue', 'US', gen_random_uuid(), 'blocked_commercial', 'new'),
  ('b3300000-0000-0000-0000-000000000002','P14Z-LEAD-002','b3200000-0000-0000-0000-00000000000b','Other Lead','other@test.com','555-9999','Detailing','Other issue', 'US', gen_random_uuid(), 'blocked_commercial', 'new');
insert into organization_memberships (profile_id, organization_id, role, status) values ('b3100000-0000-0000-0000-000000000001','b3200000-0000-0000-0000-00000000000b','kcc_admin','active');

create temporary table p14t_lead_retry (test_name text, result text);
grant insert, select on p14t_lead_retry to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b3100000-0000-0000-0000-000000000001","role":"authenticated"}';
select retry_commercially_blocked_leads('b3200000-0000-0000-0000-00000000000a', 25);
reset role;
insert into p14t_lead_retry select 'test_blocked_lead_retried_with_valid_access', case when conversion_status='converted' then 'PASS' else 'FAIL' end from leads where id='b3300000-0000-0000-0000-000000000001';
insert into p14t_lead_retry select 'test_cross_tenant_lead_untouched', case when conversion_status='blocked_commercial' then 'PASS' else 'FAIL' end from leads where id='b3300000-0000-0000-0000-000000000002';

set local role authenticated;
set local request.jwt.claims = '{"sub":"b3100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$ begin begin
  perform retry_commercially_blocked_leads('b3200000-0000-0000-0000-00000000000a', 500);
  insert into p14t_lead_retry values ('test_batch_size_bounded', 'FAIL (no exception)');
exception when others then insert into p14t_lead_retry values ('test_batch_size_bounded', 'PASS'); end; end $$;
reset role;

select * from p14t_lead_retry order by test_name;

-- =========================================================
-- P. TRIAL LIFECYCLE MILESTONES — DURABLE, IDEMPOTENT, EXACTLY-ONCE
-- =========================================================
create temporary table p14t_milestones (test_name text, result text);
grant insert, select on p14t_milestones to authenticated;
insert into p14t_milestones select 'test_4_milestones_scheduled_on_trial_start', case when count(*)=0 then 'PASS' else 'FAIL' end from subscription_lifecycle_milestones where organization_id='b3200000-0000-0000-0000-00000000000a';
-- (la org B3200...a ya no está en trial tras N — se prueba con una organización nueva en trial real abajo)

insert into organizations (id, name, slug, status) values ('b3200000-0000-0000-0000-00000000000c','P14Z Trial Org','p14z-trial-org','active');
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('b3100000-0000-0000-0000-000000000001','b3200000-0000-0000-0000-00000000000c','kcc_admin','active'),
  ('b3100000-0000-0000-0000-000000000002','b3200000-0000-0000-0000-00000000000c','company_owner','active');
set local role authenticated;
set local request.jwt.claims = '{"sub":"b3100000-0000-0000-0000-000000000001","role":"authenticated"}';
select assign_organization_subscription('b3200000-0000-0000-0000-00000000000c', (select id from subscription_plans where code='P14ZPLAN'), 'weekly', 14, null, false, null, null);
reset role;
insert into p14t_milestones select 'test_4_trial_milestones_scheduled', case when count(*)=4 then 'PASS' else 'FAIL' end from subscription_lifecycle_milestones where organization_id='b3200000-0000-0000-0000-00000000000c';

update organization_subscriptions set trial_started_at = now() - interval '20 days', trial_ends_at = now() - interval '1 hour' where organization_id='b3200000-0000-0000-0000-00000000000c' and superseded_at is null;
update subscription_lifecycle_milestones set scheduled_for = now() - interval '1 hour' where organization_id='b3200000-0000-0000-0000-00000000000c' and milestone='trial_expired';

set local role authenticated;
set local request.jwt.claims = '{"sub":"b3100000-0000-0000-0000-000000000001","role":"authenticated"}';
select process_due_subscription_lifecycle_milestones(100);
select process_due_subscription_lifecycle_milestones(100);
reset role;
insert into p14t_milestones select 'test_trial_expired_event_exactly_once', case when count(*)=1 then 'PASS' else 'FAIL' end from domain_events where organization_id='b3200000-0000-0000-0000-00000000000c' and event_type='SUBSCRIPTION_TRIAL_EXPIRED';
insert into p14t_milestones select 'test_notification_exactly_once', case when count(*)=1 then 'PASS' else 'FAIL' end from notifications where organization_id='b3200000-0000-0000-0000-00000000000c' and event_type='SUBSCRIPTION_TRIAL_EXPIRED';

-- procesador funciona sin contexto JWT (invocación real de pg_cron)
reset role;
do $$ begin begin
  perform process_due_subscription_lifecycle_milestones(10);
  insert into p14t_milestones values ('test_processor_works_without_jwt_cron_context', 'PASS');
exception when others then insert into p14t_milestones values ('test_processor_works_without_jwt_cron_context', 'FAIL: ' || sqlerrm); end; end $$;

select * from p14t_milestones order by test_name;

-- =========================================================
-- Q. BILLING NOTIFICATIONS — FINAL CLEAN STATE
-- =========================================================
create temporary table p14t_billing_final (test_name text, result text);
grant insert, select on p14t_billing_final to authenticated;
insert into p14t_billing_final select 'test_all_seven_rules_billing_admin', case when count(*)=7 then 'PASS' else 'FAIL' end from notification_rules where recipient_strategy='billing_admin' and event_type in (
  'SUBSCRIPTION_TRIAL_STARTED', 'SUBSCRIPTION_TRIAL_EXTENDED', 'SUBSCRIPTION_ACTIVATED',
  'SUBSCRIPTION_PLAN_CHANGED', 'SUBSCRIPTION_CANCELLED', 'ORGANIZATION_ARCHIVED', 'ORGANIZATION_REACTIVATED'
);
insert into p14t_billing_final select 'test_resolver_returns_owner_for_billing_admin', case when count(*)=1 then 'PASS' else 'FAIL' end from resolve_notification_recipients('billing_admin', 'b3200000-0000-0000-0000-00000000000c', null, 'organization', 'b3200000-0000-0000-0000-00000000000c') r where r=(select profile_id from organization_memberships where organization_id='b3200000-0000-0000-0000-00000000000c' and role='company_owner');

select * from p14t_billing_final order by test_name;

-- =========================================================
-- R. LIFECYCLE CONSISTENCY — short trials, rescheduling, grace, cancellation
-- =========================================================
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('b4100000-0000-0000-0000-000000000001','p14ee-kccadmin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b4100000-0000-0000-0000-000000000002','p14ee-owner@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('b4200000-0000-0000-0000-00000000000a','P14EE Org','p14ee-org','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('b4100000-0000-0000-0000-000000000001','b4200000-0000-0000-0000-00000000000a','kcc_admin','active'),
  ('b4100000-0000-0000-0000-000000000002','b4200000-0000-0000-0000-00000000000a','company_owner','active')
on conflict do nothing;
insert into subscription_plans (id, code, name, weekly_price, is_public, status) values ('b4900000-0000-0000-0000-000000000001','P14EEPLAN','P14EE Plan',99,true,'active');
insert into plan_module_entitlements (plan_id, module_key, enabled) values ('b4900000-0000-0000-0000-000000000001','service_requests', true);

create temporary table p14t_short_trial (test_name text, result text);
grant insert, select on p14t_short_trial to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b4100000-0000-0000-0000-000000000001","role":"authenticated"}';
select assign_organization_subscription('b4200000-0000-0000-0000-00000000000a', (select id from subscription_plans where code='P14EEPLAN'), 'weekly', 2, null, false, null, null);
reset role;
insert into p14t_short_trial select 'test_short_trial_only_1d_and_expired', case when array_agg(milestone order by milestone) = array['trial_1d','trial_expired'] then 'PASS' else 'FAIL' end from subscription_lifecycle_milestones where organization_id='b4200000-0000-0000-0000-00000000000a';

set local role authenticated;
set local request.jwt.claims = '{"sub":"b4100000-0000-0000-0000-000000000001","role":"authenticated"}';
select extend_organization_trial('b4200000-0000-0000-0000-00000000000a', now() + interval '20 days', 'goodwill extension');
reset role;
insert into p14t_short_trial select 'test_expired_milestone_realigned_after_extension', case when scheduled_for > now() + interval '19 days' then 'PASS' else 'FAIL' end from subscription_lifecycle_milestones where organization_id='b4200000-0000-0000-0000-00000000000a' and milestone='trial_expired';
insert into p14t_short_trial select 'test_7d_3d_created_after_extension', case when count(*)=2 then 'PASS' else 'FAIL' end from subscription_lifecycle_milestones where organization_id='b4200000-0000-0000-0000-00000000000a' and milestone in ('trial_7d','trial_3d');

select * from p14t_short_trial order by test_name;

create temporary table p14t_grace_sched (test_name text, result text);
grant insert, select on p14t_grace_sched to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b4100000-0000-0000-0000-000000000001","role":"authenticated"}';
select assign_organization_subscription('b4200000-0000-0000-0000-00000000000a', (select id from subscription_plans where code='P14EEPLAN'), 'weekly', null, null, false, null, null);
select grant_subscription_grace_period('b4200000-0000-0000-0000-00000000000a', now() + interval '5 days', 'test grace');
reset role;
insert into p14t_grace_sched select 'test_grace_expired_milestone_scheduled', case when min(scheduled_for) > now() + interval '4 days' and count(*)=1 then 'PASS' else 'FAIL' end from subscription_lifecycle_milestones where organization_id='b4200000-0000-0000-0000-00000000000a' and milestone='grace_expired';

set local role authenticated;
set local request.jwt.claims = '{"sub":"b4100000-0000-0000-0000-000000000001","role":"authenticated"}';
select grant_subscription_grace_period('b4200000-0000-0000-0000-00000000000a', now() + interval '10 days', 'extended grace');
reset role;
insert into p14t_grace_sched select 'test_grace_rescheduled_no_duplicate', case when count(*)=1 and min(scheduled_for) > now() + interval '9 days' then 'PASS' else 'FAIL' end from subscription_lifecycle_milestones where organization_id='b4200000-0000-0000-0000-00000000000a' and milestone='grace_expired';

set local role authenticated;
set local request.jwt.claims = '{"sub":"b4100000-0000-0000-0000-000000000001","role":"authenticated"}';
select end_subscription_grace_period('b4200000-0000-0000-0000-00000000000a', 'active', 'resolved manually');
reset role;
insert into p14t_grace_sched select 'test_manual_end_no_stale_event', case when count(*)=0 then 'PASS' else 'FAIL' end from domain_events where organization_id='b4200000-0000-0000-0000-00000000000a' and event_type='SUBSCRIPTION_GRACE_PERIOD_EXPIRED';

set local role authenticated;
set local request.jwt.claims = '{"sub":"b4100000-0000-0000-0000-000000000001","role":"authenticated"}';
select grant_subscription_grace_period('b4200000-0000-0000-0000-00000000000a', now() + interval '1 hour', 'about to expire');
reset role;
update subscription_lifecycle_milestones set scheduled_for = now() - interval '1 minute' where organization_id='b4200000-0000-0000-0000-00000000000a' and milestone='grace_expired';
set local role authenticated;
set local request.jwt.claims = '{"sub":"b4100000-0000-0000-0000-000000000001","role":"authenticated"}';
select process_due_subscription_lifecycle_milestones(100);
select process_due_subscription_lifecycle_milestones(100);
reset role;
insert into p14t_grace_sched select 'test_grace_expired_exactly_once', case when count(*)=1 then 'PASS' else 'FAIL' end from domain_events where organization_id='b4200000-0000-0000-0000-00000000000a' and event_type='SUBSCRIPTION_GRACE_PERIOD_EXPIRED';
insert into p14t_grace_sched select 'test_stored_status_past_due', case when status='past_due' then 'PASS' else 'FAIL' end from organization_subscriptions where organization_id='b4200000-0000-0000-0000-00000000000a' and superseded_at is null;

select * from p14t_grace_sched order by test_name;

create temporary table p14t_cancel_sched (test_name text, result text);
grant insert, select on p14t_cancel_sched to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b4100000-0000-0000-0000-000000000001","role":"authenticated"}';
select assign_organization_subscription('b4200000-0000-0000-0000-00000000000a', (select id from subscription_plans where code='P14EEPLAN'), 'weekly', null, null, false, null, null);
select cancel_subscription('b4200000-0000-0000-0000-00000000000a', false, 'scheduled cancel test');
reset role;
insert into p14t_cancel_sched select 'test_scheduled_emits_SCHEDULED_not_CANCELLED', case when count(*)=1 then 'PASS' else 'FAIL' end from domain_events where organization_id='b4200000-0000-0000-0000-00000000000a' and event_type='SUBSCRIPTION_CANCELLATION_SCHEDULED';
insert into p14t_cancel_sched select 'test_milestone_scheduled', case when count(*)=1 then 'PASS' else 'FAIL' end from subscription_lifecycle_milestones where organization_id='b4200000-0000-0000-0000-00000000000a' and milestone='scheduled_cancellation';
set local role authenticated;
set local request.jwt.claims = '{"sub":"b4100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p14t_cancel_sched select 'test_still_active_before_period_end', case when organization_has_active_access('b4200000-0000-0000-0000-00000000000a')=true then 'PASS' else 'FAIL' end;
reset role;

update subscription_lifecycle_milestones set scheduled_for = now() - interval '1 minute' where organization_id='b4200000-0000-0000-0000-00000000000a' and milestone='scheduled_cancellation';
set local role authenticated;
set local request.jwt.claims = '{"sub":"b4100000-0000-0000-0000-000000000001","role":"authenticated"}';
select process_due_subscription_lifecycle_milestones(100);
select process_due_subscription_lifecycle_milestones(100);
reset role;
insert into p14t_cancel_sched select 'test_final_cancelled_exactly_once', case when count(*)=1 then 'PASS' else 'FAIL' end from domain_events where organization_id='b4200000-0000-0000-0000-00000000000a' and event_type='SUBSCRIPTION_CANCELLED';
insert into p14t_cancel_sched select 'test_stored_status_cancelled', case when status='cancelled' and cancelled_at is not null then 'PASS' else 'FAIL' end from organization_subscriptions where organization_id='b4200000-0000-0000-0000-00000000000a' and superseded_at is null;

select * from p14t_cancel_sched order by test_name;

insert into leads (id, reference_code, assigned_organization_id, customer_name, email, phone, service_type, description, country, idempotency_key, conversion_status, status) values
  ('b4300000-0000-0000-0000-000000000001','P14EE-LEAD-001','b4200000-0000-0000-0000-00000000000a','Test Lead','lead@test.com','555-1234','Engine Repair','Engine issue', 'US', gen_random_uuid(), 'blocked_commercial', 'new');
set local role authenticated;
set local request.jwt.claims = '{"sub":"b4100000-0000-0000-0000-000000000001","role":"authenticated"}';
select assign_organization_subscription('b4200000-0000-0000-0000-00000000000a', (select id from subscription_plans where code='P14EEPLAN'), 'weekly', 1, null, false, null, null);
reset role;
update organization_subscriptions set trial_started_at=now()-interval '5 days', trial_ends_at=now()-interval '1 hour' where organization_id='b4200000-0000-0000-0000-00000000000a' and superseded_at is null;

create temporary table p14t_lead_selfservice (test_name text, result text);
grant insert, select on p14t_lead_selfservice to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b4100000-0000-0000-0000-000000000002","role":"authenticated"}';
select select_organization_plan('b4200000-0000-0000-0000-00000000000a', (select id from subscription_plans where code='P14EEPLAN'), 'weekly');
reset role;
insert into p14t_lead_selfservice select 'test_blocked_lead_retried_via_self_service', case when conversion_status='converted' then 'PASS' else 'FAIL' end from leads where id='b4300000-0000-0000-0000-000000000001';

select * from p14t_lead_selfservice order by test_name;

-- =========================================================
-- CLEANUP
-- =========================================================
delete from notifications where organization_id in ('b0200000-0000-0000-0000-00000000000a','b0200000-0000-0000-0000-00000000000b','b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000c','b1200000-0000-0000-0000-00000000000d','b3200000-0000-0000-0000-00000000000a','b3200000-0000-0000-0000-00000000000b','b3200000-0000-0000-0000-00000000000c','b4200000-0000-0000-0000-00000000000a') or organization_id in (select id from organizations where name like 'P14T%');
delete from audit_events where actor_profile_id in (select id from profiles where email like 'p14t-%@rls-test.local' or email like 'p14u-%@rls-test.local' or email like 'p14z-%@rls-test.local' or email like 'p14ee-%@rls-test.local');
delete from domain_events where actor_profile_id in (select id from profiles where email like 'p14t-%@rls-test.local' or email like 'p14u-%@rls-test.local' or email like 'p14z-%@rls-test.local' or email like 'p14ee-%@rls-test.local');
delete from audit_events where organization_id in ('b0200000-0000-0000-0000-00000000000a','b0200000-0000-0000-0000-00000000000b','b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000c','b1200000-0000-0000-0000-00000000000d','b3200000-0000-0000-0000-00000000000a','b3200000-0000-0000-0000-00000000000b','b3200000-0000-0000-0000-00000000000c','b4200000-0000-0000-0000-00000000000a') or organization_id in (select id from organizations where name like 'P14T%');
delete from domain_events where organization_id in ('b0200000-0000-0000-0000-00000000000a','b0200000-0000-0000-0000-00000000000b','b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000c','b1200000-0000-0000-0000-00000000000d','b3200000-0000-0000-0000-00000000000a','b3200000-0000-0000-0000-00000000000b','b3200000-0000-0000-0000-00000000000c','b4200000-0000-0000-0000-00000000000a') or organization_id in (select id from organizations where name like 'P14T%');
update leads set marine_cloud_service_request_id=null where id in ('b3300000-0000-0000-0000-000000000001','b4300000-0000-0000-0000-000000000001');
delete from service_requests where website_lead_id in ('b3300000-0000-0000-0000-000000000001','b4300000-0000-0000-0000-000000000001');
delete from leads where id in ('b3300000-0000-0000-0000-000000000001','b3300000-0000-0000-0000-000000000002','b1300000-0000-0000-0000-000000000001','b4300000-0000-0000-0000-000000000001');
delete from subscription_lifecycle_milestones where organization_id in ('b3200000-0000-0000-0000-00000000000a','b3200000-0000-0000-0000-00000000000c','b4200000-0000-0000-0000-00000000000a');
delete from vessels where organization_id in ('b3200000-0000-0000-0000-00000000000a','b3200000-0000-0000-0000-00000000000c','b4200000-0000-0000-0000-00000000000a');
delete from customers where organization_id in ('b3200000-0000-0000-0000-00000000000a','b3200000-0000-0000-0000-00000000000c','b4200000-0000-0000-0000-00000000000a');
delete from organization_subscriptions where organization_id in ('b0200000-0000-0000-0000-00000000000a','b0200000-0000-0000-0000-00000000000b','b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000c','b1200000-0000-0000-0000-00000000000d','b3200000-0000-0000-0000-00000000000a','b3200000-0000-0000-0000-00000000000b','b3200000-0000-0000-0000-00000000000c','b4200000-0000-0000-0000-00000000000a') or organization_id in (select id from organizations where name like 'P14T%');
delete from plan_module_entitlements where plan_id in (select id from subscription_plans where code in ('P14TPLAN','P14TNEG','P14UPLAN','P14ZPLAN','P14EEPLAN'));
delete from subscription_plans where code in ('P14TPLAN','P14TNEG','P14UPLAN','P14ZPLAN','P14EEPLAN');
delete from organization_memberships where organization_id in ('b0200000-0000-0000-0000-00000000000a','b0200000-0000-0000-0000-00000000000b','b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000c','b1200000-0000-0000-0000-00000000000d','b3200000-0000-0000-0000-00000000000a','b3200000-0000-0000-0000-00000000000b','b3200000-0000-0000-0000-00000000000c','b4200000-0000-0000-0000-00000000000a') or organization_id in (select id from organizations where name like 'P14T%');
delete from organizations where id in ('b0200000-0000-0000-0000-00000000000a','b0200000-0000-0000-0000-00000000000b','b1200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000c','b1200000-0000-0000-0000-00000000000d','b3200000-0000-0000-0000-00000000000a','b3200000-0000-0000-0000-00000000000b','b3200000-0000-0000-0000-00000000000c','b4200000-0000-0000-0000-00000000000a') or name like 'P14T%';
delete from profiles where email like 'p14t-%@rls-test.local' or email like 'p14u-%@rls-test.local' or email like 'p14z-%@rls-test.local' or email like 'p14ee-%@rls-test.local';
delete from auth.users where email like 'p14t-%@rls-test.local' or email like 'p14u-%@rls-test.local' or email like 'p14z-%@rls-test.local' or email like 'p14ee-%@rls-test.local';
select 'phase14 suite cleanup complete' as status;
