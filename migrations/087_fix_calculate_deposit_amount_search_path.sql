-- =========================================================
-- 087_fix_calculate_deposit_amount_search_path.sql — Marine Cloud Phase 7
-- =========================================================
-- BUG REAL encontrado en el advisor de seguridad: calculate_deposit_
-- amount() no tenía search_path fijado (mutable), a diferencia de
-- toda otra función del proyecto. Corregido.
-- =========================================================

create or replace function calculate_deposit_amount(p_authorized_total numeric, p_deposit_type text, p_deposit_value numeric)
returns numeric
language sql
immutable
set search_path = public
as $$
  select case
    when p_deposit_type = 'percentage' then round(p_authorized_total * p_deposit_value / 100.0, 2)
    else least(p_deposit_value, p_authorized_total)
  end;
$$;
