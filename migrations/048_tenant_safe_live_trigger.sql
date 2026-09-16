-- =========================================================
-- 048_tenant_safe_live_trigger.sql — Marine Cloud Phase 3B hardening
-- =========================================================
-- HALLAZGO REAL probando la migración 047: el trigger en vivo
-- resolve_domain_event_work_order_id() (migración 039) tenía el
-- MISMO hueco que tenía el backfill histórico. Se aplica la misma
-- defensa acá — un evento con organization_id inconsistente resuelve
-- a NULL en vez de arriesgar un FK violation que aborte el insert.
--
-- Verificado con un insert adversarial real: el trigger neutraliza el
-- intento a NULL para entity_types que reconoce, y la FK compuesta
-- (migración 043) queda como segunda capa de defensa para cualquier
-- otro caso — probado explícitamente con un entity_type que el
-- trigger no toca, confirmando que la FK en sí también sigue activa.
-- =========================================================

create or replace function resolve_domain_event_work_order_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.entity_type = 'work_order' then
    select id into new.work_order_id from work_orders where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'appointment' then
    select work_order_id into new.work_order_id from appointments where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'media_asset' then
    select work_order_id into new.work_order_id from media_assets where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'work_note' then
    select work_order_id into new.work_order_id from work_notes where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'measurement' then
    select work_order_id into new.work_order_id from measurements where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'checklist_response' then
    select work_order_id into new.work_order_id from checklist_responses where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'progress_update' then
    select work_order_id into new.work_order_id from progress_updates where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'time_entry' then
    select work_order_id into new.work_order_id from time_entries where id = new.entity_id and organization_id = new.organization_id;
  end if;
  return new;
end;
$$;

revoke execute on function resolve_domain_event_work_order_id() from public, anon, authenticated;
