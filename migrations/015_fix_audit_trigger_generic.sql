-- =========================================================
-- 015_fix_audit_trigger_generic.sql — Marine Cloud Phase 0
-- =========================================================
-- Bug real: trg_audit_row_change() asumía que toda tabla auditada
-- tiene columna organization_id (cierto para organization_memberships,
-- FALSO para organizations, donde la propia fila ES la organización).
-- Corrijo con extracción dinámica vía jsonb en vez de acceso directo
-- al campo — funciona para cualquier tabla futura sin importar su forma.
create or replace function trg_audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  -- Intenta leer organization_id; si la tabla no tiene esa columna
  -- (ej. la propia tabla organizations), usa el id de la fila.
  v_org_id := coalesce(
    (to_jsonb(new)->>'organization_id')::uuid,
    (to_jsonb(old)->>'organization_id')::uuid,
    (to_jsonb(new)->>'id')::uuid,
    (to_jsonb(old)->>'id')::uuid
  );

  perform log_audit_event(
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
