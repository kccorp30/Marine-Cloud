-- =========================================================
-- 209_allow_marine_cloud_work_order_source.sql — Phase 13 final integrity
-- =========================================================
-- BUG REAL PREEXISTENTE descubierto por regresión: service_requests.
-- source puede ser 'marine_cloud' (envío in-app) — nunca se había
-- agregado a work_orders_source_check. Cualquier conversión de un
-- service_request in-app a work order fallaba con una violación de
-- CHECK real. Verificado corregido con datos reales.
-- =========================================================

alter table work_orders drop constraint work_orders_source_check;
alter table work_orders add constraint work_orders_source_check
  check (source = any (array['internal', 'website', 'referral', 'kcc_generated', 'other', 'warranty_claim', 'marine_cloud']));
