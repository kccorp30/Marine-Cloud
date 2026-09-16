-- =========================================================
-- 028_fix_column_level_update_lock.sql
-- =========================================================
-- Bug real encontrado en TEST J durante el hardening: el REVOKE de
-- columna de la migración 019 nunca tuvo efecto. En Postgres, un
-- REVOKE de columna solo puede quitar un GRANT que se haya otorgado
-- específicamente a nivel de columna — NO puede recortar un GRANT
-- de tabla completa preexistente (Supabase otorga GRANT ALL de tabla
-- a `authenticated` por defecto en cada tabla nueva). El resultado:
-- current_status/closed_at eran editables directo desde el día uno
-- de Phase 1, aunque el diseño y la documentación decían lo contrario.
--
-- Corrección real: revocar el UPDATE de TABLA completa, y otorgar
-- UPDATE de vuelta solo en las columnas que sí deben ser editables
-- directo por staff (protegidas igual por la RLS policy de fila
-- existente). current_status y closed_at quedan FUERA de esa lista
-- a propósito — solo transition_work_order() (SECURITY DEFINER)
-- puede tocarlas.
-- =========================================================

revoke update on work_orders from authenticated;

grant update (title, description, priority, service_id) on work_orders to authenticated;

-- current_status, closed_at, organization_id, customer_id, vessel_id,
-- created_by, created_at quedan SIN grant de UPDATE directo para
-- authenticated — customer_id/vessel_id no tienen UI de reasignación
-- todavía (fuera de alcance de Phase 1), current_status/closed_at
-- solo vía la función de transición.
