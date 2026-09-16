-- =========================================================
-- 026_final_privilege_audit_and_fix.sql
-- =========================================================
-- Hallazgo real (verificado contra information_schema, no caché del
-- advisor): las funciones trigger de la migración 022 todavía tenían
-- EXECUTE otorgado a PUBLIC. La migración 023 revocó de
-- `anon`/`authenticated` directamente, pero un grant a PUBLIC es
-- INDEPENDIENTE de eso — cualquier rol hereda de PUBLIC salvo que se
-- revoque ahí también. Espejo exacto del bug de Phase 0 (ahí era al
-- revés). Ambas direcciones deben revocarse SIEMPRE juntas.
-- =========================================================

revoke execute on function trg_audit_row_change() from public;
revoke execute on function trg_emit_customer_created() from public;
revoke execute on function trg_emit_vessel_created() from public;
revoke execute on function trg_emit_vessel_owner_changed() from public;
revoke execute on function trg_emit_vessel_system_added() from public;
revoke execute on function trg_emit_work_order_created() from public;
revoke execute on function trg_emit_appointment_event() from public;
revoke execute on function trg_emit_assignment_event() from public;

-- Verificación defensiva: revoca de public/anon/authenticated TODAS
-- las funciones trigger de este proyecto (patrón 'trg_%'), sin
-- depender de que alguien se acuerde de listarlas todas a mano.
do $$
declare
  r record;
begin
  for r in
    select p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'trg\_%'
  loop
    execute format('revoke execute on function %I() from public, anon, authenticated', r.proname);
  end loop;
end $$;
