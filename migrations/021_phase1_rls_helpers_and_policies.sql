-- =========================================================
-- 021_phase1_rls_helpers_and_policies.sql — Marine Cloud Phase 1
-- =========================================================

create or replace function is_assigned_to_work_order(p_work_order_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from assignments
    where work_order_id = p_work_order_id
      and technician_profile_id = auth.uid()
      and status = 'active'
  );
$$;
revoke execute on function is_assigned_to_work_order(uuid) from public, anon;
grant execute on function is_assigned_to_work_order(uuid) to authenticated;

create or replace function is_customer_of_work_order(p_work_order_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from work_orders wo
    join customers c on c.id = wo.customer_id
    where wo.id = p_work_order_id and c.profile_id = auth.uid()
  );
$$;
revoke execute on function is_customer_of_work_order(uuid) from public, anon;
grant execute on function is_customer_of_work_order(uuid) to authenticated;

create or replace function is_own_customer_record(p_customer_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from customers where id = p_customer_id and profile_id = auth.uid());
$$;
revoke execute on function is_own_customer_record(uuid) from public, anon;
grant execute on function is_own_customer_record(uuid) to authenticated;

-- ---------------------------------------------------------
-- customers
-- ---------------------------------------------------------
create policy "read_customers" on customers for select
  using (
    is_kcc_admin()
    or is_org_staff(organization_id)
    or profile_id = auth.uid()
    or exists (
      select 1 from work_orders wo
      where wo.customer_id = customers.id and is_assigned_to_work_order(wo.id)
    )
  );

create policy "staff_write_customers_insert" on customers for insert
  with check (is_kcc_admin() or is_org_staff(organization_id));
create policy "staff_write_customers_update" on customers for update
  using (is_kcc_admin() or is_org_staff(organization_id));
create policy "staff_write_customers_delete" on customers for delete
  using (is_kcc_admin() or is_org_staff(organization_id));

-- ---------------------------------------------------------
-- vessels
-- ---------------------------------------------------------
create policy "read_vessels" on vessels for select
  using (
    is_kcc_admin()
    or is_org_staff(organization_id)
    or is_own_customer_record(current_customer_id)
    or exists (
      select 1 from work_orders wo
      where wo.vessel_id = vessels.id and is_assigned_to_work_order(wo.id)
    )
  );

create policy "staff_write_vessels_insert" on vessels for insert
  with check (is_kcc_admin() or is_org_staff(organization_id));
create policy "staff_write_vessels_update" on vessels for update
  using (is_kcc_admin() or is_org_staff(organization_id));
create policy "staff_write_vessels_delete" on vessels for delete
  using (is_kcc_admin() or is_org_staff(organization_id));

-- ---------------------------------------------------------
-- vessel_ownership_history — administrativo, staff + kcc_admin
-- ---------------------------------------------------------
create policy "staff_read_ownership_history" on vessel_ownership_history for select
  using (is_kcc_admin() or is_org_staff(organization_id));
create policy "staff_write_ownership_history" on vessel_ownership_history for insert
  with check (is_kcc_admin() or is_org_staff(organization_id));
create policy "staff_update_ownership_history" on vessel_ownership_history for update
  using (is_kcc_admin() or is_org_staff(organization_id));

-- ---------------------------------------------------------
-- vessel_systems
-- ---------------------------------------------------------
create policy "read_vessel_systems" on vessel_systems for select
  using (
    is_kcc_admin()
    or is_org_staff(organization_id)
    or exists (
      select 1 from work_orders wo
      where wo.vessel_id = vessel_systems.vessel_id and is_assigned_to_work_order(wo.id)
    )
  );
create policy "staff_write_vessel_systems_insert" on vessel_systems for insert
  with check (is_kcc_admin() or is_org_staff(organization_id));
create policy "staff_write_vessel_systems_update" on vessel_systems for update
  using (is_kcc_admin() or is_org_staff(organization_id));
create policy "staff_write_vessel_systems_delete" on vessel_systems for delete
  using (is_kcc_admin() or is_org_staff(organization_id));

-- ---------------------------------------------------------
-- service_catalog — lectura abierta a cualquier miembro de la org
-- ---------------------------------------------------------
create policy "read_service_catalog" on service_catalog for select
  using (is_kcc_admin() or is_org_member(organization_id));
create policy "staff_write_service_catalog_insert" on service_catalog for insert
  with check (is_kcc_admin() or is_org_staff(organization_id));
create policy "staff_write_service_catalog_update" on service_catalog for update
  using (is_kcc_admin() or is_org_staff(organization_id));
create policy "staff_write_service_catalog_delete" on service_catalog for delete
  using (is_kcc_admin() or is_org_staff(organization_id));

-- ---------------------------------------------------------
-- work_orders
-- ---------------------------------------------------------
create policy "read_work_orders" on work_orders for select
  using (
    is_kcc_admin()
    or is_org_staff(organization_id)
    or is_assigned_to_work_order(id)
    or is_customer_of_work_order(id)
  );

create policy "staff_create_work_orders" on work_orders for insert
  with check (is_kcc_admin() or is_org_staff(organization_id));

create policy "staff_update_work_orders" on work_orders for update
  using (is_kcc_admin() or is_org_staff(organization_id));

-- ---------------------------------------------------------
-- work_order_status_history — solo lectura
-- ---------------------------------------------------------
create policy "read_status_history" on work_order_status_history for select
  using (
    is_kcc_admin()
    or is_org_staff(organization_id)
    or is_assigned_to_work_order(work_order_id)
    or is_customer_of_work_order(work_order_id)
  );

-- ---------------------------------------------------------
-- appointments
-- ---------------------------------------------------------
create policy "read_appointments" on appointments for select
  using (
    is_kcc_admin()
    or is_org_staff(organization_id)
    or is_assigned_to_work_order(work_order_id)
    or is_customer_of_work_order(work_order_id)
  );
create policy "staff_write_appointments_insert" on appointments for insert
  with check (is_kcc_admin() or is_org_staff(organization_id));
create policy "staff_write_appointments_update" on appointments for update
  using (is_kcc_admin() or is_org_staff(organization_id) or is_assigned_to_work_order(work_order_id));

-- ---------------------------------------------------------
-- assignments
-- ---------------------------------------------------------
create policy "read_assignments" on assignments for select
  using (
    is_kcc_admin()
    or is_org_staff(organization_id)
    or technician_profile_id = auth.uid()
    or is_assigned_to_work_order(work_order_id)
    or is_customer_of_work_order(work_order_id)
  );
create policy "staff_write_assignments_insert" on assignments for insert
  with check (is_kcc_admin() or is_org_staff(organization_id));
create policy "staff_write_assignments_update" on assignments for update
  using (is_kcc_admin() or is_org_staff(organization_id));
