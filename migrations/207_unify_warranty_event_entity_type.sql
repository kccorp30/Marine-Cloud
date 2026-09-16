-- =========================================================
-- 207_unify_warranty_event_entity_type.sql — Phase 13 final integrity
-- =========================================================
-- Consistencia real: void_warranty() ahora también usa
-- entity_type='warranty' + entity_id=warranty.id, igual que el resto
-- de eventos de warranty — el resolver de 204 ya lo maneja de forma
-- uniforme para todos.
-- =========================================================

create or replace function void_warranty(p_warranty_id uuid, p_reason text)
returns warranties
language plpgsql
security definer
set search_path = public
as $$
declare
  v_warranty warranties%rowtype;
begin
  select * into v_warranty from warranties where id = p_warranty_id for update;
  if v_warranty.id is null then
    raise exception 'warranty not found';
  end if;
  if not is_org_staff(v_warranty.organization_id) then
    raise exception 'not authorized to void this warranty';
  end if;
  if v_warranty.status = 'voided' then
    return v_warranty;
  end if;
  if p_reason is null or trim(p_reason) = '' then
    raise exception 'a reason is required to void a warranty';
  end if;

  update warranties set status = 'voided', voided_at = now(), void_reason = p_reason, updated_at = now()
  where id = p_warranty_id returning * into v_warranty;

  perform log_domain_event(v_warranty.organization_id, 'WARRANTY_VOIDED', 'warranty', p_warranty_id,
    jsonb_build_object('warranty_id', p_warranty_id, 'reason', p_reason));
  perform log_audit_event(v_warranty.organization_id, 'warranty', p_warranty_id, 'warranty_voided',
    jsonb_build_object('status', 'active'), jsonb_build_object('status', 'voided', 'reason', p_reason));

  return v_warranty;
end;
$$;
