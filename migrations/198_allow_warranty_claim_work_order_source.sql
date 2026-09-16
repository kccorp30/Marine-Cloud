-- =========================================================
-- 198_allow_warranty_claim_work_order_source.sql — Phase 13
-- =========================================================
-- BUG REAL: work_orders_source_check no incluía 'warranty_claim' —
-- create_corrective_work_order_from_claim() fallaba con un CHECK
-- violation real. Verificado corregido con datos reales.
-- =========================================================

alter table work_orders drop constraint work_orders_source_check;
alter table work_orders add constraint work_orders_source_check
  check (source = any (array['internal', 'website', 'referral', 'kcc_generated', 'other', 'warranty_claim']));
