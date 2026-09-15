-- =========================================================
-- 153_location_edit_and_deactivate.sql — Phase 10 final closure
-- =========================================================
-- Reusa organization_locations.deleted_at (ya existente) — nunca
-- hard-delete, nunca columna nueva competidora. La primaria no puede
-- desactivarse sin que otra location activa pase a ser primaria
-- primero (atómico).
-- Verificado con datos reales: editar campos funciona, desactivar la
-- primaria promueve la nueva atómicamente, exactamente una primaria
-- se mantiene siempre.
-- =========================================================

create or replace function edit_location(
  p_location_id uuid,
  p_name text default null,
  p_address text default null,
  p_marina_name text default null
)
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

  update organization_locations set
    name = coalesce(p_name, name),
    address = coalesce(p_address, address),
    marina_name = coalesce(p_marina_name, marina_name),
    updated_at = now()
  where id = p_location_id;
end;
$$;

revoke execute on function edit_location(uuid, text, text, text) from public, anon;
grant execute on function edit_location(uuid, text, text, text) to authenticated;

create or replace function deactivate_location(p_location_id uuid, p_new_primary_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loc organization_locations%rowtype;
begin
  select * into v_loc from organization_locations where id = p_location_id and deleted_at is null;
  if v_loc.id is null then
    raise exception 'location not found or already inactive';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_loc.organization_id)) then
    raise exception 'not authorized to manage locations for this organization';
  end if;

  if v_loc.is_primary then
    if p_new_primary_id is null then
      raise exception 'cannot deactivate the primary location without designating a new primary — pass p_new_primary_id';
    end if;
    if not exists (select 1 from organization_locations where id = p_new_primary_id and organization_id = v_loc.organization_id and deleted_at is null and id != p_location_id) then
      raise exception 'the designated new primary location does not exist or is not active';
    end if;
    update organization_locations set is_primary = false, updated_at = now() where id = p_location_id;
    update organization_locations set is_primary = true, updated_at = now() where id = p_new_primary_id;
  end if;

  update organization_locations set deleted_at = now(), is_primary = false, updated_at = now() where id = p_location_id;
end;
$$;

revoke execute on function deactivate_location(uuid, uuid) from public, anon;
grant execute on function deactivate_location(uuid, uuid) to authenticated;

drop policy if exists "read_locations" on organization_locations;
create policy "read_locations" on organization_locations for select
using (
  (is_kcc_admin() or is_org_staff(organization_id) or is_org_member(organization_id))
  and deleted_at is null
);
