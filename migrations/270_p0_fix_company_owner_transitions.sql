-- =========================================================
-- 270_p0_fix_company_owner_transitions.sql — Go-Live P0 fix
-- =========================================================
-- P0 REAL: company_owner faltaba en 23 de 25 filas de
-- work_order_transition_rules que sí incluían company_admin/manager/
-- kcc_admin — el dueño de una compañía real (el operador más común
-- en una empresa pequeña, el perfil típico del primer cliente real)
-- no podía mover NINGÚN work order más allá de request_received.
-- Bloqueaba el flujo operacional central completo: triage, estimate,
-- aprobación, scheduling, QC, invoice, payment, completed.
-- Encontrado corriendo el escenario E2E real de intake->completado.
-- Corregido agregando company_owner en toda fila donde ya está
-- company_admin (mismo patrón de autoridad ya establecido en el
-- resto del proyecto).
-- Verificado con datos reales: owner condujo el pipeline completo
-- request_received -> triage -> estimate -> awaiting_approval ->
-- scheduled -> technician_assigned -> (técnico) en_route ->
-- checked_in -> diagnosis -> work_in_progress -> quality_control ->
-- invoice, con media subida y visible para el customer, y
-- aislamiento cross-tenant confirmado con una segunda organización.
-- =========================================================

update work_order_transition_rules
set allowed_roles = array_append(allowed_roles, 'company_owner')
where 'company_admin' = any(allowed_roles) and not ('company_owner' = any(allowed_roles));
