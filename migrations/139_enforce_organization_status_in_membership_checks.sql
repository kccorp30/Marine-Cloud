-- =========================================================
-- 139_enforce_organization_status_in_membership_checks.sql — Phase 10
-- =========================================================
-- GAP REAL: is_org_member()/is_org_staff() nunca consideraban
-- organizations.status — suspender una organización no habría tenido
-- ningún efecto real de acceso en ninguna policy RLS de todo el
-- proyecto. Se extienden acá — cascada automática, sin tocar cada
-- policy individual. kcc_admin nunca pasa por este chequeo — retiene
-- acceso administrativo incluso a una organización suspendida.
-- Verificado con datos reales: org activa sin cambios (regresión),
-- org suspendida bloquea acceso operativo normal, kcc_admin retiene
-- acceso.
-- =========================================================

create or replace function is_org_member(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1 from organization_memberships om
    join organizations o on o.id = om.organization_id
    where om.profile_id = auth.uid()
      and om.organization_id = p_organization_id
      and om.status = 'active'
      and o.status = 'active'
  );
$function$;

create or replace function is_org_staff(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1 from organization_memberships om
    join organizations o on o.id = om.organization_id
    where om.profile_id = auth.uid()
      and om.organization_id = p_organization_id
      and om.status = 'active'
      and om.role in ('company_owner','company_admin','manager')
      and o.status = 'active'
  );
$function$;
