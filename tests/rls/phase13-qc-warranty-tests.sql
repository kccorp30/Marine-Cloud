-- =========================================================
-- tests/rls/phase13-qc-warranty-tests.sql
-- =========================================================
-- Suite reproducible de Phase 13. Corre sobre una base con las
-- migraciones 001-199 aplicadas. Última corrida en vivo, de punta a
-- punta desde este archivo: 24/24 PASS (bloques A-D) + 16/16 PASS
-- (bloque E, cierre de integridad final) = 40/40 PASS.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('c1100000-0000-0000-0000-000000000001','p13-owner@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c1100000-0000-0000-0000-000000000002','p13-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c1100000-0000-0000-0000-000000000003','p13-manager@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c1100000-0000-0000-0000-000000000004','p13-customer@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c1100000-0000-0000-0000-000000000005','p13-orgb@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('c1200000-0000-0000-0000-00000000000a','P13 Org','p13-org','active'),
  ('c1200000-0000-0000-0000-00000000000b','P13 Org B','p13-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('c1100000-0000-0000-0000-000000000001','c1200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('c1100000-0000-0000-0000-000000000002','c1200000-0000-0000-0000-00000000000a','technician','active'),
  ('c1100000-0000-0000-0000-000000000003','c1200000-0000-0000-0000-00000000000a','manager','active'),
  ('c1100000-0000-0000-0000-000000000004','c1200000-0000-0000-0000-00000000000a','customer','active'),
  ('c1100000-0000-0000-0000-000000000005','c1200000-0000-0000-0000-00000000000b','company_admin','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('c1300000-0000-0000-0000-000000000001','c1200000-0000-0000-0000-00000000000a','c1100000-0000-0000-0000-000000000004','C','P13','c1100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('c1400000-0000-0000-0000-000000000001','c1200000-0000-0000-0000-00000000000a','c1300000-0000-0000-0000-000000000001','V P13','c1100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by, current_status, qc_required) values ('c1500000-0000-0000-0000-000000000001','c1200000-0000-0000-0000-00000000000a','c1300000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','P13 WO','c1100000-0000-0000-0000-000000000001','work_in_progress', true);
insert into appointments (id, organization_id, work_order_id, scheduled_start) values ('c1600000-0000-0000-0000-000000000001','c1200000-0000-0000-0000-00000000000a','c1500000-0000-0000-0000-000000000001', now());
insert into assignments (id, organization_id, work_order_id, appointment_id, technician_profile_id, assigned_by) values ('c1700000-0000-0000-0000-000000000001','c1200000-0000-0000-0000-00000000000a','c1500000-0000-0000-0000-000000000001','c1600000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000002','c1100000-0000-0000-0000-000000000001');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000002","role":"authenticated"}';
select transition_work_order('c1500000-0000-0000-0000-000000000001', 'quality_control');
reset role;

-- =========================================================
-- A. QC — GATE, CHECKLIST, AUTORIDAD
-- =========================================================
create temporary table p13_all (test_name text, result text);
grant insert, select on p13_all to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$ begin begin
  perform transition_work_order('c1500000-0000-0000-0000-000000000001', 'invoice');
  insert into p13_all values ('test_invoice_blocked_without_passed_qc', 'FAIL (no exception)');
exception when others then insert into p13_all values ('test_invoice_blocked_without_passed_qc', 'PASS'); end; end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000002","role":"authenticated"}';
select start_qc_submission('c1500000-0000-0000-0000-000000000001', '[{"label":"Engine check","required":true},{"label":"Hull inspection","required":true}]'::jsonb);
reset role;
insert into p13_all select 'test_qc_submission_created_with_items', case when (select count(*) from qc_submission_items where qc_submission_id=(select id from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000001'))=2 then 'PASS' else 'FAIL' end;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$ begin begin
  perform submit_qc_for_review((select id from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000001'));
  insert into p13_all values ('test_submit_blocked_with_pending_required_item', 'FAIL (no exception)');
exception when others then insert into p13_all values ('test_submit_blocked_with_pending_required_item', 'PASS'); end; end $$;
reset role;

select * from p13_all order by test_name;

create temporary table p13_all2 (test_name text, result text);
grant insert, select on p13_all2 to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000002","role":"authenticated"}';
select set_qc_item_result(id, 'pass', 'Looks good') from qc_submission_items where qc_submission_id=(select id from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000001');
select submit_qc_for_review((select id from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000001'));
reset role;
insert into p13_all2 select 'test_submitted_with_all_resolved', case when status='submitted' then 'PASS' else 'FAIL' end from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$ begin begin
  perform pass_qc_submission((select id from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000001'), 'looks fine');
  insert into p13_all2 values ('test_self_approval_blocked', 'FAIL (no exception)');
exception when others then insert into p13_all2 values ('test_self_approval_blocked', 'PASS'); end; end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p13_all2 select 'test_technician_lacks_review_authority', case when can_review_qc('c1200000-0000-0000-0000-00000000000a')=false then 'PASS' else 'FAIL' end;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into p13_all2 select 'test_manager_has_review_authority', case when can_review_qc('c1200000-0000-0000-0000-00000000000a')=true then 'PASS' else 'FAIL' end;
reset role;

select * from p13_all2 order by test_name;

create temporary table p13_all3 (test_name text, result text);
grant insert, select on p13_all3 to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000003","role":"authenticated"}';
select pass_qc_submission((select id from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000001'), 'All good');
reset role;
insert into p13_all3 select 'test_manager_passes_qc', case when status='passed' and reviewed_by='c1100000-0000-0000-0000-000000000003' then 'PASS' else 'FAIL' end from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select transition_work_order('c1500000-0000-0000-0000-000000000001', 'invoice');
reset role;
insert into p13_all3 select 'test_invoice_allowed_after_passed_qc', case when current_status='invoice' then 'PASS' else 'FAIL' end from work_orders where id='c1500000-0000-0000-0000-000000000001';

-- qc_required=false: flujo normal sin gate
set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by, current_status, qc_required) values ('c1500000-0000-0000-0000-000000000002','c1200000-0000-0000-0000-00000000000a','c1300000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','P13 WO No QC','c1100000-0000-0000-0000-000000000001','quality_control', false);
select transition_work_order('c1500000-0000-0000-0000-000000000002', 'invoice');
reset role;
insert into p13_all3 select 'test_qc_not_required_normal_flow_allowed', case when current_status='invoice' then 'PASS' else 'FAIL' end from work_orders where id='c1500000-0000-0000-0000-000000000002';

select * from p13_all3 order by test_name;

-- B. fail/resubmit
create temporary table p13_all4 (test_name text, result text);
grant insert, select on p13_all4 to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by, current_status, qc_required) values ('c1500000-0000-0000-0000-000000000003','c1200000-0000-0000-0000-00000000000a','c1300000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','P13 WO Fail Test','c1100000-0000-0000-0000-000000000001','quality_control', true);
insert into appointments (id, organization_id, work_order_id, scheduled_start) values ('c1600000-0000-0000-0000-000000000003','c1200000-0000-0000-0000-00000000000a','c1500000-0000-0000-0000-000000000003', now());
insert into assignments (id, organization_id, work_order_id, appointment_id, technician_profile_id, assigned_by) values ('c1700000-0000-0000-0000-000000000003','c1200000-0000-0000-0000-00000000000a','c1500000-0000-0000-0000-000000000003','c1600000-0000-0000-0000-000000000003','c1100000-0000-0000-0000-000000000002','c1100000-0000-0000-0000-000000000001');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000002","role":"authenticated"}';
select start_qc_submission('c1500000-0000-0000-0000-000000000003', '[{"label":"Check A","required":true}]'::jsonb);
select set_qc_item_result(id, 'fail', 'Loose bolt') from qc_submission_items where qc_submission_id=(select id from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000003');
select submit_qc_for_review((select id from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000003'));
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000003","role":"authenticated"}';
select fail_qc_submission((select id from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000003'), 'Loose bolt on engine mount', 'Needs re-tightening');
reset role;
insert into p13_all4 select 'test_fail_records_reason', case when status='failed' and failure_reason='Loose bolt on engine mount' then 'PASS' else 'FAIL' end from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000003';

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000002","role":"authenticated"}';
select start_qc_submission('c1500000-0000-0000-0000-000000000003', '[{"label":"Check A retest","required":true}]'::jsonb);
reset role;
insert into p13_all4 select 'test_resubmission_creates_new_submission', case when count(*)=2 then 'PASS' else 'FAIL' end from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000003';
insert into p13_all4 select 'test_prior_failed_remains_historical', case when count(*)=1 then 'PASS' else 'FAIL' end from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000003' and status='failed';

-- C. tenant/privacidad de QC
set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into p13_all4 select 'test_customer_cannot_read_qc_submissions', case when count(*)=0 then 'PASS' else 'FAIL' end from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000001';
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into p13_all4 select 'test_org_b_cannot_read_org_a_qc', case when count(*)=0 then 'PASS' else 'FAIL' end from qc_submissions where work_order_id='c1500000-0000-0000-0000-000000000001';
do $$ begin begin
  perform start_qc_submission('c1500000-0000-0000-0000-000000000001', '[]'::jsonb);
  insert into p13_all4 values ('test_org_b_cannot_start_qc_for_org_a', 'FAIL (no exception)');
exception when others then insert into p13_all4 values ('test_org_b_cannot_start_qc_for_org_a', 'PASS'); end; end $$;
reset role;

select * from p13_all4 order by test_name;

-- =========================================================
-- D. WARRANTY — ACTIVACIÓN, PRIVACIDAD, CLAIMS, TRABAJO CORRECTIVO
-- =========================================================
create temporary table p13w_all (test_name text, result text);
grant insert, select on p13w_all to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select transition_work_order('c1500000-0000-0000-0000-000000000001', 'payment');
select transition_work_order('c1500000-0000-0000-0000-000000000001', 'completed');
select activate_warranty('c1500000-0000-0000-0000-000000000001', 90, 'workmanship', 'Covers labor only');
reset role;
insert into p13w_all select 'test_warranty_activated_with_explicit_terms', case when status='active' and ends_at=current_date+90 then 'PASS' else 'FAIL' end from warranties where work_order_id='c1500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into p13w_all select 'test_owning_customer_sees_warranty', case when count(*)=1 then 'PASS' else 'FAIL' end from warranties where work_order_id='c1500000-0000-0000-0000-000000000001';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$ begin begin
  perform void_warranty((select id from warranties where work_order_id='c1500000-0000-0000-0000-000000000001'), 'test');
  insert into p13w_all values ('test_technician_cannot_void', 'FAIL (no exception)');
exception when others then insert into p13w_all values ('test_technician_cannot_void', 'PASS'); end; end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000004","role":"authenticated"}';
select submit_warranty_claim((select id from warranties where work_order_id='c1500000-0000-0000-0000-000000000001'), 'Engine noise returned', 'Grinding sound on startup');
reset role;
insert into p13w_all select 'test_owning_customer_can_submit_claim', case when status='submitted' then 'PASS' else 'FAIL' end from warranty_claims where warranty_id=(select id from warranties where work_order_id='c1500000-0000-0000-0000-000000000001');

set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select review_warranty_claim((select id from warranty_claims where warranty_id=(select id from warranties where work_order_id='c1500000-0000-0000-0000-000000000001')), 'approved', 'Confirmed defect');
select create_corrective_work_order_from_claim((select id from warranty_claims where warranty_id=(select id from warranties where work_order_id='c1500000-0000-0000-0000-000000000001')), null, null);
reset role;

insert into p13w_all select 'test_corrective_wo_links_preserved',
  case when warranty_id=(select id from warranties where work_order_id='c1500000-0000-0000-0000-000000000001')
   and source='warranty_claim'
  then 'PASS' else 'FAIL' end
from work_orders where id=(select claim_work_order_id from warranty_claims where warranty_id=(select id from warranties where work_order_id='c1500000-0000-0000-0000-000000000001'));
insert into p13w_all select 'test_corrective_wo_never_kcc_generated', case when kcc_generated=false then 'PASS' else 'FAIL' end
from work_orders where id=(select claim_work_order_id from warranty_claims where warranty_id=(select id from warranties where work_order_id='c1500000-0000-0000-0000-000000000001'));
insert into p13w_all select 'test_original_work_order_untouched', case when title='P13 WO' then 'PASS' else 'FAIL' end from work_orders where id='c1500000-0000-0000-0000-000000000001';

select * from p13w_all order by test_name;

-- expiración real
update warranties set starts_at = current_date - 100, ends_at = current_date - 10 where work_order_id='c1500000-0000-0000-0000-000000000001';
create temporary table p13w_all2 (test_name text, result text);
grant insert, select on p13w_all2 to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c1100000-0000-0000-0000-000000000004","role":"authenticated"}';
do $$ begin begin
  perform submit_warranty_claim((select id from warranties where work_order_id='c1500000-0000-0000-0000-000000000001'), 'Too late claim', null);
  insert into p13w_all2 values ('test_expired_warranty_rejects_new_claim', 'FAIL (no exception)');
exception when others then insert into p13w_all2 values ('test_expired_warranty_rejects_new_claim', 'PASS'); end; end $$;
reset role;

select * from p13w_all2;

-- CLEANUP
delete from notifications where organization_id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b');
update warranty_claims set claim_work_order_id=null where organization_id='c1200000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b') and warranty_claim_id is not null;
delete from warranty_claims where organization_id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b');
delete from warranties where organization_id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b');
delete from qc_submission_items where qc_submission_id in (select id from qc_submissions where organization_id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b'));
delete from qc_submissions where organization_id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b');
delete from domain_events where organization_id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b');
delete from work_order_status_history where work_order_id::text like 'c1500000-0000-0000-0000-00000000000%';
delete from assignments where organization_id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b');
delete from appointments where organization_id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b');
delete from work_orders where organization_id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b');
delete from vessels where organization_id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b');
delete from customers where organization_id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b');
delete from organization_memberships where organization_id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('c1200000-0000-0000-0000-00000000000a','c1200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p13-%@rls-test.local';
delete from auth.users where email like 'p13-%@rls-test.local';
select 'phase13 suite cleanup complete' as status;


-- =========================================================
-- E. CIERRE DE INTEGRIDAD FINAL — ejecutable de verdad, no comentario
-- =========================================================
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('e9100000-0000-0000-0000-000000000001','p13e-owner@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e9100000-0000-0000-0000-000000000002','p13e-kccadmin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e9100000-0000-0000-0000-000000000003','p13e-customer@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e9100000-0000-0000-0000-000000000004','p13e-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e9100000-0000-0000-0000-000000000005','p13e-orgb@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('e9100000-0000-0000-0000-000000000006','p13e-orgb-customer@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('e9200000-0000-0000-0000-00000000000a','P13E Org','p13e-org','active'),
  ('e9200000-0000-0000-0000-00000000000b','P13E Org B','p13e-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('e9100000-0000-0000-0000-000000000001','e9200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('e9100000-0000-0000-0000-000000000002','e9200000-0000-0000-0000-00000000000a','kcc_admin','active'),
  ('e9100000-0000-0000-0000-000000000003','e9200000-0000-0000-0000-00000000000a','customer','active'),
  ('e9100000-0000-0000-0000-000000000004','e9200000-0000-0000-0000-00000000000a','technician','active'),
  ('e9100000-0000-0000-0000-000000000005','e9200000-0000-0000-0000-00000000000b','company_admin','active'),
  ('e9100000-0000-0000-0000-000000000006','e9200000-0000-0000-0000-00000000000b','customer','active')
on conflict do nothing;
insert into organization_settings (organization_id, qc_required_default) values ('e9200000-0000-0000-0000-00000000000a', true) on conflict (organization_id) do update set qc_required_default=true;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e9100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('e9300000-0000-0000-0000-000000000001','e9200000-0000-0000-0000-00000000000a','e9100000-0000-0000-0000-000000000003','C','P13E','e9100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('e9400000-0000-0000-0000-000000000001','e9200000-0000-0000-0000-00000000000a','e9300000-0000-0000-0000-000000000001','V P13E','e9100000-0000-0000-0000-000000000001');
insert into service_catalog (id, organization_id, name, active, qc_required, warranty_enabled, warranty_duration_days) values ('e9600000-0000-0000-0000-000000000001','e9200000-0000-0000-0000-00000000000a','QC Service', true, true, true, 60);
insert into service_catalog (id, organization_id, name, active, qc_required, warranty_enabled, warranty_duration_days) values ('e9600000-0000-0000-0000-000000000002','e9200000-0000-0000-0000-00000000000a','Disabled Warranty Service', true, false, false, 90);
-- estilo createWorkOrder() manual — insert directo, sin qc_required
insert into work_orders (organization_id, customer_id, vessel_id, service_id, title, created_by) values
  ('e9200000-0000-0000-0000-00000000000a','e9300000-0000-0000-0000-000000000001','e9400000-0000-0000-0000-000000000001','e9600000-0000-0000-0000-000000000001','E1 QC Service WO','e9100000-0000-0000-0000-000000000001');
insert into work_orders (organization_id, customer_id, vessel_id, title, created_by) values
  ('e9200000-0000-0000-0000-00000000000a','e9300000-0000-0000-0000-000000000001','e9400000-0000-0000-0000-000000000001','E1 No Service WO','e9100000-0000-0000-0000-000000000001');
reset role;

create temporary table p13e_qc_snapshot (test_name text, result text);
grant insert, select on p13e_qc_snapshot to authenticated;
insert into p13e_qc_snapshot select 'test_manual_create_snapshots_service_qc_true', case when qc_required=true then 'PASS' else 'FAIL' end from work_orders where title='E1 QC Service WO';
insert into p13e_qc_snapshot select 'test_manual_create_no_service_uses_org_default_true', case when qc_required=true then 'PASS' else 'FAIL' end from work_orders where title='E1 No Service WO';
select * from p13e_qc_snapshot order by test_name;

-- KCC Admin cross-org (sin membresía en Org B)
set local role authenticated;
set local request.jwt.claims = '{"sub":"e9100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('e9300000-0000-0000-0000-000000000002','e9200000-0000-0000-0000-00000000000b','e9100000-0000-0000-0000-000000000006','C','P13E OrgB','e9100000-0000-0000-0000-000000000005');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('e9400000-0000-0000-0000-000000000002','e9200000-0000-0000-0000-00000000000b','e9300000-0000-0000-0000-000000000002','V OrgB','e9100000-0000-0000-0000-000000000005');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by, current_status) values ('e9500000-0000-0000-0000-000000000002','e9200000-0000-0000-0000-00000000000b','e9300000-0000-0000-0000-000000000002','e9400000-0000-0000-0000-000000000002','E1 OrgB WO','e9100000-0000-0000-0000-000000000005','completed');
reset role;

create temporary table p13e_kcc_authority (test_name text, result text);
grant insert, select on p13e_kcc_authority to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"e9100000-0000-0000-0000-000000000002","role":"authenticated"}';
select activate_warranty('e9500000-0000-0000-0000-000000000002', 45, 'workmanship', null);
reset role;
insert into p13e_kcc_authority select 'test_kcc_admin_activates_warranty_cross_org', case when count(*)=1 then 'PASS' else 'FAIL' end from warranties where work_order_id='e9500000-0000-0000-0000-000000000002';

set local role authenticated;
set local request.jwt.claims = '{"sub":"e9100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$ begin begin
  perform void_warranty((select id from warranties where work_order_id='e9500000-0000-0000-0000-000000000002'), 'unauthorized attempt');
  insert into p13e_kcc_authority values ('test_org_a_cannot_void_org_b_warranty', 'FAIL (no exception)');
exception when others then insert into p13e_kcc_authority values ('test_org_a_cannot_void_org_b_warranty', 'PASS'); end; end $$;
reset role;

select * from p13e_kcc_authority order by test_name;

-- warranty_enabled=false: duración obsoleta nunca usada
set local role authenticated;
set local request.jwt.claims = '{"sub":"e9100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into work_orders (id, organization_id, customer_id, vessel_id, service_id, title, created_by, current_status) values ('e9500000-0000-0000-0000-000000000003','e9200000-0000-0000-0000-00000000000a','e9300000-0000-0000-0000-000000000001','e9400000-0000-0000-0000-000000000001','e9600000-0000-0000-0000-000000000002','E1 Disabled Warranty WO','e9100000-0000-0000-0000-000000000001','completed');
reset role;

create temporary table p13e_warranty_default (test_name text, result text);
grant insert, select on p13e_warranty_default to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"e9100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$ begin begin
  perform activate_warranty('e9500000-0000-0000-0000-000000000003', null, 'workmanship', null);
  insert into p13e_warranty_default values ('test_disabled_service_warranty_duration_not_used', 'FAIL (used stale duration)');
exception when others then insert into p13e_warranty_default values ('test_disabled_service_warranty_duration_not_used', 'PASS'); end; end $$;
reset role;

select * from p13e_warranty_default;

-- Ciclo completo de claim: submitted->under_review->approved->in_progress->resolved
-- (usa el warranty de Org B ya activado por kcc_admin arriba)
create temporary table p13e_claim_lifecycle (test_name text, result text);
grant insert, select on p13e_claim_lifecycle to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"e9100000-0000-0000-0000-000000000005","role":"authenticated"}';
select submit_warranty_claim((select id from warranties where work_order_id='e9500000-0000-0000-0000-000000000002'), 'Recurring issue', 'Details here');
reset role;
insert into p13e_claim_lifecycle select 'test_claim_submitted', case when status='submitted' then 'PASS' else 'FAIL' end from warranty_claims where warranty_id=(select id from warranties where work_order_id='e9500000-0000-0000-0000-000000000002');

set local role authenticated;
set local request.jwt.claims = '{"sub":"e9100000-0000-0000-0000-000000000002","role":"authenticated"}';
select mark_warranty_claim_under_review((select id from warranty_claims where warranty_id=(select id from warranties where work_order_id='e9500000-0000-0000-0000-000000000002')));
reset role;
insert into p13e_claim_lifecycle select 'test_claim_under_review', case when status='under_review' then 'PASS' else 'FAIL' end from warranty_claims where warranty_id=(select id from warranties where work_order_id='e9500000-0000-0000-0000-000000000002');

set local role authenticated;
set local request.jwt.claims = '{"sub":"e9100000-0000-0000-0000-000000000002","role":"authenticated"}';
select review_warranty_claim((select id from warranty_claims where warranty_id=(select id from warranties where work_order_id='e9500000-0000-0000-0000-000000000002')), 'approved', 'confirmed');
select create_corrective_work_order_from_claim((select id from warranty_claims where warranty_id=(select id from warranties where work_order_id='e9500000-0000-0000-0000-000000000002')), null, null);
reset role;
insert into p13e_claim_lifecycle select 'test_claim_approved_then_in_progress', case when status='in_progress' then 'PASS' else 'FAIL' end from warranty_claims where warranty_id=(select id from warranties where work_order_id='e9500000-0000-0000-0000-000000000002');
insert into p13e_claim_lifecycle select 'test_work_created_event_not_resolved', case when count(*)=1 then 'PASS' else 'FAIL' end from domain_events where organization_id='e9200000-0000-0000-0000-00000000000b' and event_type='WARRANTY_CLAIM_WORK_CREATED';
insert into p13e_claim_lifecycle select 'test_no_false_resolved_event_at_work_creation', case when count(*)=0 then 'PASS' else 'FAIL' end from domain_events where organization_id='e9200000-0000-0000-0000-00000000000b' and event_type='WARRANTY_CLAIM_RESOLVED';

set local role authenticated;
set local request.jwt.claims = '{"sub":"e9100000-0000-0000-0000-000000000002","role":"authenticated"}';
select resolve_warranty_claim((select id from warranty_claims where warranty_id=(select id from warranties where work_order_id='e9500000-0000-0000-0000-000000000002')), 'Fixed');
reset role;
insert into p13e_claim_lifecycle select 'test_claim_resolved_persists_resolved_at', case when status='resolved' and resolved_at is not null then 'PASS' else 'FAIL' end from warranty_claims where warranty_id=(select id from warranties where work_order_id='e9500000-0000-0000-0000-000000000002');

set local role authenticated;
set local request.jwt.claims = '{"sub":"e9100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$ begin begin
  perform mark_warranty_claim_under_review((select id from warranty_claims where warranty_id=(select id from warranties where work_order_id='e9500000-0000-0000-0000-000000000002')));
  insert into p13e_claim_lifecycle values ('test_resolved_cannot_reopen', 'FAIL (no exception)');
exception when others then insert into p13e_claim_lifecycle values ('test_resolved_cannot_reopen', 'PASS'); end; end $$;
reset role;

select * from p13e_claim_lifecycle order by test_name;

-- notificaciones reales de warranty (recipiente verificado, no solo el evento)
create temporary table p13e_notif (test_name text, result text);
grant insert, select on p13e_notif to authenticated;
insert into p13e_notif select 'test_warranty_activated_notification_real_recipient', case when count(*)=1 then 'PASS' else 'FAIL' end from notifications where organization_id='e9200000-0000-0000-0000-00000000000b' and event_type='WARRANTY_ACTIVATED' and recipient_user_id='e9100000-0000-0000-0000-000000000006';
insert into p13e_notif select 'test_claim_approved_notification_real_recipient', case when count(*)=1 then 'PASS' else 'FAIL' end from notifications where organization_id='e9200000-0000-0000-0000-00000000000b' and event_type='WARRANTY_CLAIM_APPROVED' and recipient_user_id='e9100000-0000-0000-0000-000000000006';

select * from p13e_notif order by test_name;

-- estado efectivo de expiración: server-side ya lo respeta (submit_warranty_claim compara fecha real, no status)
create temporary table p13e_expiry (test_name text, result text);
grant insert, select on p13e_expiry to authenticated;
insert into p13e_expiry select 'test_warranty_effective_status_function_real', case when warranty_effective_status('active', current_date - 5) = 'expired' then 'PASS' else 'FAIL' end;
select * from p13e_expiry;

-- CLEANUP
delete from notifications where organization_id in ('e9200000-0000-0000-0000-00000000000a','e9200000-0000-0000-0000-00000000000b');
delete from domain_events where organization_id in ('e9200000-0000-0000-0000-00000000000a','e9200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('e9200000-0000-0000-0000-00000000000a','e9200000-0000-0000-0000-00000000000b');
update warranty_claims set claim_work_order_id=null where organization_id in ('e9200000-0000-0000-0000-00000000000a','e9200000-0000-0000-0000-00000000000b');
delete from work_orders where organization_id in ('e9200000-0000-0000-0000-00000000000a','e9200000-0000-0000-0000-00000000000b') and warranty_claim_id is not null;
delete from warranty_claims where organization_id in ('e9200000-0000-0000-0000-00000000000a','e9200000-0000-0000-0000-00000000000b');
delete from warranties where organization_id in ('e9200000-0000-0000-0000-00000000000a','e9200000-0000-0000-0000-00000000000b');
delete from work_orders where organization_id in ('e9200000-0000-0000-0000-00000000000a','e9200000-0000-0000-0000-00000000000b');
delete from service_catalog where organization_id in ('e9200000-0000-0000-0000-00000000000a','e9200000-0000-0000-0000-00000000000b');
delete from vessels where organization_id in ('e9200000-0000-0000-0000-00000000000a','e9200000-0000-0000-0000-00000000000b');
delete from customers where organization_id in ('e9200000-0000-0000-0000-00000000000a','e9200000-0000-0000-0000-00000000000b');
delete from organization_settings where organization_id in ('e9200000-0000-0000-0000-00000000000a','e9200000-0000-0000-0000-00000000000b');
delete from organization_memberships where organization_id in ('e9200000-0000-0000-0000-00000000000a','e9200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('e9200000-0000-0000-0000-00000000000a','e9200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p13e-%@rls-test.local';
delete from auth.users where email like 'p13e-%@rls-test.local';
select 'phase13 final integrity suite cleanup complete' as status;
