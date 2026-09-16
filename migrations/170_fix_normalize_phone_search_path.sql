-- =========================================================
-- 170_fix_normalize_phone_search_path.sql — Phase 11
-- =========================================================
-- Hallazgo real del advisor: normalize_phone() sin search_path fijo.
-- =========================================================

create or replace function normalize_phone(p_phone text)
returns text
language sql
immutable
set search_path = public
as $$
  select nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');
$$;
