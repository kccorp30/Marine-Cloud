-- =========================================================
-- 074_money_input_constraints.sql — Phase 6 hardening
-- =========================================================
-- unit_price y tax permitían negativos — un descuento se representa
-- con line_type='discount' (la base ya calcula su valor absoluto al
-- recalcular subtotal/discount), nunca con un precio negativo.
-- Verificado: precio negativo de servicio/labor rechazado, tax
-- negativo rechazado, descuento válido sigue funcionando
-- ($200 - $30 = $170 exacto).
-- =========================================================

alter table estimate_line_items add constraint chk_unit_price_non_negative check (unit_price >= 0);
alter table estimate_versions add constraint chk_tax_non_negative check (tax >= 0);

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
  if p_unit_price < 0 then
    raise exception 'unit price cannot be negative — use line_type=discount for discounts';
  end if;

  insert into estimate_line_items (organization_id, estimate_version_id, service_catalog_id, line_type, description, quantity, unit_price, customer_visible, sort_order)
  values (v_version.organization_id, p_estimate_version_id, p_service_catalog_id, p_line_type, p_description, p_quantity, p_unit_price, p_customer_visible, p_sort_order)
  returning id into v_line_id;

  return v_line_id;
end;
$$;

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
  if p_unit_price is not null and p_unit_price < 0 then
    raise exception 'unit price cannot be negative — use line_type=discount for discounts';
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
  if p_tax is not null and p_tax < 0 then
    raise exception 'tax cannot be negative';
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
