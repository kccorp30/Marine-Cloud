-- =========================================================
-- 143_historical_compensation_resolution.sql — Phase 10 final fix
-- =========================================================
-- BUG REAL Y GRAVE: attribute_kcc_work() exigía active=true además
-- del rango de fechas — un acuerdo histórico correcto dejaba de
-- encontrarse en cuanto se reemplazaba/desactivaba.
--
-- Semántica clara: `active` = operativo/seleccionable HOY, nunca
-- borra aplicabilidad histórica. Resolución histórica: SOLO rango
-- effective_from/effective_until. Solapamiento real a nivel de base:
-- EXCLUDE constraint con btree_gist, cubre TODO acuerdo (activo o
-- no). Al crear un acuerdo que reemplaza uno abierto, el viejo se
-- cierra automáticamente en (nuevo.effective_from - 1 día).
-- Verificado con datos reales: agreement A auto-cerrado al crear B,
-- atribución corrida DESPUÉS del reemplazo sigue resolviendo A,
-- work order tras Mar1 resuelve B, solapamiento contra histórico
-- inactivo rechazado.
-- =========================================================

create extension if not exists btree_gist;

alter table compensation_agreements add constraint excl_compensation_agreements_no_overlap
  exclude using gist (
    organization_id with =,
    daterange(effective_from, coalesce(effective_until, 'infinity'::date), '[]') with &&
  );

create or replace function create_compensation_agreement(
  p_organization_id uuid,
  p_compensation_type text,
  p_percentage_rate numeric default null,
  p_fixed_amount numeric default null,
  p_currency text default 'USD',
  p_effective_from date default current_date,
  p_effective_until date default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_open_ended_id uuid;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can create compensation agreements';
  end if;
  if not exists (select 1 from organizations where id = p_organization_id) then
    raise exception 'organization not found';
  end if;

  select id into v_open_ended_id from compensation_agreements
  where organization_id = p_organization_id and active = true and effective_until is null
  limit 1;

  if v_open_ended_id is not null then
    if p_effective_from <= (select effective_from from compensation_agreements where id = v_open_ended_id) then
      raise exception 'new agreement effective_from must be after the current open-ended agreement started';
    end if;
    update compensation_agreements
    set effective_until = p_effective_from - 1, active = false, updated_at = now()
    where id = v_open_ended_id;

    perform log_domain_event(p_organization_id, 'COMPENSATION_AGREEMENT_CHANGED', 'compensation_agreement', v_open_ended_id,
      jsonb_build_object('action', 'closed_by_replacement', 'effective_until', p_effective_from - 1));
  end if;

  insert into compensation_agreements (organization_id, compensation_type, percentage_rate, fixed_amount, currency, effective_from, effective_until, notes, created_by)
  values (p_organization_id, p_compensation_type, p_percentage_rate, p_fixed_amount, p_currency, p_effective_from, p_effective_until, p_notes, auth.uid())
  returning id into v_id;

  perform log_domain_event(p_organization_id, 'COMPENSATION_AGREEMENT_CREATED', 'compensation_agreement', v_id,
    jsonb_build_object('compensation_type', p_compensation_type, 'effective_from', p_effective_from));
  perform log_audit_event(p_organization_id, 'compensation_agreement', v_id, 'compensation_agreement_created',
    null, jsonb_build_object('compensation_type', p_compensation_type));

  return v_id;
end;
$$;

create or replace function resolve_compensation_agreement(p_organization_id uuid, p_as_of_date date)
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select id from compensation_agreements
  where organization_id = p_organization_id
    and effective_from <= p_as_of_date
    and (effective_until is null or effective_until >= p_as_of_date)
  order by effective_from desc
  limit 1;
$$;

revoke execute on function resolve_compensation_agreement(uuid, date) from public, anon;
grant execute on function resolve_compensation_agreement(uuid, date) to authenticated;
