-- =========================================================
-- 145_protect_kcc_generated_field.sql — Phase 10 final fix
-- =========================================================
-- BUG REAL: staff_create_work_orders/staff_update_work_orders
-- permiten a is_org_staff() escribir CUALQUIER columna, incluido
-- kcc_generated — campo con consecuencias financieras reales.
-- NOTA: esta versión combinaba autorización + auditoría en un solo
-- trigger BEFORE, lo cual causó un bug de reentrada real (corregido
-- en la migración 146, aplicada por separado inmediatamente
-- después) — se deja este archivo tal cual se aplicó, reflejando el
-- historial real.
-- =========================================================

create or replace function guard_kcc_generated_field()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    if NEW.kcc_generated and not is_platform_trusted_actor() then
      raise exception 'only KCC platform staff can create a work order marked kcc_generated';
    end if;
  elsif TG_OP = 'UPDATE' then
    if NEW.kcc_generated is distinct from OLD.kcc_generated and not is_platform_trusted_actor() then
      raise exception 'only KCC platform staff can change kcc_generated on a work order';
    end if;
    if NEW.kcc_generated is distinct from OLD.kcc_generated then
      perform log_domain_event(NEW.organization_id, 'KCC_GENERATED_FLAG_CHANGED', 'work_order', NEW.id,
        jsonb_build_object('from', OLD.kcc_generated, 'to', NEW.kcc_generated));
      perform log_audit_event(NEW.organization_id, 'work_order', NEW.id, 'kcc_generated_changed',
        jsonb_build_object('kcc_generated', OLD.kcc_generated), jsonb_build_object('kcc_generated', NEW.kcc_generated));
    end if;
  end if;
  return NEW;
end;
$$;

create trigger trg_guard_kcc_generated_field
  before insert or update on work_orders
  for each row execute function guard_kcc_generated_field();

create or replace function set_work_order_kcc_generated(p_work_order_id uuid, p_kcc_generated boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can change kcc_generated';
  end if;
  update work_orders set kcc_generated = p_kcc_generated, updated_at = now() where id = p_work_order_id;
  if not found then
    raise exception 'work order not found';
  end if;
end;
$$;

revoke execute on function set_work_order_kcc_generated(uuid, boolean) from public, anon;
grant execute on function set_work_order_kcc_generated(uuid, boolean) to authenticated;
