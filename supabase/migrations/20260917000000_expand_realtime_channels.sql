-- =========================================================
-- 20260917000000_expand_realtime_channels.sql — Technician Mission
-- =========================================================
-- Item 7 del brief: work_orders ya estaba en la publicación de
-- Realtime, pero assignments/technician_locations/media_assets/
-- progress_updates/appointments/notifications NO — esto es un gap
-- real: si un dispatcher crea una asignación sin que el work order
-- cambie de status en el mismo momento, ni compañía ni customer ven
-- el nuevo técnico asignado sin refrescar a mano (item 8). Mismo
-- problema para fotos nuevas y ubicaciones de tracking.
--
-- ⚠️ NO APLICADA TODAVÍA — las herramientas de Supabase no estaban
-- disponibles en la sesión donde se escribió este archivo. Queda
-- guardada lista para aplicar en la próxima sesión con acceso real
-- a la base — nunca se debe asumir aplicada solo por existir el
-- archivo.
-- =========================================================

alter publication supabase_realtime add table assignments;
alter publication supabase_realtime add table technician_locations;
alter publication supabase_realtime add table media_assets;
alter publication supabase_realtime add table progress_updates;
alter publication supabase_realtime add table appointments;
alter publication supabase_realtime add table notifications;
