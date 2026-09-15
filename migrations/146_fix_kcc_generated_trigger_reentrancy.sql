-- =========================================================
-- 146_fix_kcc_generated_trigger_reentrancy.sql — Phase 10 final fix
-- =========================================================
-- BUG REAL encontrado probando 145: el trigger BEFORE llamaba a
-- log_domain_event()/log_audit_event(), que disparan otro trigger
-- que vuelve a tocar la MISMA fila de work_orders todavía en
-- proceso — "tuple to be updated was already modified by an
-- operation triggered by the current command". Se separa en dos
-- triggers: BEFORE (solo autoriza, sin efectos secundarios) y AFTER
-- (audita, corre una vez la fila ya quedó confirmada).
-- Verificado con datos reales tras el fix: kcc_admin puede setear,
-- evento auditado, staff normal sigue rechazado.
-- =========================================================

drop trigger if exists trg_guard_kcc_generated_field on work_orders;
drop function if exists guard_kcc_generated_field();

create or replace function guard_kcc_generated_field_before()
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
  end if;
  return NEW;
end;
$$;

create trigger trg_guard_kcc_generated_field_before
  before insert or update on work_orders
  for each row execute function guard_kcc_generated_field_before();

create or replace function audit_kcc_generated_field_after()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'UPDATE' and NEW.kcc_generated is distinct from OLD.kcc_generated then
    perform log_domain_event(NEW.organization_id, 'KCC_GENERATED_FLAG_CHANGED', 'work_order', NEW.id,
      jsonb_build_object('from', OLD.kcc_generated, 'to', NEW.kcc_generated));
    perform log_audit_event(NEW.organization_id, 'work_order', NEW.id, 'kcc_generated_changed',
      jsonb_build_object('kcc_generated', OLD.kcc_generated), jsonb_build_object('kcc_generated', NEW.kcc_generated));
  end if;
  return NEW;
end;
$$;

create trigger trg_audit_kcc_generated_field_after
  after update on work_orders
  for each row execute function audit_kcc_generated_field_after();
