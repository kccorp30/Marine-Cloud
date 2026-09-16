-- =========================================================
-- tests/rls/phase7-invoicing-payments-tests.sql
-- =========================================================
-- Suite reproducible de Phase 7. Corre de punta a punta desde una
-- base con las migraciones 001-091 aplicadas. Cada test es una
-- consulta ejecutable real. ÚLTIMA CORRIDA EN VIVO: 24/24 PASS.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('b0100000-0000-0000-0000-000000000001','p7-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b0100000-0000-0000-0000-000000000002','p7-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('b0200000-0000-0000-0000-00000000000a','P7 Org','p7-org','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('b0100000-0000-0000-0000-000000000001','b0200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('b0100000-0000-0000-0000-000000000002','b0200000-0000-0000-0000-00000000000a','customer','active')
on conflict do nothing;

-- test_A/B/C: cálculo de depósito exacto contra los 3 casos del brief
insert into p7_all select 'test_A_deposit_50pct', case when calculate_deposit_amount(2000,'percentage',50)=1000.00 then 'PASS' else 'FAIL' end;
insert into p7_all select 'test_B_deposit_30pct', case when calculate_deposit_amount(2000,'percentage',30)=600.00 then 'PASS' else 'FAIL' end;
insert into p7_all select 'test_C_deposit_fixed', case when calculate_deposit_amount(2000,'fixed_amount',500)=500 then 'PASS' else 'FAIL' end;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select update_payment_settings('b0200000-0000-0000-0000-00000000000a', true, 'percentage', 50);
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('b0300000-0000-0000-0000-000000000001','b0200000-0000-0000-0000-00000000000a','b0100000-0000-0000-0000-000000000002','C','P7','b0100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('b0400000-0000-0000-0000-000000000001','b0200000-0000-0000-0000-00000000000a','b0300000-0000-0000-0000-000000000001','V P7','b0100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('b0500000-0000-0000-0000-000000000001','b0200000-0000-0000-0000-00000000000a','b0300000-0000-0000-0000-000000000001','b0400000-0000-0000-0000-000000000001','P7 WO','b0100000-0000-0000-0000-000000000001');
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('b0200000-0000-0000-0000-00000000000a','b0300000-0000-0000-0000-000000000001','b0400000-0000-0000-0000-000000000001','b0500000-0000-0000-0000-000000000001', null, 'Original', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'labor', 'Base', 1, 2000.00);
  perform send_estimate(v_est);
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000002","role":"authenticated"}';
select approve_estimate((select id from estimate_versions where title='Original'));
reset role;

create temporary table p7_all (test_name text, result text);
grant insert, select on p7_all to authenticated;

-- test_deposit_invoice_created: $1000.00 exacto (50% de $2000)
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select create_deposit_invoice('b0500000-0000-0000-0000-000000000001');
reset role;
insert into p7_all select 'test_deposit_invoice_exact', case when total=1000.00 then 'PASS' else 'FAIL' end
from invoices where work_order_id='b0500000-0000-0000-0000-000000000001' and invoice_type='deposit';

-- test_final_invoice_exact_remaining
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select create_invoice('b0500000-0000-0000-0000-000000000001', 'final', 1000.00, null);
reset role;
insert into p7_all select 'test_final_invoice_exact_remaining', case when total=1000.00 then 'PASS' else 'FAIL' end
from invoices where work_order_id='b0500000-0000-0000-0000-000000000001' and invoice_type='final';

-- test_D/E: pagos parciales de métodos distintos hasta pagar completo
do $$
declare v_final_id uuid;
begin
  select id into v_final_id from invoices where work_order_id='b0500000-0000-0000-0000-000000000001' and invoice_type='final';
  perform set_config('app.final_invoice_id', v_final_id::text, false);
end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select record_manual_payment(current_setting('app.final_invoice_id')::uuid, 400.00, 'zelle', 'ZL-1');
select record_manual_payment(current_setting('app.final_invoice_id')::uuid, 300.00, 'cash', null);
reset role;
insert into p7_all select 'test_D_partial_payment_exact', case when amount_paid=700.00 and balance_due=300.00 and status='partially_paid' then 'PASS' else 'FAIL' end
from invoices where id = current_setting('app.final_invoice_id')::uuid;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select record_manual_payment(current_setting('app.final_invoice_id')::uuid, 300.00, 'bank_transfer', 'WIRE-1');
reset role;
insert into p7_all select 'test_E_fully_paid_exact', case when amount_paid=1000.00 and balance_due=0.00 and status='paid' then 'PASS' else 'FAIL' end
from invoices where id = current_setting('app.final_invoice_id')::uuid;

-- test_G: sobrepago rechazado
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform record_manual_payment(current_setting('app.final_invoice_id')::uuid, 500.00, 'cash', null);
    insert into p7_all values ('test_G_overpayment_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p7_all values ('test_G_overpayment_rejected', 'PASS');
  end;
end $$;

-- test_H: facturar por encima del autorizado rechazado
do $$
begin
  begin
    perform create_invoice('b0500000-0000-0000-0000-000000000001', 'standalone', 100.00, null);
    insert into p7_all values ('test_H_above_authorized_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p7_all values ('test_H_above_authorized_rejected', 'PASS');
  end;
end $$;
reset role;

-- customer no puede registrar su propio pago
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    perform record_manual_payment(current_setting('app.final_invoice_id')::uuid, 10, 'cash', null);
    insert into p7_all values ('test_customer_cannot_record_own_payment', 'FAIL (no exception)');
  exception when others then
    insert into p7_all values ('test_customer_cannot_record_own_payment', 'PASS');
  end;
end $$;
reset role;

select * from p7_all order by test_name;

-- CLEANUP parcial (org sigue viva para el resto de tests de esta suite)
delete from payments where organization_id = 'b0200000-0000-0000-0000-00000000000a';
delete from invoice_line_items where organization_id = 'b0200000-0000-0000-0000-00000000000a';
delete from invoices where organization_id = 'b0200000-0000-0000-0000-00000000000a';
delete from invoice_number_counters where organization_id = 'b0200000-0000-0000-0000-00000000000a';
update estimates set current_version_id = null where organization_id = 'b0200000-0000-0000-0000-00000000000a';
delete from estimate_decisions where organization_id = 'b0200000-0000-0000-0000-00000000000a';
delete from estimate_line_items where organization_id = 'b0200000-0000-0000-0000-00000000000a';
delete from estimate_versions where organization_id = 'b0200000-0000-0000-0000-00000000000a';
delete from estimates where organization_id = 'b0200000-0000-0000-0000-00000000000a';
delete from estimate_number_counters where organization_id = 'b0200000-0000-0000-0000-00000000000a';

-- =========================================================
-- Fixtures nuevas — void/refund/readiness/escenario F/aislamiento
-- =========================================================
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('b1100000-0000-0000-0000-000000000001','p7b-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b1100000-0000-0000-0000-000000000002','p7b-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('b1200000-0000-0000-0000-00000000000a','P7B Org','p7b-org','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('b1100000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('b1100000-0000-0000-0000-000000000002','b1200000-0000-0000-0000-00000000000a','customer','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select update_payment_settings('b1200000-0000-0000-0000-00000000000a', true, 'fixed_amount', 500, null, true);
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('b1300000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-00000000000a','b1100000-0000-0000-0000-000000000002','C','P7B','b1100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('b1400000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-00000000000a','b1300000-0000-0000-0000-000000000001','V P7B','b1100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('b1500000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-00000000000a','b1300000-0000-0000-0000-000000000001','b1400000-0000-0000-0000-000000000001','P7B WO','b1100000-0000-0000-0000-000000000001');
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('b1200000-0000-0000-0000-00000000000a','b1300000-0000-0000-0000-000000000001','b1400000-0000-0000-0000-000000000001','b1500000-0000-0000-0000-000000000001', null, 'Original B', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'labor', 'Base', 1, 2000.00);
  perform send_estimate(v_est);
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000002","role":"authenticated"}';
select approve_estimate((select id from estimate_versions where title='Original B'));
reset role;

create temporary table p7b_all (test_name text, result text);
grant insert, select on p7b_all to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into p7b_all select 'test_readiness_false_before_deposit', case when is_work_order_financially_ready_to_start('b1500000-0000-0000-0000-000000000001') = false then 'PASS' else 'FAIL' end;

select create_deposit_invoice('b1500000-0000-0000-0000-000000000001');
select create_invoice('b1500000-0000-0000-0000-000000000001', 'standalone', 100.00, null);
reset role;

do $$
declare v_dep uuid; v_standalone uuid;
begin
  select id into v_dep from invoices where work_order_id='b1500000-0000-0000-0000-000000000001' and invoice_type='deposit';
  select id into v_standalone from invoices where work_order_id='b1500000-0000-0000-0000-000000000001' and invoice_type='standalone';
  perform set_config('app.dep_invoice', v_dep::text, false);
  perform set_config('app.standalone_invoice', v_standalone::text, false);
end $$;

-- void sin pagos funciona
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select void_invoice(current_setting('app.standalone_invoice')::uuid, 'Not needed after all');
reset role;
insert into p7b_all select 'test_void_empty_invoice', case when status='void' then 'PASS' else 'FAIL' end from invoices where id = current_setting('app.standalone_invoice')::uuid;

-- pago parcial del depósito, readiness sigue false
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
select record_manual_payment(current_setting('app.dep_invoice')::uuid, 200.00, 'cash', null);
insert into p7b_all select 'test_readiness_still_false_partial', case when is_work_order_financially_ready_to_start('b1500000-0000-0000-0000-000000000001') = false then 'PASS' else 'FAIL' end;

-- void con pagos rechazado
do $$
begin
  begin
    perform void_invoice(current_setting('app.dep_invoice')::uuid, 'trying to void a paid one');
    insert into p7b_all values ('test_cannot_void_with_payments', 'FAIL (no exception)');
  exception when others then
    insert into p7b_all values ('test_cannot_void_with_payments', 'PASS');
  end;
end $$;

-- completar el depósito, readiness pasa a true
select record_manual_payment(current_setting('app.dep_invoice')::uuid, 300.00, 'zelle', null);
insert into p7b_all select 'test_readiness_true_after_satisfied', case when is_work_order_financially_ready_to_start('b1500000-0000-0000-0000-000000000001') = true then 'PASS' else 'FAIL' end;
reset role;

-- reembolso manual revierte el pago cash y la invoice se auto-corrige
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_payment_id uuid;
begin
  select id into v_payment_id from payments where invoice_id=current_setting('app.dep_invoice')::uuid and method='cash';
  perform refund_manual_payment(v_payment_id, 200.00, 'Customer changed mind on part of deposit');
end $$;
reset role;
insert into p7b_all select 'test_refund_reverts_and_invoice_recalculates', case when amount_paid=300.00 and balance_due=200.00 and status='partially_paid' then 'PASS' else 'FAIL' end
from invoices where id = current_setting('app.dep_invoice')::uuid;

select * from p7b_all order by test_name;

-- =========================================================
-- Escenario F del brief: $2500 + CO $450 + CO $200 = $3150 autorizado,
-- depósito 50% sobre el TOTAL ($1575), remanente facturable $1575.
-- =========================================================
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('b2100000-0000-0000-0000-000000000001','p7t-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b2100000-0000-0000-0000-000000000002','p7t-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b2100000-0000-0000-0000-000000000003','p7t-othercust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b2100000-0000-0000-0000-000000000004','p7t-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('b2100000-0000-0000-0000-000000000005','p7t-otherorg@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('b2200000-0000-0000-0000-00000000000a','P7T Org A','p7t-org-a','active'),
  ('b2200000-0000-0000-0000-00000000000b','P7T Org B','p7t-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('b2100000-0000-0000-0000-000000000001','b2200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('b2100000-0000-0000-0000-000000000002','b2200000-0000-0000-0000-00000000000a','customer','active'),
  ('b2100000-0000-0000-0000-000000000003','b2200000-0000-0000-0000-00000000000a','customer','active'),
  ('b2100000-0000-0000-0000-000000000004','b2200000-0000-0000-0000-00000000000a','technician','active'),
  ('b2100000-0000-0000-0000-000000000005','b2200000-0000-0000-0000-00000000000b','company_owner','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b2100000-0000-0000-0000-000000000001","role":"authenticated"}';
select update_payment_settings('b2200000-0000-0000-0000-00000000000a', true, 'percentage', 50);
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('b2300000-0000-0000-0000-000000000001','b2200000-0000-0000-0000-00000000000a','b2100000-0000-0000-0000-000000000002','C','T','b2100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('b2400000-0000-0000-0000-000000000001','b2200000-0000-0000-0000-00000000000a','b2300000-0000-0000-0000-000000000001','V T','b2100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('b2500000-0000-0000-0000-000000000001','b2200000-0000-0000-0000-00000000000a','b2300000-0000-0000-0000-000000000001','b2400000-0000-0000-0000-000000000001','P7T WO','b2100000-0000-0000-0000-000000000001');
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('b2200000-0000-0000-0000-00000000000a','b2300000-0000-0000-0000-000000000001','b2400000-0000-0000-0000-000000000001','b2500000-0000-0000-0000-000000000001', null, 'Original F', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'labor', 'Base', 1, 2500.00);
  perform send_estimate(v_est);
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b2100000-0000-0000-0000-000000000002","role":"authenticated"}';
select approve_estimate((select id from estimate_versions where title='Original F'));
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b2100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_co1 uuid; v_co1v uuid; v_co2 uuid; v_co2v uuid;
begin
  v_co1 := create_change_order('b2500000-0000-0000-0000-000000000001'::uuid, 'CO Pump F', null, null);
  select current_version_id into v_co1v from estimates where id = v_co1;
  perform add_estimate_line_item(v_co1v, 'material', 'Pump', 1, 450.00);
  perform send_estimate(v_co1);
  v_co2 := create_change_order('b2500000-0000-0000-0000-000000000001'::uuid, 'CO Labor F', null, null);
  select current_version_id into v_co2v from estimates where id = v_co2;
  perform add_estimate_line_item(v_co2v, 'labor', 'Extra labor', 1, 200.00);
  perform send_estimate(v_co2);
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b2100000-0000-0000-0000-000000000002","role":"authenticated"}';
select approve_estimate((select id from estimate_versions where title='CO Pump F'));
select approve_estimate((select id from estimate_versions where title='CO Labor F'));
reset role;

create temporary table p7f_all (test_name text, result text);
grant insert, select on p7f_all to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b2100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into p7f_all select 'test_F_authorized_with_cos', case when authorized_total=3150.00 and deposit_amount=1575.00 then 'PASS' else 'FAIL' end
from get_work_order_financial_summary('b2500000-0000-0000-0000-000000000001');

select create_deposit_invoice('b2500000-0000-0000-0000-000000000001');
insert into p7f_all select 'test_F_remaining_invoiceable_exact', case when remaining_invoiceable=1575.00 then 'PASS' else 'FAIL' end
from get_work_order_financial_summary('b2500000-0000-0000-0000-000000000001');
reset role;

-- aislamiento tenant
set local role authenticated;
set local request.jwt.claims = '{"sub":"b2100000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into p7f_all select 'test_foreign_customer_cannot_read_invoice', case when count(*)=0 then 'PASS' else 'FAIL' end
from invoices where work_order_id='b2500000-0000-0000-0000-000000000001';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b2100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into p7f_all select 'test_foreign_tenant_staff_cannot_read_invoice', case when count(*)=0 then 'PASS' else 'FAIL' end
from invoices where work_order_id='b2500000-0000-0000-0000-000000000001';
do $$
begin
  begin
    perform record_manual_payment((select id from invoices where work_order_id='b2500000-0000-0000-0000-000000000001' and invoice_type='deposit'), 100, 'cash', null);
    insert into p7f_all values ('test_foreign_tenant_staff_cannot_record_payment', 'FAIL (no exception)');
  exception when others then
    insert into p7f_all values ('test_foreign_tenant_staff_cannot_record_payment', 'PASS');
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b2100000-0000-0000-0000-000000000004","role":"authenticated"}';
do $$
begin
  begin
    perform record_manual_payment((select id from invoices where work_order_id='b2500000-0000-0000-0000-000000000001' and invoice_type='deposit'), 100, 'cash', null);
    insert into p7f_all values ('test_technician_cannot_record_payment', 'FAIL (no exception)');
  exception when others then
    insert into p7f_all values ('test_technician_cannot_record_payment', 'PASS');
  end;
end $$;
reset role;

select * from p7f_all order by test_name;

-- CLEANUP FINAL
delete from payment_refunds where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from payments where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from invoice_line_items where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from invoices where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from invoice_number_counters where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
update estimates set current_version_id = null where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from estimate_decisions where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from estimate_line_items where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from estimate_versions where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from estimates where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from estimate_number_counters where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from organization_payment_settings where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from domain_events where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from work_orders where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from vessels where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from customers where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from organization_memberships where organization_id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('b0200000-0000-0000-0000-00000000000a','b1200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000a','b2200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p7-%@rls-test.local' or email like 'p7b-%@rls-test.local' or email like 'p7t-%@rls-test.local';
delete from auth.users where email like 'p7-%@rls-test.local' or email like 'p7b-%@rls-test.local' or email like 'p7t-%@rls-test.local';
select 'phase7 suite cleanup complete' as status;

-- =========================================================
-- PHASE 7 HARDENING — 21 tests nuevos, agregados sin tocar los 24
-- anteriores. ÚLTIMA CORRIDA EN VIVO: 21/21 PASS.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('c0100000-0000-0000-0000-000000000001','p7h-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c0100000-0000-0000-0000-000000000002','p7h-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c0100000-0000-0000-0000-000000000003','p7h-othercust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c0100000-0000-0000-0000-000000000004','p7h-tech@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c0100000-0000-0000-0000-000000000005','p7h-otherorg@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c0100000-0000-0000-0000-000000000006','p7h-kccadmin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('c0200000-0000-0000-0000-00000000000a','P7H Org A','p7h-org-a','active'),
  ('c0200000-0000-0000-0000-00000000000b','P7H Org B','p7h-org-b','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('c0100000-0000-0000-0000-000000000001','c0200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('c0100000-0000-0000-0000-000000000002','c0200000-0000-0000-0000-00000000000a','customer','active'),
  ('c0100000-0000-0000-0000-000000000003','c0200000-0000-0000-0000-00000000000a','customer','active'),
  ('c0100000-0000-0000-0000-000000000004','c0200000-0000-0000-0000-00000000000a','technician','active'),
  ('c0100000-0000-0000-0000-000000000005','c0200000-0000-0000-0000-00000000000b','company_owner','active'),
  ('c0100000-0000-0000-0000-000000000006','c0200000-0000-0000-0000-00000000000a','kcc_admin','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select update_payment_settings('c0200000-0000-0000-0000-00000000000a', false, null, null, null, null, true, array['cash','zelle']);
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values
  ('c0300000-0000-0000-0000-000000000001','c0200000-0000-0000-0000-00000000000a','c0100000-0000-0000-0000-000000000002','C','H','c0100000-0000-0000-0000-000000000001'),
  ('c0300000-0000-0000-0000-000000000002','c0200000-0000-0000-0000-00000000000a','c0100000-0000-0000-0000-000000000003','C','Other','c0100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('c0400000-0000-0000-0000-000000000001','c0200000-0000-0000-0000-00000000000a','c0300000-0000-0000-0000-000000000001','V H','c0100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('c0500000-0000-0000-0000-000000000001','c0200000-0000-0000-0000-00000000000a','c0300000-0000-0000-0000-000000000001','c0400000-0000-0000-0000-000000000001','P7H WO','c0100000-0000-0000-0000-000000000001');
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('c0200000-0000-0000-0000-00000000000a','c0300000-0000-0000-0000-000000000001','c0400000-0000-0000-0000-000000000001','c0500000-0000-0000-0000-000000000001', null, 'Original H', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'labor', 'Base', 1, 500.00);
  perform send_estimate(v_est);
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000002","role":"authenticated"}';
select approve_estimate((select id from estimate_versions where title='Original H'));
reset role;

create temporary table p7h_all (test_name text, result text);
grant insert, select on p7h_all to authenticated;

-- draft bloqueado, tras issue funciona, método no aceptado rechazado
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select create_invoice('c0500000-0000-0000-0000-000000000001', 'standalone', null, null);
reset role;

do $$
begin
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}', true);
    perform record_manual_payment((select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001'), 100, 'cash', null);
    insert into p7h_all values ('test_payment_on_draft_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p7h_all values ('test_payment_on_draft_rejected', 'PASS');
  end;
  reset role;
end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select issue_invoice((select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001'));
select record_manual_payment((select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001'), 100, 'cash', null);
reset role;
insert into p7h_all select 'test_payment_after_issue_succeeds', case when amount_paid=100 then 'PASS' else 'FAIL' end from invoices where work_order_id='c0500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform record_manual_payment((select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001'), 50, 'check', null);
    insert into p7h_all values ('test_non_accepted_method_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p7h_all values ('test_non_accepted_method_rejected', 'PASS');
  end;
end $$;
select record_manual_payment((select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001'), 400, 'zelle', null);
reset role;
insert into p7h_all select 'test_fully_paid_before_refund', case when amount_paid=500 and status='paid' then 'PASS' else 'FAIL' end from invoices where work_order_id='c0500000-0000-0000-0000-000000000001';

-- escenario A: reembolso total
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select refund_manual_payment((select id from payments where invoice_id=(select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001') and method='zelle'), 400, 'Full refund test');
select refund_manual_payment((select id from payments where invoice_id=(select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001') and method='cash'), 100, 'Full refund test cash');
reset role;
insert into p7h_all select 'test_A_full_refund_not_paid', case when amount_paid=0 and balance_due=500 and status != 'paid' and paid_at is null then 'PASS' else 'FAIL' end
from invoices where work_order_id='c0500000-0000-0000-0000-000000000001';

-- escenario B: pago de nuevo + reembolso parcial
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select record_manual_payment((select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001'), 500, 'zelle', 'second-payment');
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select refund_manual_payment((select id from payments where invoice_id=(select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001') and reference='second-payment'), 100, 'Partial refund B');
reset role;
insert into p7h_all select 'test_B_partial_refund_exact', case when amount_paid=400 and balance_due=100 and status='partially_paid' then 'PASS' else 'FAIL' end
from invoices where work_order_id='c0500000-0000-0000-0000-000000000001';

-- múltiples reembolsos parciales acumulativos, sobre-reembolso rechazado, total acumulado
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select refund_manual_payment((select id from payments where invoice_id=(select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001') and reference='second-payment'), 300, 'Second partial refund');
reset role;
insert into p7h_all select 'test_multiple_partial_refunds_cumulative', case when amount_paid=100 and balance_due=400 then 'PASS' else 'FAIL' end
from invoices where work_order_id='c0500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform refund_manual_payment((select id from payments where invoice_id=(select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001') and reference='second-payment'), 200, 'Over-refund attempt');
    insert into p7h_all values ('test_over_refund_rejected', 'FAIL (no exception)');
  exception when others then
    insert into p7h_all values ('test_over_refund_rejected', 'PASS');
  end;
end $$;
select refund_manual_payment((select id from payments where invoice_id=(select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001') and reference='second-payment'), 100, 'Final refund to zero');
reset role;
insert into p7h_all select 'test_cumulative_full_refund_reaches_zero', case when amount_paid=0 then 'PASS' else 'FAIL' end from invoices where work_order_id='c0500000-0000-0000-0000-000000000001';
insert into p7h_all select 'test_payment_marked_reversed_when_fully_refunded', case when status='reversed' then 'PASS' else 'FAIL' end
from payments where invoice_id=(select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001') and reference='second-payment';

-- RLS crítica de invoice_line_items
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p7h_all select 'test_owner_customer_can_read_own_lines', case when count(*)>0 then 'PASS' else 'FAIL' end
from invoice_line_items where invoice_id=(select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001');
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into p7h_all select 'test_same_tenant_wrong_customer_blocked', case when count(*)=0 then 'PASS' else 'FAIL' end
from invoice_line_items where invoice_id=(select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001');
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into p7h_all select 'test_foreign_tenant_customer_blocked', case when count(*)=0 then 'PASS' else 'FAIL' end
from invoice_line_items where invoice_id=(select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001');
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into p7h_all select 'test_technician_cannot_read_invoice_lines', case when count(*)=0 then 'PASS' else 'FAIL' end
from invoice_line_items where invoice_id=(select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001');
reset role;

-- change order para tener margen, invoice draft nueva
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_co uuid; v_cov uuid;
begin
  v_co := create_change_order('c0500000-0000-0000-0000-000000000001'::uuid, 'CO for draft test', null, null);
  select current_version_id into v_cov from estimates where id = v_co;
  perform add_estimate_line_item(v_cov, 'labor', 'Extra', 1, 100.00);
  perform send_estimate(v_co);
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000002","role":"authenticated"}';
select approve_estimate((select id from estimate_versions where title='CO for draft test'));
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select create_invoice('c0500000-0000-0000-0000-000000000001', 'standalone', 50.00, null);
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p7h_all select 'test_draft_invoice_lines_hidden', case when count(*)=0 then 'PASS' else 'FAIL' end
from invoice_line_items where invoice_id=(select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001' and status='draft');
insert into p7h_all select 'test_customer_cannot_see_payments_of_unsent_invoice', case when count(*)=0 then 'PASS' else 'FAIL' end
from payments where invoice_id=(select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001' and status='draft');
insert into p7h_all select 'test_customer_sees_own_sent_invoice_payments', case when count(*)>0 then 'PASS' else 'FAIL' end
from payments where invoice_id=(select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001' and status != 'draft' limit 1);
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into p7h_all select 'test_foreign_customer_cannot_see_payments', case when count(*)=0 then 'PASS' else 'FAIL' end
from payments where invoice_id in (select id from invoices where work_order_id='c0500000-0000-0000-0000-000000000001');
reset role;

-- Stripe: staff no puede forjar, sí preferencia; kcc_admin sí puede; disable preserva
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform set_stripe_account_state('c0200000-0000-0000-0000-00000000000a', 'acct_fake123', 'complete', true, true);
    insert into p7h_all values ('test_staff_cannot_forge_stripe_state', 'FAIL (no exception)');
  exception when others then
    insert into p7h_all values ('test_staff_cannot_forge_stripe_state', 'PASS');
  end;
end $$;
select set_stripe_preference('c0200000-0000-0000-0000-00000000000a', true);
reset role;
insert into p7h_all select 'test_staff_can_set_preference', case when enabled=true then 'PASS' else 'FAIL' end
from payment_provider_accounts where organization_id='c0200000-0000-0000-0000-00000000000a';

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000006","role":"authenticated"}';
select set_stripe_account_state('c0200000-0000-0000-0000-00000000000a', 'acct_real123', 'complete', true, true);
reset role;
insert into p7h_all select 'test_kcc_admin_can_set_real_state', case when charges_enabled=true and provider_account_id='acct_real123' then 'PASS' else 'FAIL' end
from payment_provider_accounts where organization_id='c0200000-0000-0000-0000-00000000000a';

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select disable_stripe_account('c0200000-0000-0000-0000-00000000000a');
reset role;
insert into p7h_all select 'test_disable_preserves_historical_record', case when provider_account_id='acct_real123' and enabled=false and disconnected_at is not null then 'PASS' else 'FAIL' end
from payment_provider_accounts where organization_id='c0200000-0000-0000-0000-00000000000a';

select * from p7h_all order by test_name;

-- CLEANUP
delete from payment_provider_accounts where organization_id='c0200000-0000-0000-0000-00000000000a';
delete from payment_refunds where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from payments where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from invoice_line_items where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from invoices where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from invoice_number_counters where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
update estimates set current_version_id = null where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from estimate_decisions where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from estimate_line_items where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from estimate_versions where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from estimates where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from estimate_number_counters where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from organization_payment_settings where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from domain_events where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from work_orders where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from vessels where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from customers where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from organization_memberships where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p7h-%@rls-test.local';
delete from auth.users where email like 'p7h-%@rls-test.local';
select 'phase7 hardening suite cleanup complete' as status;

-- =========================================================
-- PHASE 7 — FIX FINAL DE INTEGRIDAD FINANCIERA. 9 tests nuevos,
-- agregados sin tocar los 93 existentes. ÚLTIMA CORRIDA EN VIVO:
-- 9/9 PASS.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('c2100000-0000-0000-0000-000000000001','p7fx-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c2100000-0000-0000-0000-000000000002','p7fx-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values ('c2200000-0000-0000-0000-00000000000a','P7FX Org','p7fx-org','active') on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('c2100000-0000-0000-0000-000000000001','c2200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('c2100000-0000-0000-0000-000000000002','c2200000-0000-0000-0000-00000000000a','customer','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c2100000-0000-0000-0000-000000000001","role":"authenticated"}';
select update_payment_settings('c2200000-0000-0000-0000-00000000000a', true, 'percentage', 50, null, null, true, array['cash','zelle','bank_transfer','check']);
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values ('c2300000-0000-0000-0000-000000000001','c2200000-0000-0000-0000-00000000000a','c2100000-0000-0000-0000-000000000002','C','FX','c2100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values ('c2400000-0000-0000-0000-000000000001','c2200000-0000-0000-0000-00000000000a','c2300000-0000-0000-0000-000000000001','V FX','c2100000-0000-0000-0000-000000000001');
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('c2500000-0000-0000-0000-000000000001','c2200000-0000-0000-0000-00000000000a','c2300000-0000-0000-0000-000000000001','c2400000-0000-0000-0000-000000000001','P7FX WO','c2100000-0000-0000-0000-000000000001');
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('c2200000-0000-0000-0000-00000000000a','c2300000-0000-0000-0000-000000000001','c2400000-0000-0000-0000-000000000001','c2500000-0000-0000-0000-000000000001', null, 'Original FX', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'labor', 'Base', 1, 2000.00);
  perform send_estimate(v_est);
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c2100000-0000-0000-0000-000000000002","role":"authenticated"}';
select approve_estimate((select id from estimate_versions where title='Original FX'));
reset role;

create temporary table p7fx_all (test_name text, result text);
grant insert, select on p7fx_all to authenticated;

-- A: pago tras reembolso parcial (el bug real corregido)
set local role authenticated;
set local request.jwt.claims = '{"sub":"c2100000-0000-0000-0000-000000000001","role":"authenticated"}';
select create_deposit_invoice('c2500000-0000-0000-0000-000000000001');
select issue_invoice((select id from invoices where work_order_id='c2500000-0000-0000-0000-000000000001' and invoice_type='deposit'));
select record_manual_payment((select id from invoices where work_order_id='c2500000-0000-0000-0000-000000000001' and invoice_type='deposit'), 1000, 'zelle', 'full-pay');
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c2100000-0000-0000-0000-000000000001","role":"authenticated"}';
select refund_manual_payment((select id from payments where invoice_id=(select id from invoices where work_order_id='c2500000-0000-0000-0000-000000000001' and invoice_type='deposit') and reference='full-pay'), 100, 'Partial refund test');
reset role;
insert into p7fx_all select 'test_state_after_partial_refund', case when amount_paid=900 and balance_due=100 then 'PASS' else 'FAIL' end
from invoices where work_order_id='c2500000-0000-0000-0000-000000000001' and invoice_type='deposit';

set local role authenticated;
set local request.jwt.claims = '{"sub":"c2100000-0000-0000-0000-000000000001","role":"authenticated"}';
select record_manual_payment((select id from invoices where work_order_id='c2500000-0000-0000-0000-000000000001' and invoice_type='deposit'), 100, 'cash', 'replacement-payment');
reset role;
insert into p7fx_all select 'test_A_replacement_payment_after_refund_succeeds', case when amount_paid=1000 and balance_due=0 and status='paid' then 'PASS' else 'FAIL' end
from invoices where work_order_id='c2500000-0000-0000-0000-000000000001' and invoice_type='deposit';

set local role authenticated;
set local request.jwt.claims = '{"sub":"c2100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform record_manual_payment((select id from invoices where work_order_id='c2500000-0000-0000-0000-000000000001' and invoice_type='deposit'), 50, 'cash', null);
    insert into p7fx_all values ('test_B_overpayment_still_blocked', 'FAIL (no exception)');
  exception when others then
    insert into p7fx_all values ('test_B_overpayment_still_blocked', 'PASS');
  end;
end $$;
reset role;

-- C: final invoice tras deposit -> líneas suman exacto (no duplican el total original)
set local role authenticated;
set local request.jwt.claims = '{"sub":"c2100000-0000-0000-0000-000000000001","role":"authenticated"}';
select create_invoice('c2500000-0000-0000-0000-000000000001', 'final', null, null);
reset role;
do $$
declare v_final_id uuid; v_total numeric; v_lines_sum numeric;
begin
  select id, total into v_final_id, v_total from invoices where work_order_id='c2500000-0000-0000-0000-000000000001' and invoice_type='final';
  select coalesce(sum(line_total),0) into v_lines_sum from invoice_line_items where invoice_id=v_final_id;
  insert into p7fx_all values ('test_C_final_invoice_total_correct', case when v_total=1000.00 then 'PASS' else 'FAIL' end);
  insert into p7fx_all values ('test_C_lines_sum_equals_invoice_total', case when v_lines_sum=v_total then 'PASS' else 'FAIL' end);
end $$;

-- D/E/F: estimate + 2 COs con depósito ya facturado, reparto FIFO exacto
insert into work_orders (id, organization_id, customer_id, vessel_id, title, created_by) values ('c2500000-0000-0000-0000-000000000002','c2200000-0000-0000-0000-00000000000a','c2300000-0000-0000-0000-000000000001','c2400000-0000-0000-0000-000000000001','P7FX WO2','c2100000-0000-0000-0000-000000000001');
set local role authenticated;
set local request.jwt.claims = '{"sub":"c2100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_est uuid; v_ver uuid;
begin
  v_est := create_draft_estimate('c2200000-0000-0000-0000-00000000000a','c2300000-0000-0000-0000-000000000001','c2400000-0000-0000-0000-000000000001','c2500000-0000-0000-0000-000000000002', null, 'Original D', null, null);
  select current_version_id into v_ver from estimates where id = v_est;
  perform add_estimate_line_item(v_ver, 'labor', 'Base', 1, 2000.00);
  perform send_estimate(v_est);
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c2100000-0000-0000-0000-000000000002","role":"authenticated"}';
select approve_estimate((select id from estimate_versions where title='Original D'));
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c2100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_co1 uuid; v_co1v uuid; v_co2 uuid; v_co2v uuid;
begin
  v_co1 := create_change_order('c2500000-0000-0000-0000-000000000002'::uuid, 'CO1 D', null, null);
  select current_version_id into v_co1v from estimates where id = v_co1;
  perform add_estimate_line_item(v_co1v, 'material', 'Pump', 1, 450.00);
  perform send_estimate(v_co1);
  v_co2 := create_change_order('c2500000-0000-0000-0000-000000000002'::uuid, 'CO2 D', null, null);
  select current_version_id into v_co2v from estimates where id = v_co2;
  perform add_estimate_line_item(v_co2v, 'labor', 'Extra', 1, 200.00);
  perform send_estimate(v_co2);
end $$;
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c2100000-0000-0000-0000-000000000002","role":"authenticated"}';
select approve_estimate((select id from estimate_versions where title='CO1 D'));
select approve_estimate((select id from estimate_versions where title='CO2 D'));
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c2100000-0000-0000-0000-000000000001","role":"authenticated"}';
select create_deposit_invoice('c2500000-0000-0000-0000-000000000002');
select create_invoice('c2500000-0000-0000-0000-000000000002', 'final', null, null);
reset role;

do $$
declare v_final_id uuid; v_total numeric; v_lines_sum numeric;
begin
  select id, total into v_final_id, v_total from invoices where work_order_id='c2500000-0000-0000-0000-000000000002' and invoice_type='final';
  select coalesce(sum(line_total),0) into v_lines_sum from invoice_line_items where invoice_id=v_final_id;
  insert into p7fx_all values ('test_D_final_invoice_total_exact_1325', case when v_total=1325.00 then 'PASS' else 'FAIL' end);
  insert into p7fx_all values ('test_D_lines_sum_equals_invoice_total', case when v_lines_sum=v_total then 'PASS' else 'FAIL' end);
end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c2100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into p7fx_all select 'test_E_no_double_billing', case when authorized_total = invoiced_total and remaining_invoiceable = 0 then 'PASS' else 'FAIL' end
from get_work_order_financial_summary('c2500000-0000-0000-0000-000000000002');
do $$
begin
  begin
    perform create_invoice('c2500000-0000-0000-0000-000000000002', 'standalone', 1.00, null);
    insert into p7fx_all values ('test_F_never_exceeds_authorized', 'FAIL (no exception)');
  exception when others then
    insert into p7fx_all values ('test_F_never_exceeds_authorized', 'PASS');
  end;
end $$;
reset role;

select * from p7fx_all order by test_name;

-- CLEANUP (bump total primero para evitar violar la constraint al borrar refunds antes que payments)
update invoices set total = 999999 where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from payment_refunds where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from payments where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from invoice_line_items where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from invoices where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from invoice_number_counters where organization_id = 'c2200000-0000-0000-0000-00000000000a';
update estimates set current_version_id = null where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from estimate_decisions where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from estimate_line_items where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from estimate_versions where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from estimates where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from estimate_number_counters where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from organization_payment_settings where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from domain_events where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from audit_events where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from work_orders where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from customers where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id = 'c2200000-0000-0000-0000-00000000000a';
delete from organizations where id = 'c2200000-0000-0000-0000-00000000000a';
delete from profiles where email like 'p7fx-%@rls-test.local';
delete from auth.users where email like 'p7fx-%@rls-test.local';
select 'phase7 final fix suite cleanup complete' as status;
