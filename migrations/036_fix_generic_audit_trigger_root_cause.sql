-- =========================================================
-- 036_fix_generic_audit_trigger_root_cause.sql — Marine Cloud Phase 2
-- =========================================================
-- Bug real, mismo patrón que 027 pero en la raíz: trg_audit_row_change()
-- — el trigger genérico usado en TODAS las tablas auditadas — llamaba
-- a la función PÚBLICA log_audit_event(), que exige ser staff.
-- Cualquier UPDATE legítimo hecho por un technician/customer ya
-- autorizado (ej. technician_check_in() actualizando appointments)
-- rompía con "not authorized to log audit events". Como TODO
-- llamador de este trigger ya pasó por una escritura autorizada
-- (RLS o una función SECURITY DEFINER que ya validó), corresponde
-- usar la función INTERNA, nunca la pública.
--
-- Encontrado en vivo probando el flujo completo del técnico —
-- técnico_check_in() actualiza appointments.actual_start, lo que
-- dispara trg_audit_appointments_actual_times (nueva de esta fase),
-- que llamaba a trg_audit_row_change(), que fallaba para el técnico.
-- =========================================================

create or replace function trg_audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  v_org_id := coalesce(
    (to_jsonb(new)->>'organization_id')::uuid,
    (to_jsonb(old)->>'organization_id')::uuid,
    (to_jsonb(new)->>'id')::uuid,
    (to_jsonb(old)->>'id')::uuid
  );

  perform log_audit_event_internal(
    v_org_id,
    TG_TABLE_NAME,
    coalesce(new.id, old.id),
    TG_OP,
    to_jsonb(old),
    to_jsonb(new)
  );
  return new;
end;
$$;

revoke execute on function trg_audit_row_change() from public, anon, authenticated;
