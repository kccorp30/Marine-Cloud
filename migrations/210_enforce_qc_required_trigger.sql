-- =========================================================
-- 210_enforce_qc_required_trigger.sql — Phase 13 true final closure
-- =========================================================
-- GAP REAL: lib/work-orders/actions.ts createWorkOrder() inserta
-- directo en work_orders con service_id, pero nunca seteaba
-- qc_required — 4ta ruta real de creación, no auditada antes.
-- Trigger BEFORE INSERT que SIEMPRE sobrescribe NEW.qc_required con
-- resolve_qc_required() — cierra todo camino presente y futuro. Solo
-- BEFORE INSERT, nunca BEFORE UPDATE (snapshot histórico).
-- Verificado con datos reales: servicio true/false, sin servicio
-- (default de org), browser no puede forjar true NI false.
-- =========================================================

create or replace function enforce_qc_required_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.qc_required := resolve_qc_required(new.organization_id, new.service_id);
  return new;
end;
$$;

create trigger trg_enforce_qc_required_snapshot
  before insert on work_orders
  for each row execute function enforce_qc_required_snapshot();
