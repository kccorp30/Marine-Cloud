-- =========================================================
-- 064_estimate_draft_functions.sql — Marine Cloud Phase 6
-- =========================================================
-- Construcción del draft. Todo limitado a versiones en 'draft' — el
-- trigger de recálculo se niega a tocar una versión ya enviada, como
-- defensa en profundidad además del propio chequeo en cada función.
-- Verificado con datos reales: 2hrs*$125 + 1*$85.50 = $335.50
-- subtotal, descuento $20, tax $15 -> total $330.50, calculado
-- enteramente por la base, nunca confiado del cliente.
-- =========================================================

create or replace function recalculate_estimate_version_totals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version_id uuid;
  v_status text;
  v_subtotal numeric(12,2);
  v_discount numeric(12,2);
  v_tax numeric(12,2);
begin
  v_version_id := coalesce(new.estimate_version_id, old.estimate_version_id);
  select status, tax into v_status, v_tax from estimate_versions where id = v_version_id for update;

  if v_status != 'draft' then
    return coalesce(new, old);
  end if;

  select coalesce(sum(line_total) filter (where line_type != 'discount'), 0),
         coalesce(sum(abs(line_total)) filter (where line_type = 'discount'), 0)
  into v_subtotal, v_discount
  from estimate_line_items where estimate_version_id = v_version_id;

  update estimate_versions
  set subtotal = v_subtotal,
      discount = v_discount,
      total = greatest(round(v_subtotal - v_discount + coalesce(v_tax, 0), 2), 0)
  where id = v_version_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_recalculate_estimate_totals
  after insert or update or delete on estimate_line_items
  for each row execute function recalculate_estimate_version_totals();

revoke execute on function recalculate_estimate_version_totals() from public, anon, authenticated;

