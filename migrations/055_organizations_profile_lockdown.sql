-- =========================================================
-- 055_organizations_profile_lockdown.sql — Marine Cloud Phase 5
-- =========================================================
-- BUG REAL encontrado revisando el schema para Company Settings: la
-- policy staff_updates_own_org tiene with_check NULL — Postgres la
-- reusa igual al qual (is_org_staff(id)), lo que en la práctica deja
-- a CUALQUIER staff de la organización tocar TODAS las columnas,
-- incluidas slug (identidad de tenant), status (palanca de nivel
-- KCC), created_by, deleted_at.
--
-- Fix: mismo patrón column-lock de Phase 4B — se revoca UPDATE
-- directo, y una función SECURITY DEFINER expone solo los campos de
-- perfil seguros (name, phone, email). Verificado: slug/status
-- intactos tras usar la función.
-- =========================================================

alter table organizations add column if not exists phone text;
alter table organizations add column if not exists email text;

drop policy if exists "staff_updates_own_org" on organizations;
revoke update on organizations from authenticated;

create or replace function update_company_profile(
  p_organization_id uuid,
  p_name text default null,
  p_phone text default null,
  p_email text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (is_kcc_admin() or is_org_staff(p_organization_id)) then
    raise exception 'not authorized';
  end if;

  update organizations
  set
    name = coalesce(p_name, name),
    phone = coalesce(p_phone, phone),
    email = coalesce(p_email, email),
    updated_at = now()
  where id = p_organization_id;
end;
$$;

revoke execute on function update_company_profile(uuid, text, text, text) from public, anon;
grant execute on function update_company_profile(uuid, text, text, text) to authenticated;
