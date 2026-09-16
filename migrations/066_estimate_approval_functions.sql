-- =========================================================
-- 066_estimate_approval_functions.sql — Marine Cloud Phase 6
-- =========================================================
-- La pieza más crítica de esta fase. Verificado con datos reales:
-- customer aprueba, work order pasa automáticamente de
-- awaiting_approval a scheduled vía transition_work_order() (nunca
-- un UPDATE directo a current_status), decisión queda registrada de
-- forma durable, doble aprobación rechazada por la unique constraint
-- de estimate_decisions.
-- =========================================================

create or replace function approve_estimate(p_estimate_version_id uuid, p_customer_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version estimate_versions%rowtype;
  v_estimate estimates%rowtype;
begin
  select * into v_version from estimate_versions where id = p_estimate_version_id for update;
  if v_version.id is null then
    raise exception 'estimate version not found';
  end if;

  select * into v_estimate from estimates where id = v_version.estimate_id for update;

  if not is_own_customer_record(v_estimate.customer_id) then
    raise exception 'not authorized to approve this estimate';
  end if;

  if v_estimate.current_version_id != p_estimate_version_id then
    raise exception 'this is not the current actionable version';
  end if;
  if v_version.status not in ('sent', 'viewed') then
    raise exception 'this version cannot be approved (status: %)', v_version.status;
  end if;
  if v_version.valid_until is not null and v_version.valid_until < current_date then
    update estimate_versions set status = 'expired' where id = p_estimate_version_id;
    update estimates set status = 'expired' where id = v_estimate.id;
    raise exception 'this estimate has expired';
  end if;

  insert into estimate_decisions (organization_id, estimate_id, estimate_version_id, customer_id, decision, version_total_at_decision, customer_note)
  values (v_estimate.organization_id, v_estimate.id, p_estimate_version_id, v_estimate.customer_id, 'approved', v_version.total, p_customer_note);

  update estimate_versions set status = 'approved' where id = p_estimate_version_id;
  update estimates set status = 'approved', updated_at = now() where id = v_estimate.id;

  if v_estimate.work_order_id is not null then
    if (select current_status from work_orders where id = v_estimate.work_order_id) = 'awaiting_approval' then
      perform transition_work_order(v_estimate.work_order_id, 'scheduled');
    end if;
  end if;

  perform log_domain_event(v_estimate.organization_id, 'ESTIMATE_APPROVED', 'estimate', v_estimate.id,
    jsonb_build_object('estimate_version_id', p_estimate_version_id, 'total', v_version.total));
end;
$$;

revoke execute on function approve_estimate(uuid, text) from public, anon;
grant execute on function approve_estimate(uuid, text) to authenticated;

create or replace function decline_estimate(p_estimate_version_id uuid, p_customer_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version estimate_versions%rowtype;
  v_estimate estimates%rowtype;
begin
  select * into v_version from estimate_versions where id = p_estimate_version_id for update;
  if v_version.id is null then
    raise exception 'estimate version not found';
  end if;

  select * into v_estimate from estimates where id = v_version.estimate_id for update;

  if not is_own_customer_record(v_estimate.customer_id) then
    raise exception 'not authorized to decline this estimate';
  end if;

  if v_estimate.current_version_id != p_estimate_version_id then
    raise exception 'this is not the current actionable version';
  end if;
  if v_version.status not in ('sent', 'viewed') then
    raise exception 'this version cannot be declined (status: %)', v_version.status;
  end if;

  insert into estimate_decisions (organization_id, estimate_id, estimate_version_id, customer_id, decision, version_total_at_decision, customer_note)
  values (v_estimate.organization_id, v_estimate.id, p_estimate_version_id, v_estimate.customer_id, 'declined', v_version.total, p_customer_note);

  update estimate_versions set status = 'declined' where id = p_estimate_version_id;
  update estimates set status = 'declined', updated_at = now() where id = v_estimate.id;

  if v_estimate.work_order_id is not null then
    if (select current_status from work_orders where id = v_estimate.work_order_id) = 'awaiting_approval' then
      perform transition_work_order(v_estimate.work_order_id, 'cancelled');
    end if;
  end if;

  perform log_domain_event(v_estimate.organization_id, 'ESTIMATE_DECLINED', 'estimate', v_estimate.id,
    jsonb_build_object('estimate_version_id', p_estimate_version_id, 'reason', p_customer_note));
end;
$$;

revoke execute on function decline_estimate(uuid, text) from public, anon;
grant execute on function decline_estimate(uuid, text) to authenticated;
