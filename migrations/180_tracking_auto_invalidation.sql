-- =========================================================
-- 180_tracking_auto_invalidation.sql — Marine Cloud Phase 12
-- =========================================================
-- La sesión se invalida automáticamente cuando el work order sale de
-- en_route, o la asignación deja de estar activa. Verificado con
-- datos reales: salir de en_route expira la sesión, e ingestión
-- posterior queda rechazada.
-- =========================================================

create or replace function auto_expire_tracking_on_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.current_status is distinct from OLD.current_status and OLD.current_status = 'en_route' then
    update technician_tracking_sessions
    set status = 'expired', stopped_at = now(), updated_at = now()
    where work_order_id = NEW.id and status in ('active', 'paused');
  end if;
  return NEW;
end;
$$;

create trigger trg_auto_expire_tracking_on_status_change
  after update on work_orders
  for each row execute function auto_expire_tracking_on_status_change();

revoke execute on function auto_expire_tracking_on_status_change() from public, anon, authenticated;

create or replace function auto_expire_tracking_on_assignment_removed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.status is distinct from OLD.status and OLD.status = 'active' and NEW.status != 'active' then
    update technician_tracking_sessions
    set status = 'expired', stopped_at = now(), updated_at = now()
    where assignment_id = NEW.id and status in ('active', 'paused');
  end if;
  return NEW;
end;
$$;

create trigger trg_auto_expire_tracking_on_assignment_removed
  after update on assignments
  for each row execute function auto_expire_tracking_on_assignment_removed();

revoke execute on function auto_expire_tracking_on_assignment_removed() from public, anon, authenticated;
