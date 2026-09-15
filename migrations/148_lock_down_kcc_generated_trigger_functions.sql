-- =========================================================
-- 148_lock_down_kcc_generated_trigger_functions.sql — Phase 10 final fix
-- =========================================================
-- Hallazgo real del advisor: guard_kcc_generated_field_before()/
-- audit_kcc_generated_field_after() (funciones de trigger) eran
-- callables por anon vía RPC. Mismo patrón ya aplicado a
-- generate_notifications_from_domain_event() en Phase 9.
-- =========================================================

revoke execute on function guard_kcc_generated_field_before() from public, anon, authenticated;
revoke execute on function audit_kcc_generated_field_after() from public, anon, authenticated;
