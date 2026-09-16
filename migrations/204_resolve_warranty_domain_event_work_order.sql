-- =========================================================
-- 204_resolve_warranty_domain_event_work_order.sql — Phase 13 final integrity
-- =========================================================
-- BUG REAL: resolve_domain_event_work_order_id() no manejaba
-- entity_type='warranty' — las notificaciones de warranty al customer
-- nunca llegaban a nadie. Verificado con datos reales: notificación
-- real creada para el customer correcto tras activar warranty.
-- =========================================================

create or replace function resolve_domain_event_work_order_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
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
  elsif new.entity_type = 'kcc_assistance_request' then
    select work_order_id into new.work_order_id from kcc_assistance_requests where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'warranty' then
    select work_order_id into new.work_order_id from warranties where id = new.entity_id and organization_id = new.organization_id;
  end if;
  return new;
end;
$function$;
