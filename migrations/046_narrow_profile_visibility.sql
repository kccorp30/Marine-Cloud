-- =========================================================
-- 046_narrow_profile_visibility.sql — Marine Cloud Phase 3B hardening
-- =========================================================
-- La migración 044 corrigió el bug de RLS anidada, pero con un
-- alcance DEMASIADO amplio: cualquier miembro activo de una
-- organización podía leer el `profiles` completo (full_name, phone,
-- email, avatar_url) de cualquier otro miembro de esa misma
-- organización — un customer nunca necesita eso, solo necesita
-- nombre/avatar del técnico asignado a SU work order específico.
--
-- Modelo final:
-- 1. Cada quien lee su propio profile.
-- 2. kcc_admin lee cualquiera.
-- 3. STAFF (company_owner/company_admin/manager) sigue pudiendo leer
--    perfiles de su organización — lo necesitan para operar.
-- 4. Technician YA NO puede leer el perfil de otro technician/customer
--    solo por compartir organización.
-- 5. Customer NO tiene ningún SELECT directo de más sobre `profiles`
--    — accede al nombre/avatar del técnico asignado SOLO a través de
--    una función que expone exclusivamente esos dos campos.
--
-- Verificado con tests adversariales reales: customer lee nombre/
-- avatar del técnico asignado vía la función, NO puede leer el
-- profiles crudo por ningún camino directo, la función rechaza un
-- work order que no es del customer, y staff/technician siguen
-- funcionando sin regresión.
-- =========================================================

drop policy if exists "read_own_profile" on profiles;

create or replace function can_staff_view_profile(target_profile_id uuid)
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
      and m1.role in ('company_owner', 'company_admin', 'manager')
      and m2.profile_id = target_profile_id and m2.status = 'active'
  );
$$;

revoke execute on function can_staff_view_profile(uuid) from public, anon;
grant execute on function can_staff_view_profile(uuid) to authenticated;

create policy "read_own_profile" on profiles for select
using (
  id = auth.uid()
  or is_kcc_admin()
  or can_staff_view_profile(id)
);

drop function if exists shares_active_organization_with(uuid);

create or replace function get_assigned_technician_public_info(p_work_order_id uuid)
returns table(full_name text, avatar_url text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select organization_id into v_org_id from work_orders where id = p_work_order_id;
  if v_org_id is null then
    raise exception 'work order not found';
  end if;

  if not (
    is_kcc_admin()
    or is_org_staff(v_org_id)
    or is_customer_of_work_order(p_work_order_id)
    or is_assigned_to_work_order(p_work_order_id)
  ) then
    raise exception 'not authorized';
  end if;

  return query
  select p.full_name, p.avatar_url
  from assignments a
  join profiles p on p.id = a.technician_profile_id
  where a.work_order_id = p_work_order_id and a.status = 'active'
  order by a.assigned_at desc
  limit 1;
end;
$$;

revoke execute on function get_assigned_technician_public_info(uuid) from public, anon;
grant execute on function get_assigned_technician_public_info(uuid) to authenticated;
