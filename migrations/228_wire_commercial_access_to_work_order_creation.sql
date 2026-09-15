-- =========================================================
-- 228_wire_commercial_access_to_work_order_creation.sql — Marine Cloud Phase 14
-- =========================================================
-- El enforcement comercial NUNCA es decorativo — conectado directo a
-- la policy RLS de INSERT en work_orders, cubre todos los caminos
-- reales de creación de forma uniforme.
-- Verificado con datos reales: organización con suscripción cancelada
-- bloquea la creación de un work order nuevo; con suscripción activa
-- real (sin trial, sin fabricar pago) lo permite.
-- =========================================================

drop policy "staff_create_work_orders" on work_orders;
create policy "staff_create_work_orders" on work_orders for insert
with check ((is_kcc_admin() or is_org_staff(organization_id)) and organization_has_active_access(organization_id));
