-- =========================================================
-- 044_fix_profiles_read_nested_rls_bug.sql — Marine Cloud Phase 3B
-- =========================================================
-- BUG REAL encontrado construyendo el tracking del customer (no
-- introducido ahora, existía desde Phase 0): la policy
-- read_own_profile de `profiles` decide con una subquery cruda sobre
-- organization_memberships — pero esa tabla tiene SU PROPIA RLS
-- (read_memberships: cada uno ve solo su propia fila, salvo
-- staff/kcc_admin). Un customer nunca es staff, así que la subquery
-- nunca puede ver la fila de membership del técnico, y la condición
-- "compartimos organización" da falso siempre para roles no-staff —
-- aunque la lógica pretendida fuera permitirlo. Mismo patrón de bug
-- que ya se corrigió antes con is_org_member()/is_org_staff() (RLS
-- anidada silenciosamente más restrictiva de lo que el autor de la
-- policy asumía).
--
-- Verificado: un customer ahora sí lee el nombre de su técnico
-- asignado, y NO puede leer el perfil de alguien de una organización
-- completamente distinta (probado con un usuario real sin ninguna
-- organización en común).
-- =========================================================

create or replace function shares_active_organization_with(target_profile_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from organization_memberships m1
    join organization_memberships m2 on m1.organization_id = m2.organization_id
    where m1.profile_id = auth.uid() and m1.status = 'active'
      and m2.profile_id = target_profile_id and m2.status = 'active'
  );
$$;

revoke execute on function shares_active_organization_with(uuid) from public;
grant execute on function shares_active_organization_with(uuid) to authenticated;

drop policy if exists "read_own_profile" on profiles;

create policy "read_own_profile" on profiles for select
using (
  id = auth.uid()
  or is_kcc_admin()
  or shares_active_organization_with(id)
);
