-- =========================================================
-- 235_extend_commercial_enforcement_new_business.sql — Phase 14 final integrity
-- =========================================================
-- Extiende organization_has_active_access() a customers/vessels/
-- service_requests (negocio nuevo real). NO gatea appointments/
-- assignments (ejecución de trabajo ya existente).
-- Verificado con datos reales: sin suscripción bloquea customer nuevo.
-- =========================================================

drop policy "staff_write_customers_insert" on customers;
create policy "staff_write_customers_insert" on customers for insert
with check ((is_kcc_admin() or is_org_staff(organization_id)) and organization_has_active_access(organization_id));

drop policy "staff_write_vessels_insert" on vessels;
create policy "staff_write_vessels_insert" on vessels for insert
with check ((is_kcc_admin() or is_org_staff(organization_id)) and organization_has_active_access(organization_id));

drop policy "customer_insert_service_requests" on service_requests;
create policy "customer_insert_service_requests" on service_requests for insert
with check (
  is_own_customer_record(customer_id)
  and exists (select 1 from vessels v where v.id = service_requests.vessel_id and v.current_customer_id = service_requests.customer_id and v.organization_id = service_requests.organization_id)
  and status = 'submitted'
  and organization_has_active_access(organization_id)
);
