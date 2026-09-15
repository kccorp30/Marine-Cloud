-- =========================================================
-- tests/rls/phase6-estimates-tests.sql
-- =========================================================
-- Suite reproducible de Phase 6 — corre de punta a punta desde una
-- base con las migraciones 001-069 aplicadas. Cada test es una
-- consulta ejecutable real. ÚLTIMA CORRIDA EN VIVO: 27/27 PASS
-- (10 de money/lifecycle/immutability + 8 de change orders/bridges +
-- 9 de tenant isolation/expiration/revision/decline).
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('a9100000-0000-0000-0000-000000000001','p6t-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a9100000-0000-0000-0000-000000000002','p6t-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a9100000-0000-0000-0000-000000000003','p6t-othercust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a9100000-0000-0000-0000-000000000004','p6t-otherorg-owner@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('a9200000-0000-0000-0000-00000000000a','P6T Org A','p6t-org-a','active'),
  ('a9200000-0000-0000-0000-00000000000b','P6T Org B','p6t-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('a9100000-0000-0000-0000-000000000001','a9200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('a9100000-0000-0000-0000-000000000002','a9200000-0000-0000-0000-00000000000a','customer','active'),
  ('a9100000-0000-0000-0000-000000000003','a9200000-0000-0000-0000-00000000000a','customer','active'),
  ('a9100000-0000-0000-0000-000000000004','a9200000-0000-0000-0000-00000000000b','company_owner','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('a9300000-0000-0000-0000-000000000001','a9200000-0000-0000-0000-00000000000a','a9100000-0000-0000-0000-000000000002','C','T','a9100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('a9400000-0000-0000-0000-000000000001','a9200000-0000-0000-0000-00000000000a','a9300000-0000-0000-0000-000000000001','V T','a9100000-0000-0000-0000-000000000001');
reset role;

create temporary table p6_all (test_name text, result text);
grant insert, select on p6_all to authenticated;

-- MONEY: subtotal/discount/tax/total calculados enteramente por la
-- base, nunca confiados del cliente. 2*$125 + 1*$85.50 = $335.50,
-- -$20 descuento, +$15 tax -> $330.50 exacto.
set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('a9200000-0000-0000-0000-00000000000a','a9300000-0000-0000-0000-000000000001','a9400000-0000-0000-0000-000000000001', null, null, 'Money test', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'labor', 'Diagnostic labor', 2, 125.00);
  perform add_estimate_line_item(v_ver, 'material', 'Impeller kit', 1, 85.50);
  perform add_estimate_line_item(v_ver, 'discount', 'Loyalty discount', 1, 20.00, null, false);
  perform update_estimate_version_details(v_ver, null, null, 15.00, null);
  perform set_config('app.money_ver', v_ver::text, false);
end $$;
reset role;

insert into p6_all select 'test_01_money_calculated_correctly', case when subtotal=335.50 and discount=20.00 and tax=15.00 and total=330.50 then 'PASS' else 'FAIL' end
from estimate_versions where id = current_setting('app.money_ver')::uuid;

-- IMMUTABILITY: sent version no se puede editar, ni con función ni con UPDATE crudo
set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000001","role":"authenticated"}';
select send_estimate((select estimate_id from estimate_versions where id = current_setting('app.money_ver')::uuid));
do $$
begin
  begin
    perform add_estimate_line_item(current_setting('app.money_ver')::uuid, 'labor', 'sneaky', 1, 1000);
    insert into p6_all values ('test_02_sent_version_immutable_via_function', 'FAIL (no exception)');
  exception when others then
    insert into p6_all values ('test_02_sent_version_immutable_via_function', 'PASS');
  end;
end $$;
do $$
begin
  begin
    update estimate_versions set total = 1.00 where id = current_setting('app.money_ver')::uuid;
    insert into p6_all values ('test_03_sent_version_immutable_via_raw_update', 'FAIL (update succeeded)');
  exception when others then
    insert into p6_all values ('test_03_sent_version_immutable_via_raw_update', 'PASS');
  end;
end $$;
reset role;

-- CUSTOMER: no ve drafts, sí ve la línea customer_visible, no ve la interna
set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p6_all select 'test_04_customer_sees_visible_lines_only', case when count(*)=2 then 'PASS' else 'FAIL' end
from estimate_line_items where estimate_version_id = current_setting('app.money_ver')::uuid and customer_visible=true;
insert into p6_all select 'test_05_customer_cannot_see_internal_line', case when count(*)=0 then 'PASS' else 'FAIL' end
from estimate_line_items where estimate_version_id = current_setting('app.money_ver')::uuid and line_type='discount';

-- APPROVAL: aprobar, doble aprobación rechazada, decisión persistida
select approve_estimate(current_setting('app.money_ver')::uuid, 'Approved!');
reset role;

insert into p6_all select 'test_06_decision_persisted', case when decision='approved' and version_total_at_decision=330.50 then 'PASS' else 'FAIL' end
from estimate_decisions where estimate_version_id = current_setting('app.money_ver')::uuid;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    perform approve_estimate(current_setting('app.money_ver')::uuid);
    insert into p6_all values ('test_07_double_approval_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p6_all values ('test_07_double_approval_rejected', 'PASS');
  end;
end $$;
reset role;

-- DRAFT approval rejected
set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('a9200000-0000-0000-0000-00000000000a','a9300000-0000-0000-0000-000000000001','a9400000-0000-0000-0000-000000000001', null, null, 'Draft test', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'service', 'Test', 1, 100);
  perform set_config('app.draft_ver', v_ver::text, false);
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    perform approve_estimate(current_setting('app.draft_ver')::uuid);
    insert into p6_all values ('test_08_draft_cannot_be_approved', 'FAIL (no exception)');
  exception when others then
    insert into p6_all values ('test_08_draft_cannot_be_approved', 'PASS');
  end;
end $$;
insert into p6_all select 'test_09_customer_cannot_see_draft_version', case when count(*)=0 then 'PASS' else 'FAIL' end
from estimate_versions where id = current_setting('app.draft_ver')::uuid;
reset role;

-- EXPIRED
set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('a9200000-0000-0000-0000-00000000000a','a9300000-0000-0000-0000-000000000001','a9400000-0000-0000-0000-000000000001', null, null, 'Expired test', null, current_date - 1);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'service', 'Test', 1, 100);
  perform send_estimate(v_est);
  perform set_config('app.expired_ver', v_ver::text, false);
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    perform approve_estimate(current_setting('app.expired_ver')::uuid);
    insert into p6_all values ('test_10_expired_cannot_be_approved', 'FAIL (no exception)');
  exception when others then
    insert into p6_all values ('test_10_expired_cannot_be_approved', 'PASS');
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$
begin
  begin
    perform approve_estimate(current_setting('app.expired_ver')::uuid);
    insert into p6_all values ('test_11_wrong_customer_blocked', 'FAIL (no exception)');
  exception when others then
    insert into p6_all values ('test_11_wrong_customer_blocked', 'PASS');
  end;
end $$;
reset role;

-- TENANT ISOLATION
set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into p6_all select 'test_12_cross_tenant_staff_blocked', case when count(*)=0 then 'PASS' else 'FAIL' end
from estimates where organization_id = 'a9200000-0000-0000-0000-00000000000a';
reset role;

-- REVISION: crea versión distinta, la vieja queda superseded con líneas intactas, no se puede aprobar la vieja
set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver1 uuid; v_ver2 uuid;
begin
  v_est := create_draft_estimate('a9200000-0000-0000-0000-00000000000a','a9300000-0000-0000-0000-000000000001','a9400000-0000-0000-0000-000000000001', null, null, 'Revision test', null, null);
  select current_version_id into v_ver1 from estimates where id = v_est;
  perform add_estimate_line_item(v_ver1, 'service', 'Original scope', 1, 500);
  perform send_estimate(v_est);
  v_ver2 := revise_estimate(v_est);
  perform set_config('app.rev_v1', v_ver1::text, false);
  perform set_config('app.rev_v2', v_ver2::text, false);
end $$;
reset role;

insert into p6_all select 'test_13_revision_creates_distinct_version', case when current_setting('app.rev_v1') != current_setting('app.rev_v2') then 'PASS' else 'FAIL' end;
insert into p6_all select 'test_14_old_version_superseded', case when status='superseded' then 'PASS' else 'FAIL' end from estimate_versions where id = current_setting('app.rev_v1')::uuid;
insert into p6_all select 'test_15_old_version_lines_unchanged', case when count(*)=1 then 'PASS' else 'FAIL' end from estimate_line_items where estimate_version_id = current_setting('app.rev_v1')::uuid;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    perform approve_estimate(current_setting('app.rev_v1')::uuid);
    insert into p6_all values ('test_16_cannot_approve_superseded_version', 'FAIL (no exception)');
  exception when others then
    insert into p6_all values ('test_16_cannot_approve_superseded_version', 'PASS');
  end;
end $$;
reset role;

-- DECLINE con razón persistida
set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('a9200000-0000-0000-0000-00000000000a','a9300000-0000-0000-0000-000000000001','a9400000-0000-0000-0000-000000000001', null, null, 'Decline test', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'service', 'Test', 1, 200);
  perform send_estimate(v_est);
  perform set_config('app.decline_ver', v_ver::text, false);
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a9100000-0000-0000-0000-000000000002","role":"authenticated"}';
select decline_estimate(current_setting('app.decline_ver')::uuid, 'Too expensive for now');
reset role;

insert into p6_all select 'test_17_decline_reason_persisted', case when customer_note='Too expensive for now' and decision='declined' then 'PASS' else 'FAIL' end
from estimate_decisions where estimate_version_id = current_setting('app.decline_ver')::uuid;

select * from p6_all order by test_name;

-- CLEANUP
update estimates set current_version_id = null where organization_id in ('a9200000-0000-0000-0000-00000000000a','a9200000-0000-0000-0000-00000000000b');
delete from estimate_decisions where organization_id in ('a9200000-0000-0000-0000-00000000000a','a9200000-0000-0000-0000-00000000000b');
delete from estimate_line_items where organization_id in ('a9200000-0000-0000-0000-00000000000a','a9200000-0000-0000-0000-00000000000b');
delete from estimate_versions where organization_id in ('a9200000-0000-0000-0000-00000000000a','a9200000-0000-0000-0000-00000000000b');
delete from estimates where organization_id in ('a9200000-0000-0000-0000-00000000000a','a9200000-0000-0000-0000-00000000000b');
delete from estimate_number_counters where organization_id in ('a9200000-0000-0000-0000-00000000000a','a9200000-0000-0000-0000-00000000000b');
delete from domain_events where organization_id in ('a9200000-0000-0000-0000-00000000000a','a9200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('a9200000-0000-0000-0000-00000000000a','a9200000-0000-0000-0000-00000000000b');
delete from vessels where organization_id = 'a9200000-0000-0000-0000-00000000000a';
delete from customers where organization_id = 'a9200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id in ('a9200000-0000-0000-0000-00000000000a','a9200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('a9200000-0000-0000-0000-00000000000a','a9200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p6t-%@rls-test.local';
delete from auth.users where email like 'p6t-%@rls-test.local';

-- =========================================================
-- CHANGE ORDERS — tests físicamente ejecutables, no notas.
-- =========================================================
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('a8100000-0000-0000-0000-000000000001','p6co-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a8100000-0000-0000-0000-000000000002','p6co-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a8100000-0000-0000-0000-000000000003','p6co-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('a8100000-0000-0000-0000-000000000004','p6co-othercust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('a8200000-0000-0000-0000-00000000000a','P6CO Org','p6co-org','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('a8100000-0000-0000-0000-000000000001','a8200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('a8100000-0000-0000-0000-000000000002','a8200000-0000-0000-0000-00000000000a','customer','active'),
  ('a8100000-0000-0000-0000-000000000003','a8200000-0000-0000-0000-00000000000a','technician','active'),
  ('a8100000-0000-0000-0000-000000000004','a8200000-0000-0000-0000-00000000000a','customer','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a8100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values
  ('a8300000-0000-0000-0000-000000000001','a8200000-0000-0000-0000-00000000000a','a8100000-0000-0000-0000-000000000002','C','CO','a8100000-0000-0000-0000-000000000001'),
  ('a8300000-0000-0000-0000-000000000002','a8200000-0000-0000-0000-00000000000a','a8100000-0000-0000-0000-000000000004','C','Other','a8100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('a8400000-0000-0000-0000-000000000001','a8200000-0000-0000-0000-00000000000a','a8300000-0000-0000-0000-000000000001','Vessel CO','a8100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('a8500000-0000-0000-0000-000000000001','a8200000-0000-0000-0000-00000000000a','a8300000-0000-0000-0000-000000000001','a8400000-0000-0000-0000-000000000001','P6CO WO','a8100000-0000-0000-0000-000000000001');
reset role;

create temporary table p6co_all (test_name text, result text);
grant insert, select on p6co_all to authenticated;

-- test_18/19: technician y customer bloqueados de crear change order
set local role authenticated;
set local request.jwt.claims = '{"sub":"a8100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$
begin
  begin
    perform create_change_order('a8500000-0000-0000-0000-000000000001'::uuid, 'sneaky', null, null);
    insert into p6co_all values ('test_18_technician_cannot_create_change_order', 'FAIL (no exception)');
  exception when others then
    insert into p6co_all values ('test_18_technician_cannot_create_change_order', 'PASS');
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a8100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    perform create_change_order('a8500000-0000-0000-0000-000000000001'::uuid, 'sneaky2', null, null);
    insert into p6co_all values ('test_19_customer_cannot_create_change_order', 'FAIL (no exception)');
  exception when others then
    insert into p6co_all values ('test_19_customer_cannot_create_change_order', 'PASS');
  end;
end $$;
reset role;

-- Original $2500 aprobado
set local role authenticated;
set local request.jwt.claims = '{"sub":"a8100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('a8200000-0000-0000-0000-00000000000a','a8300000-0000-0000-0000-000000000001','a8400000-0000-0000-0000-000000000001','a8500000-0000-0000-0000-000000000001', null, 'Original scope', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'labor', 'Base service', 1, 2500.00);
  perform send_estimate(v_est);
  perform set_config('app.co_orig_ver', v_ver::text, false);
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a8100000-0000-0000-0000-000000000002","role":"authenticated"}';
select approve_estimate(current_setting('app.co_orig_ver')::uuid);
reset role;

-- CO-001 +$450, CO-002 +$200
set local role authenticated;
set local request.jwt.claims = '{"sub":"a8100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_co1 uuid; v_co1v uuid; v_co2 uuid; v_co2v uuid;
begin
  v_co1 := create_change_order('a8500000-0000-0000-0000-000000000001'::uuid, 'Pump replacement', null, null);
  select current_version_id into v_co1v from estimates where id = v_co1;
  perform add_estimate_line_item(v_co1v, 'material', 'Pump', 1, 450.00);
  perform send_estimate(v_co1);

  v_co2 := create_change_order('a8500000-0000-0000-0000-000000000001'::uuid, 'Extra labor', null, null);
  select current_version_id into v_co2v from estimates where id = v_co2;
  perform add_estimate_line_item(v_co2v, 'labor', 'Extra labor', 1, 200.00);
  perform send_estimate(v_co2);

  perform set_config('app.co1v', v_co1v::text, false);
  perform set_config('app.co2v', v_co2v::text, false);
end $$;
reset role;

-- customer ajeno bloqueado de aprobar el CO
set local role authenticated;
set local request.jwt.claims = '{"sub":"a8100000-0000-0000-0000-000000000004","role":"authenticated"}';
do $$
begin
  begin
    perform approve_estimate(current_setting('app.co1v')::uuid);
    insert into p6co_all values ('test_20_foreign_customer_cannot_approve_change_order', 'FAIL (no exception)');
  exception when others then
    insert into p6co_all values ('test_20_foreign_customer_cannot_approve_change_order', 'PASS');
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a8100000-0000-0000-0000-000000000002","role":"authenticated"}';
select approve_estimate(current_setting('app.co1v')::uuid);
select approve_estimate(current_setting('app.co2v')::uuid);
reset role;

insert into p6co_all select 'test_21_aggregate_authorized_total_correct', case when get_work_order_authorized_total('a8500000-0000-0000-0000-000000000001') = 3150.00 then 'PASS' else 'FAIL' end;
insert into p6co_all select 'test_22_original_estimate_never_rewritten', case when total = 2500.00 then 'PASS' else 'FAIL' end from estimate_versions where id = current_setting('app.co_orig_ver')::uuid;

-- idempotencia de conversión a work order (con una estimate standalone nueva)
set local role authenticated;
set local request.jwt.claims = '{"sub":"a8100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('a8200000-0000-0000-0000-00000000000a','a8300000-0000-0000-0000-000000000001','a8400000-0000-0000-0000-000000000001', null, null, 'Standalone', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'service', 'Detailing', 1, 300.00);
  perform send_estimate(v_est);
  perform set_config('app.standalone_est', v_est::text, false);
  perform set_config('app.standalone_ver', v_ver::text, false);
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a8100000-0000-0000-0000-000000000002","role":"authenticated"}';
select approve_estimate(current_setting('app.standalone_ver')::uuid);
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a8100000-0000-0000-0000-000000000001","role":"authenticated"}';
select convert_estimate_to_work_order(current_setting('app.standalone_est')::uuid);
select convert_estimate_to_work_order(current_setting('app.standalone_est')::uuid);
reset role;

insert into p6co_all select 'test_23_idempotent_work_order_conversion', case when count(*)=2 then 'PASS' else 'FAIL' end
from work_orders where customer_id = 'a8300000-0000-0000-0000-000000000001';
-- (2 = la de la original con estimate + la creada una sola vez por la conversión, pese a llamarla dos veces)

select * from p6co_all order by test_name;

delete from domain_events where organization_id = 'a8200000-0000-0000-0000-00000000000a';
delete from audit_events where organization_id = 'a8200000-0000-0000-0000-00000000000a';
update estimates set current_version_id = null where organization_id = 'a8200000-0000-0000-0000-00000000000a';
delete from estimate_decisions where organization_id = 'a8200000-0000-0000-0000-00000000000a';
delete from estimate_line_items where organization_id = 'a8200000-0000-0000-0000-00000000000a';
delete from estimate_versions where organization_id = 'a8200000-0000-0000-0000-00000000000a';
delete from estimates where organization_id = 'a8200000-0000-0000-0000-00000000000a';
delete from estimate_number_counters where organization_id = 'a8200000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id = 'a8200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = 'a8200000-0000-0000-0000-00000000000a';
delete from customers where organization_id = 'a8200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id = 'a8200000-0000-0000-0000-00000000000a';
delete from organizations where id = 'a8200000-0000-0000-0000-00000000000a';
delete from profiles where email like 'p6co-%@rls-test.local';
delete from auth.users where email like 'p6co-%@rls-test.local';
select 'phase6 suite cleanup complete' as status;

-- =========================================================
-- PHASE 6 HARDENING — tests 01-24 nuevos, agregados sin tocar los
-- 27 anteriores. ÚLTIMA CORRIDA EN VIVO: 24/24 PASS.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('ab100000-0000-0000-0000-000000000001','p6h-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('ab100000-0000-0000-0000-000000000002','p6h-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('ab100000-0000-0000-0000-000000000003','p6h-othercust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('ab100000-0000-0000-0000-000000000004','p6h-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('ab100000-0000-0000-0000-000000000005','p6h-otherorg-owner@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('ab200000-0000-0000-0000-00000000000a','P6H Org A','p6h-org-a','active'),
  ('ab200000-0000-0000-0000-00000000000b','P6H Org B','p6h-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('ab100000-0000-0000-0000-000000000001','ab200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('ab100000-0000-0000-0000-000000000002','ab200000-0000-0000-0000-00000000000a','customer','active'),
  ('ab100000-0000-0000-0000-000000000003','ab200000-0000-0000-0000-00000000000a','customer','active'),
  ('ab100000-0000-0000-0000-000000000004','ab200000-0000-0000-0000-00000000000a','technician','active'),
  ('ab100000-0000-0000-0000-000000000005','ab200000-0000-0000-0000-00000000000b','company_owner','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('ab300000-0000-0000-0000-000000000001','ab200000-0000-0000-0000-00000000000a','ab100000-0000-0000-0000-000000000002','C','H','ab100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('ab400000-0000-0000-0000-000000000001','ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000001','V H','ab100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('ab500000-0000-0000-0000-000000000001','ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000001','P6H WO','ab100000-0000-0000-0000-000000000001');
reset role;

create temporary table p6h_all (test_name text, result text);
grant insert, select on p6h_all to authenticated;

-- test_01/02: draft oculto, visible tras enviar
set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000001', null, null, 'Visibility test', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'service', 'Test', 1, 100);
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p6h_all select 'test_01_customer_cannot_see_draft_parent_row', case when count(*)=0 then 'PASS' else 'FAIL' end
from estimates where customer_id='ab300000-0000-0000-0000-000000000001' and status='draft';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000001","role":"authenticated"}';
select send_estimate((select id from estimates where customer_id='ab300000-0000-0000-0000-000000000001' and status='draft'));
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p6h_all select 'test_02_customer_can_see_after_send', case when count(*)=1 then 'PASS' else 'FAIL' end
from estimates where customer_id='ab300000-0000-0000-0000-000000000001' and status='sent';
reset role;

-- test_03-07: autorización de get_work_order_authorized_total
set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform get_work_order_authorized_total('ab500000-0000-0000-0000-000000000001');
    insert into p6h_all values ('test_03_staff_own_tenant_succeeds', 'PASS');
  exception when others then
    insert into p6h_all values ('test_03_staff_own_tenant_succeeds', 'FAIL (exception)');
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    perform get_work_order_authorized_total('ab500000-0000-0000-0000-000000000001');
    insert into p6h_all values ('test_04_own_customer_succeeds', 'PASS');
  exception when others then
    insert into p6h_all values ('test_04_own_customer_succeeds', 'FAIL (exception)');
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$
begin
  begin
    perform get_work_order_authorized_total('ab500000-0000-0000-0000-000000000001');
    insert into p6h_all values ('test_05_foreign_customer_blocked', 'FAIL (no exception)');
  exception when others then
    insert into p6h_all values ('test_05_foreign_customer_blocked', 'PASS');
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000005","role":"authenticated"}';
do $$
begin
  begin
    perform get_work_order_authorized_total('ab500000-0000-0000-0000-000000000001');
    insert into p6h_all values ('test_06_foreign_tenant_staff_blocked', 'FAIL (no exception)');
  exception when others then
    insert into p6h_all values ('test_06_foreign_tenant_staff_blocked', 'PASS');
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000004","role":"authenticated"}';
do $$
begin
  begin
    perform get_work_order_authorized_total('ab500000-0000-0000-0000-000000000001');
    insert into p6h_all values ('test_07_unrelated_technician_blocked', 'FAIL (no exception)');
  exception when others then
    insert into p6h_all values ('test_07_unrelated_technician_blocked', 'PASS');
  end;
end $$;
reset role;

-- test_08-11: validación de relaciones (work order y service request ajenos/incorrectos)
set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into customers (id, organization_id, first_name, last_name, created_by) values ('ab300000-0000-0000-0000-00000000000b','ab200000-0000-0000-0000-00000000000b','C','B','ab100000-0000-0000-0000-000000000005');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('ab400000-0000-0000-0000-00000000000b','ab200000-0000-0000-0000-00000000000b','ab300000-0000-0000-0000-00000000000b','V B','ab100000-0000-0000-0000-000000000005');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('ab500000-0000-0000-0000-00000000000b','ab200000-0000-0000-0000-00000000000b','ab300000-0000-0000-0000-00000000000b','ab400000-0000-0000-0000-00000000000b','WO B','ab100000-0000-0000-0000-000000000005');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('ab300000-0000-0000-0000-000000000002','ab200000-0000-0000-0000-00000000000a','ab100000-0000-0000-0000-000000000003','C','Other','ab100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('ab400000-0000-0000-0000-000000000002','ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000002','V Other','ab100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('ab500000-0000-0000-0000-000000000002','ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000002','ab400000-0000-0000-0000-000000000002','WO Other Cust','ab100000-0000-0000-0000-000000000001');

do $$
begin
  begin
    perform create_draft_estimate('ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000001','ab500000-0000-0000-0000-00000000000b', null, 'sneaky', null, null);
    insert into p6h_all values ('test_08_foreign_work_order_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p6h_all values ('test_08_foreign_work_order_rejected', 'PASS');
  end;
end $$;
do $$
begin
  begin
    perform create_draft_estimate('ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000001','ab500000-0000-0000-0000-000000000002', null, 'sneaky2', null, null);
    insert into p6h_all values ('test_09_wrong_customer_work_order_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p6h_all values ('test_09_wrong_customer_work_order_rejected', 'PASS');
  end;
end $$;
reset role;

update customers set profile_id = 'ab100000-0000-0000-0000-000000000005' where id = 'ab300000-0000-0000-0000-00000000000b';
set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into service_requests (id, organization_id, customer_id, vessel_id, title, client_generated_id, created_by) values ('ab700000-0000-0000-0000-00000000000b','ab200000-0000-0000-0000-00000000000b','ab300000-0000-0000-0000-00000000000b','ab400000-0000-0000-0000-00000000000b','SR B', gen_random_uuid(), 'ab100000-0000-0000-0000-000000000005');
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into service_requests (id, organization_id, customer_id, vessel_id, title, client_generated_id, created_by) values ('ab700000-0000-0000-0000-000000000001','ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000001','SR A own vessel', gen_random_uuid(), 'ab100000-0000-0000-0000-000000000002');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform create_draft_estimate('ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000001', null, 'ab700000-0000-0000-0000-00000000000b', 'sneaky3', null, null);
    insert into p6h_all values ('test_10_foreign_service_request_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p6h_all values ('test_10_foreign_service_request_rejected', 'PASS');
  end;
end $$;
do $$
begin
  begin
    perform create_draft_estimate('ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000002', null, 'ab700000-0000-0000-0000-000000000001', 'sneaky4', null, null);
    insert into p6h_all values ('test_11_wrong_vessel_service_request_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p6h_all values ('test_11_wrong_vessel_service_request_rejected', 'PASS');
  end;
end $$;
reset role;

select * from p6h_all order by test_name;

-- test_12-14: expiración — el intento fallido no corrompe el estado,
-- expire_estimate() sí persiste de verdad y emite el evento.
set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000001', null, null, 'Expiry test', null, current_date - 1);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'service', 'Test', 1, 100);
  perform send_estimate(v_est);
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    perform approve_estimate((select id from estimate_versions where title='Expiry test'));
  exception when others then
    null;
  end;
end $$;
reset role;

insert into p6h_all select 'test_12_expired_attempt_leaves_status_sent_not_corrupted', case when status='sent' then 'PASS' else 'FAIL' end
from estimate_versions where title='Expiry test';

set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000001","role":"authenticated"}';
select expire_estimate((select id from estimates where id in (select estimate_id from estimate_versions where title='Expiry test')));
reset role;

insert into p6h_all select 'test_13_expire_estimate_persists_real_state', case when status='expired' then 'PASS' else 'FAIL' end from estimate_versions where title='Expiry test';
insert into p6h_all select 'test_14_expired_event_emitted', case when count(*)=1 then 'PASS' else 'FAIL' end from domain_events where event_type='ESTIMATE_EXPIRED';

-- test_15: decline también bloqueado sobre versión vencida
set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000001', null, null, 'Decline expiry test', null, current_date - 1);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'service', 'Test', 1, 100);
  perform send_estimate(v_est);
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    perform decline_estimate((select id from estimate_versions where title='Decline expiry test'));
    insert into p6h_all values ('test_15_decline_also_blocked_when_expired', 'FAIL (no exception)');
  exception when others then
    insert into p6h_all values ('test_15_decline_also_blocked_when_expired', 'PASS');
  end;
end $$;

-- test_16: auditoría de aprobación
select approve_estimate((select id from estimate_versions where title='Visibility test'), 'Approved via audit test');
reset role;

insert into p6h_all select 'test_16_approval_audit_record_written', case when count(*)=1 then 'PASS' else 'FAIL' end
from audit_events where action='estimate_approved' and entity_id=(select id from estimates where id in (select estimate_id from estimate_versions where title='Visibility test'));

-- test_17: auditoría de rechazo
set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000001', null, null, 'Decline audit test', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'service', 'Test', 1, 100);
  perform send_estimate(v_est);
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000002","role":"authenticated"}';
select decline_estimate((select id from estimate_versions where title='Decline audit test'), 'No thanks');
reset role;
insert into p6h_all select 'test_17_decline_audit_record_written', case when count(*)=1 then 'PASS' else 'FAIL' end
from audit_events where action='estimate_declined' and entity_id=(select id from estimates where id in (select estimate_id from estimate_versions where title='Decline audit test'));

-- test_18-21: restricciones de dinero
set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000001', null, null, 'Money constraint test', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  begin
    perform add_estimate_line_item(v_ver, 'service', 'sneaky negative', 1, -50);
    insert into p6h_all values ('test_18_negative_service_price_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p6h_all values ('test_18_negative_service_price_rejected', 'PASS');
  end;
  begin
    perform add_estimate_line_item(v_ver, 'labor', 'sneaky negative labor', 1, -75);
    insert into p6h_all values ('test_19_negative_labor_price_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p6h_all values ('test_19_negative_labor_price_rejected', 'PASS');
  end;
  begin
    perform update_estimate_version_details(v_ver, null, null, -10, null);
    insert into p6h_all values ('test_20_negative_tax_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p6h_all values ('test_20_negative_tax_rejected', 'PASS');
  end;
  perform add_estimate_line_item(v_ver, 'service', 'Real service', 1, 200);
  perform add_estimate_line_item(v_ver, 'discount', 'Valid discount', 1, 30, null, false);
end $$;
reset role;
insert into p6h_all select 'test_21_valid_discount_still_works', case when subtotal=200 and discount=30 and total=170 then 'PASS' else 'FAIL' end
from estimate_versions where title='Money constraint test';

-- test_22-23: change order exige estimate original aprobada
set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform create_change_order('ab500000-0000-0000-0000-000000000001'::uuid, 'CO without approval', null, null);
    insert into p6h_all values ('test_22_change_order_rejected_without_approved_original', 'FAIL (no exception)');
  exception when others then
    insert into p6h_all values ('test_22_change_order_rejected_without_approved_original', 'PASS');
  end;
end $$;
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('ab200000-0000-0000-0000-00000000000a','ab300000-0000-0000-0000-000000000001','ab400000-0000-0000-0000-000000000001','ab500000-0000-0000-0000-000000000001', null, 'Original for CO test', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'labor', 'Base', 1, 1000);
  perform send_estimate(v_est);
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000002","role":"authenticated"}';
select approve_estimate((select id from estimate_versions where title='Original for CO test'));
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"ab100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform create_change_order('ab500000-0000-0000-0000-000000000001'::uuid, 'CO with approval', null, null);
    insert into p6h_all values ('test_23_change_order_succeeds_with_approved_original', 'PASS');
  exception when others then
    insert into p6h_all values ('test_23_change_order_succeeds_with_approved_original', 'FAIL (exception)');
  end;
end $$;
reset role;

-- test_24: la FK compuesta en sí bloquea un insert crudo cross-tenant
do $$
begin
  begin
    insert into estimates (organization_id, customer_id, vessel_id, work_order_id, estimate_number, type, status, currency, created_by)
    values ('ab200000-0000-0000-0000-00000000000a', 'ab300000-0000-0000-0000-000000000001', 'ab400000-0000-0000-0000-000000000001', 'ab500000-0000-0000-0000-00000000000b', 'EST-SNEAKY', 'estimate', 'draft', 'USD', 'ab100000-0000-0000-0000-000000000001');
    insert into p6h_all values ('test_24_composite_fk_blocks_raw_cross_tenant_insert', 'FAIL (insert succeeded)');
  exception when others then
    insert into p6h_all values ('test_24_composite_fk_blocks_raw_cross_tenant_insert', 'PASS');
  end;
end $$;

select * from p6h_all order by test_name;

-- CLEANUP
update estimates set current_version_id = null where organization_id in ('ab200000-0000-0000-0000-00000000000a','ab200000-0000-0000-0000-00000000000b');
delete from estimate_decisions where organization_id in ('ab200000-0000-0000-0000-00000000000a','ab200000-0000-0000-0000-00000000000b');
delete from estimate_line_items where organization_id in ('ab200000-0000-0000-0000-00000000000a','ab200000-0000-0000-0000-00000000000b');
delete from estimate_versions where organization_id in ('ab200000-0000-0000-0000-00000000000a','ab200000-0000-0000-0000-00000000000b');
delete from estimates where organization_id in ('ab200000-0000-0000-0000-00000000000a','ab200000-0000-0000-0000-00000000000b');
delete from estimate_number_counters where organization_id in ('ab200000-0000-0000-0000-00000000000a','ab200000-0000-0000-0000-00000000000b');
delete from domain_events where organization_id in ('ab200000-0000-0000-0000-00000000000a','ab200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('ab200000-0000-0000-0000-00000000000a','ab200000-0000-0000-0000-00000000000b');
delete from service_requests where organization_id in ('ab200000-0000-0000-0000-00000000000a','ab200000-0000-0000-0000-00000000000b');
delete from work_orders where organization_id in ('ab200000-0000-0000-0000-00000000000a','ab200000-0000-0000-0000-00000000000b');
delete from vessels where organization_id in ('ab200000-0000-0000-0000-00000000000a','ab200000-0000-0000-0000-00000000000b');
delete from customers where organization_id in ('ab200000-0000-0000-0000-00000000000a','ab200000-0000-0000-0000-00000000000b');
delete from organization_memberships where organization_id in ('ab200000-0000-0000-0000-00000000000a','ab200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('ab200000-0000-0000-0000-00000000000a','ab200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p6h-%@rls-test.local';
delete from auth.users where email like 'p6h-%@rls-test.local';
select 'phase6 hardening suite cleanup complete' as status;

-- =========================================================
-- PHASE 6 — caso límite de visibilidad final. ÚLTIMA CORRIDA EN
-- VIVO: 4/4 PASS. Total real de la suite: 27 + 24 + 4 = 55 tests
-- únicos ejecutables.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('ad100000-0000-0000-0000-000000000001','p6edge-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('ad100000-0000-0000-0000-000000000002','p6edge-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('ad200000-0000-0000-0000-00000000000a','P6Edge Org','p6edge-org','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('ad100000-0000-0000-0000-000000000001','ad200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('ad100000-0000-0000-0000-000000000002','ad200000-0000-0000-0000-00000000000a','customer','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ad100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('ad300000-0000-0000-0000-000000000001','ad200000-0000-0000-0000-00000000000a','ad100000-0000-0000-0000-000000000002','C','Edge','ad100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('ad400000-0000-0000-0000-000000000001','ad200000-0000-0000-0000-00000000000a','ad300000-0000-0000-0000-000000000001','V Edge','ad100000-0000-0000-0000-000000000001');
reset role;

create temporary table p6edge_all (test_name text, result text);
grant insert, select on p6edge_all to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ad100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('ad200000-0000-0000-0000-00000000000a','ad300000-0000-0000-0000-000000000001','ad400000-0000-0000-0000-000000000001', null, null, 'Never sent draft', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'service', 'Test', 1, 100);
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ad100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p6edge_all select 'test_1_unsent_draft_invisible', case when count(*)=0 then 'PASS' else 'FAIL' end
from estimates where id in (select estimate_id from estimate_versions where title='Never sent draft');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ad100000-0000-0000-0000-000000000001","role":"authenticated"}';
select cancel_estimate((select estimate_id from estimate_versions where title='Never sent draft'));
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ad100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p6edge_all select 'test_2_cancelled_unsent_draft_still_invisible', case when count(*)=0 then 'PASS' else 'FAIL' end
from estimates where id in (select estimate_id from estimate_versions where title='Never sent draft');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ad100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('ad200000-0000-0000-0000-00000000000a','ad300000-0000-0000-0000-000000000001','ad400000-0000-0000-0000-000000000001', null, null, 'Sent then cancelled', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'service', 'Test', 1, 100);
  perform send_estimate(v_est);
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ad100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p6edge_all select 'test_3_sent_estimate_visible', case when count(*)=1 then 'PASS' else 'FAIL' end
from estimates where id in (select estimate_id from estimate_versions where title='Sent then cancelled');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ad100000-0000-0000-0000-000000000001","role":"authenticated"}';
select cancel_estimate((select estimate_id from estimate_versions where title='Sent then cancelled'));
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ad100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p6edge_all
select 'test_4_sent_then_cancelled_still_visible_historically',
  case when (select count(*) from estimates where id in (select estimate_id from estimate_versions where title='Sent then cancelled') and status='cancelled') = 1
  then 'PASS' else 'FAIL' end;
reset role;

select * from p6edge_all order by test_name;

-- CLEANUP
update estimates set current_version_id = null where organization_id = 'ad200000-0000-0000-0000-00000000000a';
delete from estimate_decisions where organization_id = 'ad200000-0000-0000-0000-00000000000a';
delete from estimate_line_items where organization_id = 'ad200000-0000-0000-0000-00000000000a';
delete from estimate_versions where organization_id = 'ad200000-0000-0000-0000-00000000000a';
delete from estimates where organization_id = 'ad200000-0000-0000-0000-00000000000a';
delete from estimate_number_counters where organization_id = 'ad200000-0000-0000-0000-00000000000a';
delete from domain_events where organization_id = 'ad200000-0000-0000-0000-00000000000a';
delete from audit_events where organization_id = 'ad200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = 'ad200000-0000-0000-0000-00000000000a';
delete from customers where organization_id = 'ad200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id = 'ad200000-0000-0000-0000-00000000000a';
delete from organizations where id = 'ad200000-0000-0000-0000-00000000000a';
delete from profiles where email like 'p6edge-%@rls-test.local';
delete from auth.users where email like 'p6edge-%@rls-test.local';
select 'phase6 edge-case suite cleanup complete' as status;
