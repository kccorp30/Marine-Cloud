-- =========================================================
-- 013_permission_matrix_rls.sql — Marine Cloud Phase 0
-- Políticas RLS completas para las tablas existentes, siguiendo el
-- Permission Matrix de Architecture v1.0.
--
-- DECISIÓN ARQUITECTÓNICA (corrección respecto al diseño original):
-- NO se usa current_organization_id() (variable de sesión de
-- Postgres) para nada de seguridad. Ese enfoque es frágil con
-- connection pooling (PgBouncer en modo transacción, que es como
-- Supabase sirve conexiones por defecto) — un SET no persiste de
-- forma confiable entre el navegador y las funciones server-side de
-- Next.js. La función sigue existiendo en el baseline por
-- compatibilidad histórica, pero está EN DESUSO — ninguna policy de
-- este archivo en adelante la usa.
--
-- Patrón real: toda policy verifica pertenencia real vía
-- organization_memberships + auth.uid() (confiable con pooling,
-- viene del JWT). La "organización activa" es un filtro de
-- aplicación (qué mostrás en la UI vía cookie), nunca un límite de
-- seguridad — ver lib/auth/active-org.ts y
-- tests/rls/phase0-rls-tests.sql (TEST 9) para la verificación de
-- que cambiar esa cookie no expone nada.
-- =========================================================

-- Helper: ¿el usuario actual es staff (owner/admin/manager) activo de
-- esa organización?
create or replace function is_org_staff(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from organization_memberships
    where profile_id = auth.uid()
      and organization_id = p_organization_id
      and status = 'active'
      and role in ('company_owner','company_admin','manager')
  );
$$;
revoke execute on function is_org_staff(uuid) from public;
grant execute on function is_org_staff(uuid) to authenticated;

create or replace function is_org_member(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from organization_memberships
    where profile_id = auth.uid()
      and organization_id = p_organization_id
      and status = 'active'
  );
$$;
revoke execute on function is_org_member(uuid) from public;
grant execute on function is_org_member(uuid) to authenticated;

-- ---------------------------------------------------------
-- organizations
-- ---------------------------------------------------------
create policy "read_own_org_or_kcc_admin" on organizations for select
  using (is_kcc_admin() or is_org_member(id));

create policy "kcc_admin_creates_orgs" on organizations for insert
  with check (is_kcc_admin());

create policy "staff_updates_own_org" on organizations for update
  using (is_kcc_admin() or is_org_staff(id));

-- Sin policy de DELETE — el borrado es siempre soft (deleted_at) vía UPDATE.

-- ---------------------------------------------------------
-- organization_locations
-- ---------------------------------------------------------
create policy "read_locations" on organization_locations for select
  using (is_kcc_admin() or is_org_member(organization_id));

create policy "staff_manage_locations_insert" on organization_locations for insert
  with check (is_kcc_admin() or is_org_staff(organization_id));

create policy "staff_manage_locations_update" on organization_locations for update
  using (is_kcc_admin() or is_org_staff(organization_id));

create policy "staff_manage_locations_delete" on organization_locations for delete
  using (is_kcc_admin() or is_org_staff(organization_id));

-- ---------------------------------------------------------
-- organization_settings
-- ---------------------------------------------------------
create policy "read_settings" on organization_settings for select
  using (is_kcc_admin() or is_org_member(organization_id));

create policy "staff_update_settings" on organization_settings for update
  using (is_kcc_admin() or is_org_staff(organization_id));

create policy "staff_insert_settings" on organization_settings for insert
  with check (is_kcc_admin() or is_org_staff(organization_id));

-- ---------------------------------------------------------
-- profiles — identidad personal, cruza organizaciones
-- ---------------------------------------------------------
create policy "read_own_profile" on profiles for select
  using (
    id = auth.uid()
    or is_kcc_admin()
    -- ver perfiles de personas que comparten al menos una organización activa contigo
    or exists (
      select 1 from organization_memberships m1
      join organization_memberships m2 on m1.organization_id = m2.organization_id
      where m1.profile_id = auth.uid() and m1.status = 'active'
        and m2.profile_id = profiles.id and m2.status = 'active'
    )
  );

create policy "update_own_profile" on profiles for update
  using (id = auth.uid() or is_kcc_admin());

-- Sin policy de INSERT — profiles se crea únicamente vía el trigger
-- handle_new_user() (SECURITY DEFINER), nunca directo por el cliente.

-- ---------------------------------------------------------
-- organization_memberships
-- ---------------------------------------------------------
create policy "read_memberships" on organization_memberships for select
  using (
    profile_id = auth.uid()
    or is_kcc_admin()
    or is_org_staff(organization_id)
  );

create policy "staff_create_memberships" on organization_memberships for insert
  with check (
    is_kcc_admin()
    or (is_org_staff(organization_id) and role <> 'kcc_admin')  -- staff nunca puede otorgarse a sí mismo o a otros el rol kcc_admin
  );

create policy "staff_update_memberships" on organization_memberships for update
  using (
    is_kcc_admin()
    or (is_org_staff(organization_id) and role <> 'kcc_admin')
  );

create policy "staff_delete_memberships" on organization_memberships for delete
  using (is_kcc_admin() or is_org_staff(organization_id));

-- ---------------------------------------------------------
-- technician_relationships
-- ---------------------------------------------------------
create policy "read_technician_relationships" on technician_relationships for select
  using (
    profile_id = auth.uid()
    or is_kcc_admin()
    or is_org_member(organization_id)  -- compañeros de la misma org pueden verse (necesario para asignación de trabajos)
  );

create policy "staff_manage_technicians_insert" on technician_relationships for insert
  with check (is_kcc_admin() or is_org_staff(organization_id));

create policy "staff_manage_technicians_update" on technician_relationships for update
  using (is_kcc_admin() or is_org_staff(organization_id) or profile_id = auth.uid());
  -- el propio técnico puede editar campos limitados (ej. sus skills) — el control fino de QUÉ campos se hace en la capa de aplicación, no en RLS

create policy "staff_manage_technicians_delete" on technician_relationships for delete
  using (is_kcc_admin() or is_org_staff(organization_id));

-- ---------------------------------------------------------
-- customer_relationships
-- ---------------------------------------------------------
create policy "read_customer_relationships" on customer_relationships for select
  using (
    profile_id = auth.uid()
    or is_kcc_admin()
    or is_org_member(organization_id)  -- incluye technician — necesario para ver de quién es el vessel en el que trabaja
  );

create policy "staff_manage_customers_insert" on customer_relationships for insert
  with check (is_kcc_admin() or is_org_staff(organization_id));

create policy "staff_manage_customers_update" on customer_relationships for update
  using (is_kcc_admin() or is_org_staff(organization_id));

create policy "staff_manage_customers_delete" on customer_relationships for delete
  using (is_kcc_admin() or is_org_staff(organization_id));
