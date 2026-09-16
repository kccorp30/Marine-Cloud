-- =========================================================
-- 213_warranty_effective_status.sql — Phase 13 true final closure
-- =========================================================
-- Sin cron, warranties.status podía quedar 'active' con ends_at ya
-- vencido. warranty_effective_status() es la ÚNICA fuente de verdad
-- de presentación — nunca se duplica la regla de fecha en cada
-- componente. Verificado con datos reales: futuro=active,
-- pasado+stored active=expired, voided se mantiene voided.
-- =========================================================

create or replace function warranty_effective_status(p_status text, p_ends_at date)
returns text
language sql
immutable
as $$
  select case
    when p_status = 'active' and p_ends_at is not null and p_ends_at < current_date then 'expired'
    else p_status
  end;
$$;
