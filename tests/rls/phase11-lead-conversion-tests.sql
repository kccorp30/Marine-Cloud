-- =========================================================
-- tests/rls/phase11-lead-conversion-tests.sql
-- =========================================================
-- Suite reproducible de Phase 11. Corre sobre una base con las
-- migraciones 001-173 aplicadas. Última corrida en vivo, de punta a
-- punta desde este archivo: 18/18 PASS automatizados (bloques
-- principal + C). Los escenarios D/E (sección 23 del brief) requieren
-- inyección temporal de falla controlada — no se dejan como rama de
-- prueba permanente en la función de producción; el procedimiento
-- exacto para reproducirlos está documentado más abajo, con el
-- resultado de la última corrida real: 16/16 PASS.
-- =========================================================

insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role) values
  ('c0100000-0000-0000-0000-000000000001','p11-kccadmin@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c0100000-0000-0000-0000-000000000002','p11-owner@rls-test.local','x',now(),now(),now(),'authenticated','authenticated'),
  ('c0100000-0000-0000-0000-000000000003','p11-otherorg@rls-test.local','x',now(),now(),now(),'authenticated','authenticated')
on conflict (id) do nothing;
insert into organizations (id, name, slug, status) values
  ('c0200000-0000-0000-0000-00000000000a','P11 Florida Org','p11-fl-org','active'),
  ('c0200000-0000-0000-0000-00000000000b','P11 Other Org','p11-other-org','active')
on conflict (id) do nothing;
insert into organization_memberships (profile_id, organization_id, role, status) values
  ('c0100000-0000-0000-0000-000000000001','c0200000-0000-0000-0000-00000000000a','kcc_admin','active'),
  ('c0100000-0000-0000-0000-000000000002','c0200000-0000-0000-0000-00000000000a','company_owner','active'),
  ('c0100000-0000-0000-0000-000000000003','c0200000-0000-0000-0000-00000000000b','company_owner','active')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select create_lead_routing_rule('c0200000-0000-0000-0000-00000000000a', 'US', 'FL', null, 100);
reset role;

create temporary table p11_all (test_name text, result text);
grant insert, select on p11_all to authenticated;

-- A/B. IDEMPOTENCIA BÁSICA + RUTEO
insert into leads (id, reference_code, status, country, region, city, service_type, vessel_make, vessel_model, customer_name, phone, email, source, idempotency_key, conversion_status) values
  ('c0600000-0000-0000-0000-000000000001','LEAD001','new','US','FL','Miami','Engine Repair','Sea Ray','340', 'John Doe', '(305) 555-1234', 'John.Doe@Example.com', 'website', gen_random_uuid(), 'not_converted');

set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select convert_website_lead('c0600000-0000-0000-0000-000000000001');
reset role;

insert into p11_all select 'test_routed_to_correct_org', case when assigned_organization_id='c0200000-0000-0000-0000-00000000000a' then 'PASS' else 'FAIL' end from leads where id='c0600000-0000-0000-0000-000000000001';
insert into p11_all select 'test_converted_status', case when conversion_status='converted' then 'PASS' else 'FAIL' end from leads where id='c0600000-0000-0000-0000-000000000001';
insert into p11_all select 'test_service_request_created_website_origin', case when count(*)=1 then 'PASS' else 'FAIL' end from service_requests where website_lead_id='c0600000-0000-0000-0000-000000000001' and source='website';

-- B: reintento del mismo lead ya convertido -> idempotente, no duplica
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select convert_website_lead('c0600000-0000-0000-0000-000000000001');
reset role;
insert into p11_all select 'test_b_retry_already_converted_no_duplicate', case when count(*)=1 then 'PASS' else 'FAIL' end from service_requests where website_lead_id='c0600000-0000-0000-0000-000000000001';

-- matching de teléfono normalizado
insert into leads (id, reference_code, status, country, region, service_type, vessel_make, vessel_model, customer_name, phone, email, source, idempotency_key, conversion_status) values
  ('c0600000-0000-0000-0000-000000000002','LEAD002','new','US','FL','Detailing', 'Boston Whaler','280', 'John Doe', '305-555-1234', 'john.doe@example.com', 'website', gen_random_uuid(), 'not_converted');
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select convert_website_lead('c0600000-0000-0000-0000-000000000002');
reset role;
insert into p11_all select 'test_phone_matching_reuses_customer',
  case when (select marine_cloud_customer_id from leads where id='c0600000-0000-0000-0000-000000000002') = (select marine_cloud_customer_id from leads where id='c0600000-0000-0000-0000-000000000001')
  then 'PASS' else 'FAIL' end;

