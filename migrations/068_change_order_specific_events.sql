-- =========================================================
-- 068_change_order_specific_events.sql — Marine Cloud Phase 6
-- =========================================================
-- BUG REAL encontrado justo después de construir change orders:
-- send_estimate/approve_estimate/decline_estimate emitían siempre
-- ESTIMATE_SENT/APPROVED/DECLINED, incluso cuando la fila era en
-- realidad un change_order. Se corrige para que el evento emitido
-- dependa de estimates.type. También: solo la estimate ORIGINAL (no
-- un change order) dispara la transición inicial de
-- awaiting_approval -> scheduled — un change order aprobado no debe
-- re-disparar esa transición.
-- =========================================================

create or replace function send_estimate(p_estimate_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estimate estimates%rowtype;
  v_version estimate_versions%rowtype;
  v_line_count int;
  v_event_type text;
begin
  select * into v_estimate from estimates where id = p_estimate_id for update;
  if v_estimate.id is null then
    raise exception 'estimate not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_estimate.organization_id)) then
    raise exception 'not authorized';
  end if;

  select * into v_version from estimate_versions where id = v_estimate.current_version_id for update;
  if v_version.status != 'draft' then
    raise exception 'current version is not a draft (status: %)', v_version.status;
  end if;

  select count(*) into v_line_count from estimate_line_items where estimate_version_id = v_version.id;
  if v_line_count = 0 then
    raise exception 'cannot send an estimate with no line items';
  end if;

  update estimate_versions set status = 'sent', sent_at = now() where id = v_version.id;
  update estimates set status = 'sent', updated_at = now() where id = p_estimate_id;

  v_event_type := case when v_estimate.type = 'change_order' then 'CHANGE_ORDER_SENT' else 'ESTIMATE_SENT' end;
  perform log_domain_event(v_estimate.organization_id, v_event_type, 'estimate', p_estimate_id,
    jsonb_build_object('estimate_version_id', v_version.id, 'total', v_version.total));
  perform log_audit_event(v_estimate.organization_id, 'estimate', p_estimate_id, 'estimate_sent',
    jsonb_build_object('version', v_version.version_number), jsonb_build_object('total', v_version.total));
end;
$$;

create or replace function approve_estimate(p_estimate_version_id uuid, p_customer_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version estimate_versions%rowtype;
  v_estimate estimates%rowtype;
  v_event_type text;
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

  if v_estimate.type = 'estimate' and v_estimate.work_order_id is not null then
    if (select current_status from work_orders where id = v_estimate.work_order_id) = 'awaiting_approval' then
      perform transition_work_order(v_estimate.work_order_id, 'scheduled');
    end if;
  end if;

  v_event_type := case when v_estimate.type = 'change_order' then 'CHANGE_ORDER_APPROVED' else 'ESTIMATE_APPROVED' end;
  perform log_domain_event(v_estimate.organization_id, v_event_type, 'estimate', v_estimate.id,
    jsonb_build_object('estimate_version_id', p_estimate_version_id, 'total', v_version.total));
end;
$$;

create or replace function decline_estimate(p_estimate_version_id uuid, p_customer_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version estimate_versions%rowtype;
  v_estimate estimates%rowtype;
  v_event_type text;
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

  if v_estimate.type = 'estimate' and v_estimate.work_order_id is not null then
    if (select current_status from work_orders where id = v_estimate.work_order_id) = 'awaiting_approval' then
      perform transition_work_order(v_estimate.work_order_id, 'cancelled');
    end if;
  end if;

  v_event_type := case when v_estimate.type = 'change_order' then 'CHANGE_ORDER_DECLINED' else 'ESTIMATE_DECLINED' end;
  perform log_domain_event(v_estimate.organization_id, v_event_type, 'estimate', v_estimate.id,
    jsonb_build_object('estimate_version_id', p_estimate_version_id, 'reason', p_customer_note));
end;
$$;
