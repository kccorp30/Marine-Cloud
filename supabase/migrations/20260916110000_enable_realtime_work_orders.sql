-- =========================================================
-- 20260916110000_enable_realtime_work_orders.sql — Technician Mission
-- =========================================================
-- BRIEF: "No acepto 'funciona después de refrescar'." El mecanismo
-- anterior (TrackingAutoRefresh) era polling de 30s, documentado
-- como decisión deliberada pero insuficiente para lo que el brief
-- exige explícitamente. work_orders no estaba en la publicación de
-- Supabase Realtime — se agrega para permitir suscripción real vía
-- postgres_changes (RLS-aware, nunca bypasea políticas existentes).
-- =========================================================

alter publication supabase_realtime add table work_orders;
