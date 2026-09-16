-- =========================================================
-- 246_extend_recipient_strategy_constraint.sql — Phase 14 absolute final closure
-- =========================================================
-- NO-OP idempotente: el trabajo real de esta migración se movió a
-- 245 (reescrita para ser autocontenida y replay-safe). Se conserva
-- este archivo en la secuencia numérica (nunca se renumeran
-- migraciones ya aplicadas), pero su contenido ahora es un no-op
-- seguro de re-correr — "if exists"/"or replace" en todo lo que toca,
-- así que aplicarla de nuevo sobre el estado ya correcto de 245 no
-- rompe nada.
-- =========================================================

alter table notification_rules drop constraint if exists notification_rules_recipient_strategy_check;
alter table notification_rules add constraint notification_rules_recipient_strategy_check
  check (recipient_strategy = any (array['org_staff', 'billing_admin', 'assigned_technician', 'customer', 'kcc_admin', 'requesting_technician']));