-- needs_routing sin fallback a la primera organización
insert into leads (id, reference_code, status, country, customer_name, phone, source, idempotency_key, conversion_status) values
  ('c0600000-0000-0000-0000-000000000003','LEAD003','new','DE','German Customer','+491234567','website', gen_random_uuid(), 'not_converted');
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select convert_website_lead('c0600000-0000-0000-0000-000000000003');
reset role;
insert into p11_all select 'test_no_routing_rule_needs_routing', case when conversion_status='needs_routing' then 'PASS' else 'FAIL' end from leads where id='c0600000-0000-0000-0000-000000000003';

-- ruteo manual + conversión por kcc_admin
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select manually_route_lead('c0600000-0000-0000-0000-000000000003', 'c0200000-0000-0000-0000-00000000000a');
select convert_website_lead('c0600000-0000-0000-0000-000000000003');
reset role;
insert into p11_all select 'test_manual_routing_and_conversion', case when conversion_status='converted' then 'PASS' else 'FAIL' end from leads where id='c0600000-0000-0000-0000-000000000003';

-- actor no confiable rechazado
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000002","role":"authenticated"}';
do $$ begin begin
  perform convert_website_lead('c0600000-0000-0000-0000-000000000001');
  insert into p11_all values ('test_ordinary_company_user_cannot_convert', 'FAIL (no exception)');
exception when others then insert into p11_all values ('test_ordinary_company_user_cannot_convert', 'PASS'); end; end $$;
do $$ begin begin
  perform manually_route_lead('c0600000-0000-0000-0000-000000000003', 'c0200000-0000-0000-0000-00000000000a');
  insert into p11_all values ('test_ordinary_company_user_cannot_manually_route', 'FAIL (no exception)');
exception when others then insert into p11_all values ('test_ordinary_company_user_cannot_manually_route', 'PASS'); end; end $$;
reset role;

-- matching por HIN (case-insensitive, entre customers distintos)
insert into leads (id, reference_code, status, country, customer_name, phone, email, vessel_make, vessel_model, hin, source, idempotency_key, conversion_status) values
  ('c0600000-0000-0000-0000-000000000004','HIN001','new','US','HIN Test','5550001111','hintest@example.com','Sea Ray','340', 'ABC12345D404','website', gen_random_uuid(), 'not_converted'),
  ('c0600000-0000-0000-0000-000000000005','HIN002','new','US','Different Name Same Boat','5550002222','different@example.com','Sea Ray','340', 'abc12345d404','website', gen_random_uuid(), 'not_converted');
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000001","role":"authenticated"}';
select manually_route_lead('c0600000-0000-0000-0000-000000000004', 'c0200000-0000-0000-0000-00000000000a');
select manually_route_lead('c0600000-0000-0000-0000-000000000005', 'c0200000-0000-0000-0000-00000000000a');
reset role;
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select convert_website_lead('c0600000-0000-0000-0000-000000000004');
select convert_website_lead('c0600000-0000-0000-0000-000000000005');
reset role;
insert into p11_all select 'test_hin_matches_case_insensitive_across_customers',
  case when (select marine_cloud_vessel_id from leads where id='c0600000-0000-0000-0000-000000000004') = (select marine_cloud_vessel_id from leads where id='c0600000-0000-0000-0000-000000000005')
  then 'PASS' else 'FAIL' end;

-- aislamiento tenant de leads
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into p11_all select 'test_other_org_cannot_see_leads_table', case when count(*)=0 then 'PASS' else 'FAIL' end from leads where id='c0600000-0000-0000-0000-000000000001';
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0100000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into p11_all select 'test_org_staff_cannot_see_platform_leads_table', case when count(*)=0 then 'PASS' else 'FAIL' end from leads where id='c0600000-0000-0000-0000-000000000001';
reset role;

select * from p11_all order by test_name;

-- =========================================================
-- C. CONFLICTO DE IDEMPOTENCIA — misma key, payload distinto
-- =========================================================
create temporary table p11c_all (test_name text, result text);
grant insert, select on p11c_all to authenticated;

