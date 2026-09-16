-- =========================================================
-- 184_enable_realtime_technician_locations.sql — Phase 12 final fix
-- =========================================================
-- BUG REAL: TrackingStatusPanel se suscribía a postgres_changes
-- INSERT sobre technician_locations, pero la tabla nunca se agregó a
-- la publicación supabase_realtime — la suscripción nunca disparaba,
-- dependiendo silenciosamente del fallback de polling de 30s.
-- Verificado: la tabla ahora aparece en pg_publication_tables.
-- =========================================================

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'technician_locations'
  ) then
    alter publication supabase_realtime add table technician_locations;
  end if;
end $$;
