-- =========================================================
-- 037_fix_client_generated_id_constraints.sql — Marine Cloud Phase 2
-- =========================================================
-- Bug real encontrado antes de probar: work_notes, measurements,
-- progress_updates y media_assets usan ON CONFLICT (work_order_id,
-- client_generated_id) desde el cliente (Supabase JS .upsert()), pero
-- el índice único original era PARCIAL (WHERE client_generated_id IS
-- NOT NULL) — Postgres no resuelve ON CONFLICT de forma confiable
-- contra un índice parcial solo por lista de columnas. Se corrige
-- haciendo la columna NOT NULL con un índice único NORMAL.
-- Verificado con un upsert real simulando reconexión: 1 fila, no 2.
-- =========================================================

delete from work_notes where client_generated_id is null;
alter table work_notes alter column client_generated_id set not null;
drop index if exists uq_work_notes_client_id;
alter table work_notes add constraint uq_work_notes_client_id unique (work_order_id, client_generated_id);

delete from measurements where client_generated_id is null;
alter table measurements alter column client_generated_id set not null;
drop index if exists uq_measurements_client_id;
alter table measurements add constraint uq_measurements_client_id unique (work_order_id, client_generated_id);

delete from progress_updates where client_generated_id is null;
alter table progress_updates alter column client_generated_id set not null;
drop index if exists uq_progress_updates_client_id;
alter table progress_updates add constraint uq_progress_updates_client_id unique (work_order_id, client_generated_id);

delete from media_assets where client_generated_id is null;
alter table media_assets alter column client_generated_id set not null;
drop index if exists uq_media_assets_client_id;
alter table media_assets add constraint uq_media_assets_client_id unique (work_order_id, client_generated_id);
