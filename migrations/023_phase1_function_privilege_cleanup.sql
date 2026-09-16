-- =========================================================
-- 023_phase1_function_privilege_cleanup.sql — Marine Cloud Phase 1
-- Hallazgo del security advisor: el patrón de bug de Phase 0 se
-- repitió (toda función nueva recibe grant directo a `anon` al
-- crearse, no solo vía PUBLIC — revocar de PUBLIC no alcanza).
-- Además, los triggers puros nunca deben invocarse vía RPC directo.
-- =========================================================

revoke execute on function transition_work_order(uuid, text, text) from anon;

revoke execute on function trg_audit_row_change() from anon, authenticated;
revoke execute on function trg_emit_customer_created() from anon, authenticated;
revoke execute on function trg_emit_vessel_created() from anon, authenticated;
revoke execute on function trg_emit_vessel_owner_changed() from anon, authenticated;
revoke execute on function trg_emit_vessel_system_added() from anon, authenticated;
revoke execute on function trg_emit_work_order_created() from anon, authenticated;
revoke execute on function trg_emit_appointment_event() from anon, authenticated;
revoke execute on function trg_emit_assignment_event() from anon, authenticated;
