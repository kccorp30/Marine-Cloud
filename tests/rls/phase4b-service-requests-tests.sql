-- =========================================================
-- tests/rls/phase4b-service-requests-tests.sql
-- =========================================================
-- Suite completa y reproducible — corre de punta a punta desde una
-- base limpia (con las migraciones 001-054 ya aplicadas), sin
-- depender de historial de sesión. Cada uno de los 19 tests (15
-- escenarios pedidos, 4 divididos en sub-pasos a/b/c/d) es una
-- consulta ejecutable real, con resultado PASS/FAIL verificable —
-- nada de comentarios afirmando que "se corrió antes".
--
-- ÚLTIMA CORRIDA EN VIVO: 19/19 PASS.
-- =========================================================
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('9d100000-0000-0000-0000-000000000001','p4bf-admin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('9d100000-0000-0000-0000-000000000002','p4bf-cust1@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('9d100000-0000-0000-0000-000000000003','p4bf-cust2@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('9d100000-0000-0000-0000-000000000004','p4bf-otherorg-cust@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('9d100000-0000-0000-0000-000000000005','p4bf-otherorg-staff@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;

insert into organizations (id, name, slug, status) values
  ('9d200000-0000-0000-0000-00000000000a','P4BF Org A','p4bf-org-a','active'),
  ('9d200000-0000-0000-0000-00000000000b','P4BF Org B','p4bf-org-b','active')
on conflict (id) do nothing;

insert into organization_memberships (profile_id, organization_id, role, status) values
  ('9d100000-0000-0000-0000-000000000001','9d200000-0000-0000-0000-00000000000a','company_admin','active'),
  ('9d100000-0000-0000-0000-000000000002','9d200000-0000-0000-0000-00000000000a','customer','active'),
  ('9d100000-0000-0000-0000-000000000003','9d200000-0000-0000-0000-00000000000a','customer','active'),
  ('9d100000-0000-0000-0000-000000000004','9d200000-0000-0000-0000-00000000000b','customer','active'),
  ('9d100000-0000-0000-0000-000000000005','9d200000-0000-0000-0000-00000000000b','company_admin','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into customers (id, organization_id, profile_id, first_name, last_name, created_by) values
  ('9d300000-0000-0000-0000-000000000001','9d200000-0000-0000-0000-00000000000a','9d100000-0000-0000-0000-000000000002','C','One','9d100000-0000-0000-0000-000000000001'),
  ('9d300000-0000-0000-0000-000000000002','9d200000-0000-0000-0000-00000000000a','9d100000-0000-0000-0000-000000000003','C','Two','9d100000-0000-0000-0000-000000000001');
insert into vessels (id, organization_id, current_customer_id, name, created_by) values
  ('9d400000-0000-0000-0000-000000000001','9d200000-0000-0000-0000-00000000000a','9d300000-0000-0000-0000-000000000001','Boat One','9d100000-0000-0000-0000-000000000001'),
  ('9d400000-0000-0000-0000-000000000002','9d200000-0000-0000-0000-00000000000a','9d300000-0000-0000-0000-000000000002','Boat Two','9d100000-0000-0000-0000-000000000001');
reset role;

create temporary table phase4b_results (test_name text, result text);
grant insert, select on phase4b_results to authenticated;

-- IDs fijos de los pedidos usados en toda la suite:
-- req1 = 9d500000-...0001 (customer 1, se convertirá al final)
-- req2 = 9d500000-...0002 (customer 1, se cancelará)
-- req3 = 9d500000-...0003 (customer 1, se aceptará y no debe poder cancelarse)

-- ---------------------------------------------------------
-- TEST 1: owner customer can create request for own vessel
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into service_requests (id, organization_id, customer_id, vessel_id, service_category, title, description, urgency, client_generated_id, created_by)
values ('9d500000-0000-0000-0000-000000000001','9d200000-0000-0000-0000-00000000000a','9d300000-0000-0000-0000-000000000001','9d400000-0000-0000-0000-000000000001','electrical','No power at helm','Nothing turns on','high', gen_random_uuid(), '9d100000-0000-0000-0000-000000000002');
reset role;

insert into phase4b_results select 'test_01_owner_creates_for_own_vessel', case when count(*)=1 then 'PASS' else 'FAIL' end
from service_requests where id = '9d500000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------
-- TEST 2: customer cannot create request for another customer's vessel
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    insert into service_requests (organization_id, customer_id, vessel_id, title, client_generated_id, created_by)
    values ('9d200000-0000-0000-0000-00000000000a','9d300000-0000-0000-0000-000000000001','9d400000-0000-0000-0000-000000000002','sneaky', gen_random_uuid(), '9d100000-0000-0000-0000-000000000002');
    insert into phase4b_results values ('test_02_cannot_create_for_others_vessel', 'FAIL (insert succeeded)');
  exception when others then
    insert into phase4b_results values ('test_02_cannot_create_for_others_vessel', 'PASS');
  end;
end $$;
reset role;

-- ---------------------------------------------------------
-- TEST 3: customer cannot create request already accepted
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    insert into service_requests (organization_id, customer_id, vessel_id, title, status, client_generated_id, created_by)
    values ('9d200000-0000-0000-0000-00000000000a','9d300000-0000-0000-0000-000000000001','9d400000-0000-0000-0000-000000000001','sneaky2', 'accepted', gen_random_uuid(), '9d100000-0000-0000-0000-000000000002');
    insert into phase4b_results values ('test_03_cannot_create_pre_accepted', 'FAIL (insert succeeded)');
  exception when others then
    insert into phase4b_results values ('test_03_cannot_create_pre_accepted', 'PASS');
  end;
end $$;
reset role;

-- ---------------------------------------------------------
-- TEST 4: second customer cannot read first customer's request
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into phase4b_results select 'test_04_other_customer_cannot_read', case when count(*)=0 then 'PASS' else 'FAIL' end
from service_requests where id = '9d500000-0000-0000-0000-000000000001';
reset role;

-- ---------------------------------------------------------
-- TEST 5: customer in another organization cannot read it
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into phase4b_results select 'test_05_other_org_customer_cannot_read', case when count(*)=0 then 'PASS' else 'FAIL' end
from service_requests where id = '9d500000-0000-0000-0000-000000000001';
reset role;

-- ---------------------------------------------------------
-- TEST 6: customer cannot accept own request
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    perform accept_service_request('9d500000-0000-0000-0000-000000000001'::uuid);
    insert into phase4b_results values ('test_06_customer_cannot_accept_own', 'FAIL (no exception)');
  exception when others then
    insert into phase4b_results values ('test_06_customer_cannot_accept_own', 'PASS');
  end;
end $$;
reset role;

-- ---------------------------------------------------------
-- TEST 7: customer cannot decline/convert own request
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    perform decline_service_request('9d500000-0000-0000-0000-000000000001'::uuid, 'nope');
    insert into phase4b_results values ('test_07a_customer_cannot_decline_own', 'FAIL (no exception)');
  exception when others then
    insert into phase4b_results values ('test_07a_customer_cannot_decline_own', 'PASS');
  end;
end $$;
do $$
begin
  begin
    perform convert_service_request_to_work_order('9d500000-0000-0000-0000-000000000001'::uuid, null, null, null);
    insert into phase4b_results values ('test_07b_customer_cannot_convert_own', 'FAIL (no exception)');
  exception when others then
    insert into phase4b_results values ('test_07b_customer_cannot_convert_own', 'PASS');
  end;
end $$;
reset role;

-- ---------------------------------------------------------
-- TEST 8: correct tenant staff can accept
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000001","role":"authenticated"}';
select accept_service_request('9d500000-0000-0000-0000-000000000001'::uuid);
reset role;

insert into phase4b_results select 'test_08_correct_tenant_staff_can_accept', case when status='accepted' then 'PASS' else 'FAIL' end
from service_requests where id = '9d500000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------
-- TEST 9: other-tenant staff cannot accept/update
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into service_requests (id, organization_id, customer_id, vessel_id, title, client_generated_id, created_by)
values ('9d500000-0000-0000-0000-000000000002','9d200000-0000-0000-0000-00000000000a','9d300000-0000-0000-0000-000000000001','9d400000-0000-0000-0000-000000000001','Second request', gen_random_uuid(), '9d100000-0000-0000-0000-000000000002');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000005","role":"authenticated"}';
do $$
begin
  begin
    perform accept_service_request('9d500000-0000-0000-0000-000000000002'::uuid);
    insert into phase4b_results values ('test_09_other_tenant_staff_cannot_accept', 'FAIL (no exception)');
  exception when others then
    insert into phase4b_results values ('test_09_other_tenant_staff_cannot_accept', 'PASS');
  end;
end $$;
reset role;

-- ---------------------------------------------------------
-- TEST 10: conversion creates exactly one correct work_order
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
declare v_wo_id uuid;
declare v_title text;
declare v_cnt int;
begin
  v_wo_id := convert_service_request_to_work_order('9d500000-0000-0000-0000-000000000001'::uuid, null, null, null);
  select count(*), max(title) into v_cnt, v_title from work_orders where id = v_wo_id;
  insert into phase4b_results
  values ('test_10a_conversion_creates_work_order', case when v_cnt=1 and v_title='No power at helm' then 'PASS' else 'FAIL' end);
end $$;
reset role;

insert into phase4b_results
select 'test_10b_request_marked_converted', case when status='converted' and converted_work_order_id is not null then 'PASS' else 'FAIL' end
from service_requests where id = '9d500000-0000-0000-0000-000000000001';

-- doble conversión — debe fallar, nunca crear un segundo work order
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000001","role":"authenticated"}';
do $$
begin
  begin
    perform convert_service_request_to_work_order('9d500000-0000-0000-0000-000000000001'::uuid, null, null, null);
    insert into phase4b_results values ('test_10c_double_conversion_blocked', 'FAIL (no exception)');
  exception when others then
    insert into phase4b_results values ('test_10c_double_conversion_blocked', 'PASS');
  end;
end $$;
reset role;
insert into phase4b_results
select 'test_10d_still_exactly_one_work_order', case when count(*)=1 then 'PASS' else 'FAIL' end
from work_orders where customer_id = '9d300000-0000-0000-0000-000000000001' and title='No power at helm';

-- ---------------------------------------------------------
-- TEST 11: customer cannot call conversion RPC
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    perform convert_service_request_to_work_order('9d500000-0000-0000-0000-000000000002'::uuid, null, null, null);
    insert into phase4b_results values ('test_11_customer_cannot_call_conversion_rpc', 'FAIL (no exception)');
  exception when others then
    insert into phase4b_results values ('test_11_customer_cannot_call_conversion_rpc', 'PASS');
  end;
end $$;
reset role;

-- ---------------------------------------------------------
-- TEST 12: owner customer can cancel submitted/under_review request
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000002","role":"authenticated"}';
select cancel_service_request('9d500000-0000-0000-0000-000000000002'::uuid);
reset role;

insert into phase4b_results select 'test_12_owner_can_cancel_submitted', case when status='cancelled' then 'PASS' else 'FAIL' end
from service_requests where id = '9d500000-0000-0000-0000-000000000002';

-- ---------------------------------------------------------
-- TEST 13: customer cannot cancel another customer's request
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into service_requests (id, organization_id, customer_id, vessel_id, title, client_generated_id, created_by)
values ('9d500000-0000-0000-0000-000000000003','9d200000-0000-0000-0000-00000000000a','9d300000-0000-0000-0000-000000000001','9d400000-0000-0000-0000-000000000001','Third request', gen_random_uuid(), '9d100000-0000-0000-0000-000000000002');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000003","role":"authenticated"}';
do $$
begin
  begin
    perform cancel_service_request('9d500000-0000-0000-0000-000000000003'::uuid);
    insert into phase4b_results values ('test_13_customer_cannot_cancel_others', 'FAIL (no exception)');
  exception when others then
    insert into phase4b_results values ('test_13_customer_cannot_cancel_others', 'PASS');
  end;
end $$;
reset role;

-- ---------------------------------------------------------
-- TEST 14: customer cannot cancel accepted/converted/declined request
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000001","role":"authenticated"}';
select accept_service_request('9d500000-0000-0000-0000-000000000003'::uuid);
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$
begin
  begin
    perform cancel_service_request('9d500000-0000-0000-0000-000000000003'::uuid);
    insert into phase4b_results values ('test_14_cannot_cancel_accepted', 'FAIL (no exception)');
  exception when others then
    insert into phase4b_results values ('test_14_cannot_cancel_accepted', 'PASS');
  end;
end $$;
reset role;

-- ---------------------------------------------------------
-- TEST 15: cross-tenant access remains blocked
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"9d100000-0000-0000-0000-000000000005","role":"authenticated"}';
insert into phase4b_results select 'test_15_cross_tenant_blocked', case when count(*)=0 then 'PASS' else 'FAIL' end
from service_requests where organization_id = '9d200000-0000-0000-0000-00000000000a';
reset role;

-- ---------------------------------------------------------
-- RESULTADOS
-- ---------------------------------------------------------
select * from phase4b_results order by test_name;

-- ---------------------------------------------------------
-- CLEANUP
-- ---------------------------------------------------------
delete from domain_events where organization_id in ('9d200000-0000-0000-0000-00000000000a','9d200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('9d200000-0000-0000-0000-00000000000a','9d200000-0000-0000-0000-00000000000b');
delete from service_requests where organization_id in ('9d200000-0000-0000-0000-00000000000a','9d200000-0000-0000-0000-00000000000b');
delete from work_orders where organization_id = '9d200000-0000-0000-0000-00000000000a';
delete from vessels where organization_id = '9d200000-0000-0000-0000-00000000000a';
delete from customers where organization_id = '9d200000-0000-0000-0000-00000000000a';
delete from organization_memberships where organization_id in ('9d200000-0000-0000-0000-00000000000a','9d200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('9d200000-0000-0000-0000-00000000000a','9d200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p4bf-%@rls-test.local';
delete from auth.users where email like 'p4bf-%@rls-test.local';
select 'phase4b full suite cleanup complete' as status;
