-- =========================================================
-- tests/rls/phase0-rls-tests.sql
-- =========================================================
-- Pruebas RLS ejecutables y repetibles para Phase 0. Diseñadas para
-- correrse en el SQL Editor de Supabase (o vía psql con una conexión
-- que tenga privilegios para usar SET ROLE / SET request.jwt.claims —
-- típicamente la conexión directa de Postgres, no el pooler).
--
-- Patrón: cada test simula un usuario real vía
-- `set local request.jwt.claims`, corre una query, y compara el
-- resultado esperado contra el real. Los fixtures se crean al
-- principio y se destruyen al final — correr este archivo completo
-- no deja rastros en la base.
--
-- Cómo correrlo: pegar el archivo completo en el SQL Editor de
-- Supabase y ejecutar. Cada bloque imprime su resultado; revisar que
-- todos digan PASS.
-- =========================================================

-- ---------------------------------------------------------
-- FIXTURES
-- ---------------------------------------------------------
insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role)
values
  ('10000000-0000-0000-0000-000000000001', 'test-kcc-admin@rls-test.local', 'x', now(), now(), now(), 'authenticated', 'authenticated'),
  ('10000000-0000-0000-0000-000000000002', 'test-admin-a@rls-test.local', 'x', now(), now(), now(), 'authenticated', 'authenticated'),
  ('10000000-0000-0000-0000-000000000003', 'test-tech-a@rls-test.local', 'x', now(), now(), now(), 'authenticated', 'authenticated'),
  ('10000000-0000-0000-0000-000000000004', 'test-cust-a@rls-test.local', 'x', now(), now(), now(), 'authenticated', 'authenticated'),
  ('10000000-0000-0000-0000-000000000005', 'test-cust-b@rls-test.local', 'x', now(), now(), now(), 'authenticated', 'authenticated'),
  ('10000000-0000-0000-0000-000000000006', 'test-suspended-a@rls-test.local', 'x', now(), now(), now(), 'authenticated', 'authenticated')
on conflict (id) do nothing;

insert into organizations (id, name, slug, status)
values
  ('20000000-0000-0000-0000-00000000000a', 'RLS Test Org A', 'rls-test-org-a-v2', 'active'),
  ('20000000-0000-0000-0000-00000000000b', 'RLS Test Org B', 'rls-test-org-b-v2', 'active')
on conflict (id) do nothing;

insert into organization_memberships (profile_id, organization_id, role, status)
values
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-00000000000a', 'kcc_admin', 'active'),
  ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-00000000000a', 'company_admin', 'active'),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-00000000000a', 'technician', 'active'),
  ('10000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-00000000000a', 'customer', 'active'),
  ('10000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-00000000000b', 'customer', 'active'),
  ('10000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-00000000000a', 'customer', 'suspended')
on conflict do nothing;

-- ---------------------------------------------------------
-- TEST 1 — unauthenticated (anon, sin JWT) no debe leer tenant data
-- ---------------------------------------------------------
-- Nota real: anon ni siquiera puede EVALUAR la policy (no tiene
-- permiso de ejecutar is_kcc_admin(), que la policy invoca) — el
-- resultado es "permission denied", una denegación más estricta que
-- un simple conteo en cero. Este test acepta ambos desenlaces como
-- correctos porque ambos significan lo mismo: anon no ve nada.
create temporary table if not exists test_results (test_name text, result text);
do $$
declare
  v_count int;
begin
  begin
    set local role anon;
    select count(*) into v_count from organizations where id in ('20000000-0000-0000-0000-00000000000a','20000000-0000-0000-0000-00000000000b');
    insert into test_results values ('test_1_anon_blocked', case when v_count = 0 then 'PASS (empty result)' else 'FAIL' end);
  exception when insufficient_privilege then
    insert into test_results values ('test_1_anon_blocked', 'PASS (permission denied)');
  end;
end $$;
reset role;
select * from test_results where test_name = 'test_1_anon_blocked';

-- ---------------------------------------------------------
-- TEST 2 — customer NO debe ver otra organización
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';
select case when array_agg(name) = array['RLS Test Org A'] then 'PASS' else 'FAIL: ' || array_agg(name)::text end as test_2_customer_isolated
from organizations where id in ('20000000-0000-0000-0000-00000000000a','20000000-0000-0000-0000-00000000000b');
reset role;

-- ---------------------------------------------------------
-- TEST 3 — technician NO debe ver otra organización
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';
select case when array_agg(name) = array['RLS Test Org A'] then 'PASS' else 'FAIL: ' || array_agg(name)::text end as test_3_technician_isolated
from organizations where id in ('20000000-0000-0000-0000-00000000000a','20000000-0000-0000-0000-00000000000b');
reset role;

-- ---------------------------------------------------------
-- TEST 4 — company_admin SÍ puede leer/actualizar recursos permitidos
-- de SU organización (positivo)
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';
update organizations set name = 'RLS Test Org A (verified)' where id = '20000000-0000-0000-0000-00000000000a';
select case when name = 'RLS Test Org A (verified)' then 'PASS' else 'FAIL' end as test_4_admin_can_update_own_org
from organizations where id = '20000000-0000-0000-0000-00000000000a';
reset role;

