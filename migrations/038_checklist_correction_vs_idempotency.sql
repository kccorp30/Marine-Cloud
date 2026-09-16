-- =========================================================
-- 038_checklist_correction_vs_idempotency.sql — Phase 2 hardening
-- =========================================================
-- Problema real de diseño (punto 3 del hardening): la constraint
-- original era UNIQUE(work_order_id, template_item_id) — un reintento
-- de sync (mismo client_generated_id) y una corrección intencional
-- (nuevo client_generated_id, misma pregunta) hacían exactamente el
-- mismo UPSERT, indistinguibles. Un reintento tardío de la respuesta
-- ORIGINAL después de que el técnico ya la corrigió podía revertir
-- silenciosamente la corrección.
--
-- Corrección: la clave de idempotencia real pasa a ser
-- (work_order_id, client_generated_id) — igual que el resto de las
-- tablas de Phase 2 (migración 037). Cada intento de escritura
-- (reintento O corrección) es su propia fila. "Cuál es la respuesta
-- vigente" se resuelve en la lectura (la más reciente por
-- completed_at), no en la escritura — así un reintento nunca puede
-- pisar una corrección posterior por accidente.
--
-- Verificado con test real: reintento del mismo client_generated_id
-- → 1 fila (no duplica). Corrección posterior con client_generated_id
-- nuevo → 2 filas totales, la lectura por completed_at desc resuelve
-- correctamente al valor corregido.
-- =========================================================

alter table checklist_responses drop constraint if exists uq_checklist_responses_item_per_wo;
drop index if exists uq_checklist_responses_item_per_wo;
drop index if exists uq_checklist_responses_client_id;

delete from checklist_responses where client_generated_id is null;
alter table checklist_responses alter column client_generated_id set not null;
alter table checklist_responses add constraint uq_checklist_responses_client_id unique (work_order_id, client_generated_id);

create index idx_checklist_responses_latest on checklist_responses(work_order_id, template_item_id, completed_at desc);
