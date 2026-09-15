-- =========================================================
-- 043_domain_events_work_order_fk.sql — Marine Cloud Phase 3B
-- =========================================================
-- FK compuesta real (work_order_id, organization_id) → work_orders
-- (id, organization_id) — reusa la unique constraint que ya existe
-- desde la migración 025 (uq_work_orders_id_org), sin crear un índice
-- único redundante. Columnas NULL (eventos a nivel vessel/customer)
-- simplemente no se validan contra la FK — comportamiento estándar
-- de Postgres, no hace falta ninguna excepción especial.
--
-- Hace estructuralmente IMPOSIBLE que domain_events.work_order_id
-- apunte a un work order de otra organización. Verificado con un
-- insert adversarial real: rechazado con foreign_key_violation.
-- =========================================================

alter table domain_events
  add constraint fk_domain_events_work_order_same_org
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id);