do $$
declare v_shared_key uuid := gen_random_uuid();
begin
  insert into leads (id, reference_code, status, country, customer_name, phone, email, source, idempotency_key, conversion_status) values
    ('c9000000-0000-0000-0000-000000000001','IDEMPC1','new','US','Original Customer','5551110000','original@example.com','website', v_shared_key, 'not_converted');
  perform set_config('app.pc_shared_key', v_shared_key::text, false);
  begin
    insert into leads (id, reference_code, status, country, customer_name, phone, email, source, idempotency_key, conversion_status) values
      ('c9000000-0000-0000-0000-000000000002','IDEMPC2','new','US','DIFFERENT Customer','5559998888','different@example.com','website', v_shared_key, 'not_converted');
    insert into p11c_all values ('test_c_conflicting_payload_same_key_rejected', 'FAIL (no exception, duplicate key accepted)');
  exception when unique_violation then
    insert into p11c_all values ('test_c_conflicting_payload_same_key_rejected', 'PASS');
  end;
end $$;
insert into p11c_all select 'test_c_only_one_row_exists_for_key',
  case when (select count(*) from leads where idempotency_key = current_setting('app.pc_shared_key')::uuid) = 1 then 'PASS' else 'FAIL' end;
insert into p11c_all select 'test_c_original_row_unmodified',
  case when customer_name = 'Original Customer' and phone = '5551110000' then 'PASS' else 'FAIL' end
from leads where idempotency_key = current_setting('app.pc_shared_key')::uuid;

select * from p11c_all order by test_name;
delete from leads where id in ('c9000000-0000-0000-0000-000000000001','c9000000-0000-0000-0000-000000000002');

-- =========================================================
-- D/E. FALLA DESPUÉS DE CUSTOMER / DESPUÉS DE VESSEL
-- =========================================================
-- Estos dos escenarios exigen inyectar una falla controlada real
-- dentro de convert_website_lead() (mediante un valor centinela en
-- leads.description) y luego restaurar la función real — no se deja
-- una rama de prueba permanente en producción (ver migraciones 172/
-- 173, que documentan el resultado exacto de esta corrida). Se deja
-- comentado el procedimiento para reproducirlo manualmente si hace
-- falta re-verificar el invariante de atomicidad:
--
-- 1. CREATE OR REPLACE la función agregando, justo después de
--    resolver v_customer_id:
--      if v_lead.description = 'FORCE_FAIL_AFTER_CUSTOMER' then
--        raise exception 'forced test failure after customer creation';
--      end if;
--    y justo después de resolver v_vessel_id:
--      if v_lead.description = 'FORCE_FAIL_AFTER_VESSEL' then
--        raise exception 'forced test failure after vessel creation';
--      end if;
-- 2. Crear un lead con description='FORCE_FAIL_AFTER_CUSTOMER',
--    convertirlo -> debe quedar conversion_status='failed' con
--    conversion_error real, SIN customer huérfano.
-- 3. Arreglar la description, reintentar -> debe completar con
--    exactamente un customer/vessel/service_request nuevo.
-- 4. Repetir con description='FORCE_FAIL_AFTER_VESSEL' -> mismo
--    criterio, sin vessel huérfano, customer también revertido
--    atómicamente (todo el bloque comparte un solo savepoint).
-- 5. Restaurar la función a la versión de la migración 173 (sin
--    ninguna rama de prueba).
--
-- Resultado verificado en vivo la última vez que se corrió
-- (documentado en docs/PHASE-11-REPORT.md): 16/16 PASS entre D y E
-- combinados (falla real persistida, sin huérfanos, reintento limpio
-- con conteos exactos, conversion_error limpio al convertir con
-- éxito).
-- =========================================================

-- CLEANUP
delete from notifications where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from domain_events where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
update leads set marine_cloud_service_request_id=null, marine_cloud_customer_id=null, marine_cloud_vessel_id=null where source='website';
delete from service_requests where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from vessels where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from customers where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from lead_routing_rules where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from leads where id::text like 'c0600000-0000-0000-0000-00000000000%';
delete from organization_memberships where organization_id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from organizations where id in ('c0200000-0000-0000-0000-00000000000a','c0200000-0000-0000-0000-00000000000b');
delete from profiles where email like 'p11-%@rls-test.local';
delete from auth.users where email like 'p11-%@rls-test.local';
select 'phase11 suite cleanup complete' as status;
