-- =========================================================
-- 150_enforce_single_primary_location.sql — Phase 10 final fix
-- =========================================================
-- GAP REAL: no había invariante real de "una sola ubicación primaria
-- por organización" a nivel de base. Índice único parcial real, más
-- una función que cambia la primaria de forma atómica.
-- Verificado con datos reales: cambiar de Dock A a Dock B como
-- primaria deja exactamente una fila is_primary=true.
-- =========================================================

create unique index uq_organization_locations_one_primary on organization_locations(organization_id) where is_primary = true;

create or replace function set_primary_location(p_location_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loc organization_locations%rowtype;
begin
  select * into v_loc from organization_locations where id = p_location_id;
  if v_loc.id is null then
    raise exception 'location not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_loc.organization_id)) then
    raise exception 'not authorized to manage locations for this organization';
  end if;

  update organization_locations set is_primary = false, updated_at = now()
  where organization_id = v_loc.organization_id and is_primary = true and id != p_location_id;
  update organization_locations set is_primary = true, updated_at = now()
  where id = p_location_id;
end;
$$;

revoke execute on function set_primary_location(uuid) from public, anon;
grant execute on function set_primary_location(uuid) to authenticated;