-- ---------------------------------------------------------
-- TEST 5 — company_admin NO puede actualizar otra organización
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';
update organizations set name = 'HACKED' where id = '20000000-0000-0000-0000-00000000000b';
select case when count(*) = 0 then 'PASS' else 'FAIL' end as test_5_admin_cannot_update_other_org
from organizations where id = '20000000-0000-0000-0000-00000000000b' and name = 'HACKED';
reset role;

-- ---------------------------------------------------------
-- TEST 6 — kcc_admin SÍ ve ambas organizaciones (cross-tenant, según
-- arquitectura aprobada)
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';
select case when count(*) = 2 then 'PASS' else 'FAIL' end as test_6_kcc_admin_cross_tenant
from organizations where id in ('20000000-0000-0000-0000-00000000000a','20000000-0000-0000-0000-00000000000b');
reset role;

-- ---------------------------------------------------------
-- TEST 7 — cambiar la cookie kcc_active_org a otra organización NO
-- puede exponer esos datos. La cookie nunca llega a Postgres (no
-- existe ninguna policy que la lea) — este test simula exactamente
-- ese escenario: un customer de Org A cuya app "cree" tener Org B
-- activa (cookie manipulada a mano) sigue sin poder leer Org B,
-- porque RLS depende únicamente de organization_memberships, nunca
-- de la cookie.
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';
-- Simula que la app, con la cookie manipulada, arma esta query como si Org B fuera la activa:
select case when count(*) = 0 then 'PASS' else 'FAIL' end as test_7_active_org_cookie_cannot_bypass_rls
from organizations where id = '20000000-0000-0000-0000-00000000000b';
reset role;

-- ---------------------------------------------------------
-- TEST 8 — membership suspendida pierde acceso
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}';
select case when count(*) = 0 then 'PASS' else 'FAIL' end as test_8_suspended_membership_loses_access
from organizations where id = '20000000-0000-0000-0000-00000000000a';
reset role;

-- ---------------------------------------------------------
-- TEST 9 — bloqueo de escalación de privilegios (staff no puede
-- otorgarse kcc_admin a sí mismo)
-- ---------------------------------------------------------
do $$
begin
  begin
    set local role authenticated;
    set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';
    insert into organization_memberships (profile_id, organization_id, role, status)
    values ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-00000000000a', 'kcc_admin', 'active');
    insert into test_results values ('test_9_privilege_escalation_blocked', 'FAIL (insert succeeded)');
  exception when insufficient_privilege then
    insert into test_results values ('test_9_privilege_escalation_blocked', 'PASS');
  end;
end $$;
reset role;

-- ---------------------------------------------------------
-- TEST 10 — domain_events no acepta insert directo del cliente
-- ---------------------------------------------------------
do $$
begin
  begin
    set local role authenticated;
    set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';
    insert into domain_events (organization_id, event_type, entity_type, entity_id)
    values ('20000000-0000-0000-0000-00000000000a','FAKE','test', gen_random_uuid());
    insert into test_results values ('test_10_domain_events_no_direct_insert', 'FAIL (insert succeeded)');
  exception when insufficient_privilege then
    insert into test_results values ('test_10_domain_events_no_direct_insert', 'PASS');
  end;
end $$;
reset role;

-- ---------------------------------------------------------
-- TEST 11 — log_domain_event() funciona para la org propia, falla
-- para una ajena
-- ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into test_results
select 'test_11a_log_event_own_org', case when log_domain_event('20000000-0000-0000-0000-00000000000a','TEST','test',gen_random_uuid()) is not null then 'PASS' else 'FAIL' end;
reset role;

do $$
begin
  begin
    set local role authenticated;
    set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';
    perform log_domain_event('20000000-0000-0000-0000-00000000000b','FAKE','test',gen_random_uuid());
    insert into test_results values ('test_11b_log_event_other_org_blocked', 'FAIL (call succeeded)');
  exception when others then
    insert into test_results values ('test_11b_log_event_other_org_blocked', 'PASS');
  end;
end $$;
reset role;

select * from test_results order by test_name;

-- ---------------------------------------------------------
-- CLEANUP — no debe quedar ningún rastro de estos fixtures
-- ---------------------------------------------------------
delete from domain_events where organization_id in ('20000000-0000-0000-0000-00000000000a','20000000-0000-0000-0000-00000000000b');
delete from audit_events where organization_id in ('20000000-0000-0000-0000-00000000000a','20000000-0000-0000-0000-00000000000b');
delete from organization_memberships where organization_id in ('20000000-0000-0000-0000-00000000000a','20000000-0000-0000-0000-00000000000b');
delete from organizations where id in ('20000000-0000-0000-0000-00000000000a','20000000-0000-0000-0000-00000000000b');
delete from profiles where email like '%rls-test.local';
delete from auth.users where email like '%rls-test.local';
select 'cleanup complete' as status;
