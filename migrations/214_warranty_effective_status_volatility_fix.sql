-- =========================================================
-- 214_warranty_effective_status_volatility_fix.sql — Phase 13 last correctness pass
-- =========================================================
-- BUG REAL: 213 declaró warranty_effective_status() como IMMUTABLE
-- pero depende de current_date — no es inmutable. Clasificación
-- correcta: STABLE. No se edita 213 retroactivamente.
-- Verificado con datos reales: ayer=expired, hoy=active,
-- mañana=active, voided se mantiene, ya no declarada IMMUTABLE.
-- =========================================================

create or replace function warranty_effective_status(p_status text, p_ends_at date)
returns text
language sql
stable
as $$
  select case
    when p_status = 'active' and p_ends_at is not null and p_ends_at < current_date then 'expired'
    else p_status
  end;
$$;
