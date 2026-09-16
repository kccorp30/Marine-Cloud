-- =========================================================
-- 133_enable_realtime_notifications.sql — Marine Cloud Phase 9
-- =========================================================
-- Sin esto, el cliente nunca recibe postgres_changes. RLS ya protege
-- qué filas ve cada usuario incluso en la conexión realtime.
-- =========================================================

alter publication supabase_realtime add table notifications;
alter publication supabase_realtime add table kcc_assistance_requests;
