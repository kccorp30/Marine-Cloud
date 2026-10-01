-- =========================================================
-- 20260916100000_start_route_requires_service_address.sql — Technician Mission
-- =========================================================
-- Brief: "Para iniciar ruta debe existir una dirección válida...
-- Si falta: NO permitir START ROUTE." Nunca se validaba —
-- technician_start_route() transicionaba sin chequear ubicación.
-- Exige service_street_address O marina (texto libre aceptado como
-- ubicación válida). Rechazo real server-side, nunca solo un botón
-- deshabilitado. Verificado con datos reales: bloquea sin dirección,
-- permite con dirección — 2/2 PASS.
-- =========================================================

create or replace function technician_start_route(p_work_order_id uuid)
returns work_orders
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_wo work_orders;
  v_has_location boolean;
begin
  select exists (
    select 1 from work_orders wo join vessels v on v.id = wo.vessel_id
    where wo.id = p_work_order_id
      and (coalesce(trim(v.service_street_address), '') != '' or coalesce(trim(v.marina), '') != '')
  ) into v_has_location;

  if not v_has_location then
    raise exception 'service location required — this vessel has no service address or marina on file';
  end if;

  v_wo := transition_work_order(p_work_order_id, 'en_route');
  perform log_domain_event(v_wo.organization_id, 'TECHNICIAN_EN_ROUTE', 'work_order', p_work_order_id, '{}'::jsonb);
  return v_wo;
end;
$function$;