create or replace function create_draft_estimate(
  p_organization_id uuid,
  p_customer_id uuid,
  p_vessel_id uuid,
  p_work_order_id uuid default null,
  p_service_request_id uuid default null,
  p_title text default null,
  p_customer_message text default null,
  p_valid_until date default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estimate_id uuid;
  v_version_id uuid;
  v_currency text;
begin
  if not (is_kcc_admin() or is_org_staff(p_organization_id)) then
    raise exception 'not authorized to create estimates';
  end if;

  if not exists (select 1 from customers where id = p_customer_id and organization_id = p_organization_id) then
    raise exception 'customer does not belong to this organization';
  end if;
  if not exists (select 1 from vessels where id = p_vessel_id and organization_id = p_organization_id and current_customer_id = p_customer_id) then
    raise exception 'vessel does not belong to this customer/organization';
  end if;

  select currency into v_currency from organization_settings where organization_id = p_organization_id;
  v_currency := coalesce(v_currency, 'USD');

  insert into estimates (organization_id, customer_id, vessel_id, work_order_id, service_request_id, estimate_number, type, status, currency, created_by)
  values (p_organization_id, p_customer_id, p_vessel_id, p_work_order_id, p_service_request_id,
    generate_estimate_number(p_organization_id, 'estimate'), 'estimate', 'draft', v_currency, auth.uid())
  returning id into v_estimate_id;

  insert into estimate_versions (organization_id, estimate_id, version_number, status, title, customer_message, currency, valid_until, created_by)
  values (p_organization_id, v_estimate_id, 1, 'draft', p_title, p_customer_message, v_currency, p_valid_until, auth.uid())
  returning id into v_version_id;

  update estimates set current_version_id = v_version_id where id = v_estimate_id;

  perform log_domain_event(p_organization_id, 'ESTIMATE_CREATED', 'estimate', v_estimate_id,
    jsonb_build_object('estimate_number', (select estimate_number from estimates where id = v_estimate_id)));

  return v_estimate_id;
end;
$$;

revoke execute on function create_draft_estimate(uuid, uuid, uuid, uuid, uuid, text, text, date) from public, anon;
grant execute on function create_draft_estimate(uuid, uuid, uuid, uuid, uuid, text, text, date) to authenticated;

create or replace function add_estimate_line_item(
  p_estimate_version_id uuid,
  p_line_type text,
  p_description text,
  p_quantity numeric,
  p_unit_price numeric,
  p_service_catalog_id uuid default null,
  p_customer_visible boolean default true,
  p_sort_order int default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version estimate_versions%rowtype;
  v_line_id uuid;
begin
  select * into v_version from estimate_versions where id = p_estimate_version_id for update;
  if v_version.id is null then
    raise exception 'estimate version not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_version.organization_id)) then
    raise exception 'not authorized';
  end if;
  if v_version.status != 'draft' then
    raise exception 'cannot modify a version that is not draft (current status: %)', v_version.status;
  end if;

  insert into estimate_line_items (organization_id, estimate_version_id, service_catalog_id, line_type, description, quantity, unit_price, customer_visible, sort_order)
  values (v_version.organization_id, p_estimate_version_id, p_service_catalog_id, p_line_type, p_description, p_quantity, p_unit_price, p_customer_visible, p_sort_order)
  returning id into v_line_id;

  return v_line_id;
end;
$$;

revoke execute on function add_estimate_line_item(uuid, text, text, numeric, numeric, uuid, boolean, int) from public, anon;
grant execute on function add_estimate_line_item(uuid, text, text, numeric, numeric, uuid, boolean, int) to authenticated;

create or replace function update_estimate_line_item(
  p_line_item_id uuid,
  p_description text default null,
  p_quantity numeric default null,
  p_unit_price numeric default null,
  p_sort_order int default null,
  p_customer_visible boolean default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line estimate_line_items%rowtype;
  v_version estimate_versions%rowtype;
begin
  select * into v_line from estimate_line_items where id = p_line_item_id;
  if v_line.id is null then
    raise exception 'line item not found';
  end if;
  select * into v_version from estimate_versions where id = v_line.estimate_version_id for update;
  if not (is_kcc_admin() or is_org_staff(v_version.organization_id)) then
    raise exception 'not authorized';
  end if;
  if v_version.status != 'draft' then
    raise exception 'cannot modify a version that is not draft (current status: %)', v_version.status;
  end if;

  update estimate_line_items set
    description = coalesce(p_description, description),
    quantity = coalesce(p_quantity, quantity),
    unit_price = coalesce(p_unit_price, unit_price),
    sort_order = coalesce(p_sort_order, sort_order),
    customer_visible = coalesce(p_customer_visible, customer_visible)
  where id = p_line_item_id;
end;
$$;

revoke execute on function update_estimate_line_item(uuid, text, numeric, numeric, int, boolean) from public, anon;
grant execute on function update_estimate_line_item(uuid, text, numeric, numeric, int, boolean) to authenticated;

create or replace function remove_estimate_line_item(p_line_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line estimate_line_items%rowtype;
  v_version estimate_versions%rowtype;
begin
  select * into v_line from estimate_line_items where id = p_line_item_id;
  if v_line.id is null then
    raise exception 'line item not found';
  end if;
  select * into v_version from estimate_versions where id = v_line.estimate_version_id for update;
  if not (is_kcc_admin() or is_org_staff(v_version.organization_id)) then
    raise exception 'not authorized';
  end if;
  if v_version.status != 'draft' then
    raise exception 'cannot modify a version that is not draft (current status: %)', v_version.status;
  end if;

  delete from estimate_line_items where id = p_line_item_id;
end;
$$;

revoke execute on function remove_estimate_line_item(uuid) from public, anon;
grant execute on function remove_estimate_line_item(uuid) to authenticated;

create or replace function update_estimate_version_details(
  p_estimate_version_id uuid,
  p_title text default null,
  p_customer_message text default null,
  p_tax numeric default null,
  p_valid_until date default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version estimate_versions%rowtype;
begin
  select * into v_version from estimate_versions where id = p_estimate_version_id for update;
  if v_version.id is null then
    raise exception 'estimate version not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_version.organization_id)) then
    raise exception 'not authorized';
  end if;
  if v_version.status != 'draft' then
    raise exception 'cannot modify a version that is not draft (current status: %)', v_version.status;
  end if;

  update estimate_versions set
    title = coalesce(p_title, title),
    customer_message = coalesce(p_customer_message, customer_message),
    tax = coalesce(p_tax, tax),
    valid_until = coalesce(p_valid_until, valid_until)
  where id = p_estimate_version_id;

  update estimate_versions ev
  set total = greatest(round(ev.subtotal - ev.discount + ev.tax, 2), 0)
  where ev.id = p_estimate_version_id;
end;
$$;

revoke execute on function update_estimate_version_details(uuid, text, text, numeric, date) from public, anon;
grant execute on function update_estimate_version_details(uuid, text, text, numeric, date) to authenticated;
