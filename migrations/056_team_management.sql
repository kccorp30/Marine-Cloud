-- =========================================================
-- 056_team_management.sql — Marine Cloud Phase 5
-- =========================================================
-- Jerarquía de permisos de equipo:
--   company_owner  -> invita/cambia rol a company_owner, company_admin,
--                     manager, technician
--   company_admin  -> invita/cambia rol SOLO a manager, technician
--   manager        -> sin escritura sobre equipo
--   kcc_admin      -> bypass total
-- Nadie puede asignar kcc_admin vía estas funciones.
--
-- NOTA (hardening): esta migración originalmente se aplicó con dos
-- bugs (nombre de enum incorrecto, digest()/gen_random_bytes() sin
-- calificar de schema) que se corrigieron en 057/058 — este archivo
-- ya incluye esas correcciones directamente, para que una base nueva
-- pueda correr la cadena completa sin pasar por el estado intermedio
-- roto. 057/058 quedan como no-ops idempotentes (ver esos archivos).
-- =========================================================

create table organization_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  email text not null,
  intended_role text not null check (intended_role in ('company_owner', 'company_admin', 'manager', 'technician')),
  token_hash text not null,
  invited_by uuid not null references profiles(id),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'revoked', 'expired')),
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_by uuid references profiles(id),
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint uq_org_invitations_token unique (token_hash)
);

create index idx_org_invitations_org_status on organization_invitations(organization_id, status);
create index idx_org_invitations_email on organization_invitations(email);

alter table organization_invitations enable row level security;

create policy "read_own_org_invitations" on organization_invitations for select
using (
  is_kcc_admin()
  or exists (
    select 1 from organization_memberships m
    where m.organization_id = organization_invitations.organization_id
      and m.profile_id = auth.uid() and m.status = 'active'
      and m.role in ('company_owner', 'company_admin')
  )
);

revoke all on organization_invitations from anon, authenticated;
grant select on organization_invitations to authenticated;

create or replace function get_actor_role_in_org(p_organization_id uuid)
returns text
language sql
security definer
set search_path = public
stable
as $$
  select role::text from organization_memberships
  where organization_id = p_organization_id and profile_id = auth.uid() and status = 'active'
  limit 1;
$$;

revoke execute on function get_actor_role_in_org(uuid) from public, anon;
grant execute on function get_actor_role_in_org(uuid) to authenticated;

create or replace function invite_team_member(p_organization_id uuid, p_email text, p_intended_role text)
returns table(invitation_id uuid, raw_token text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_role text;
  v_token text;
  v_id uuid;
begin
  v_actor_role := get_actor_role_in_org(p_organization_id);

  if not (is_kcc_admin() or v_actor_role in ('company_owner', 'company_admin')) then
    raise exception 'not authorized to invite team members';
  end if;

  if p_intended_role = 'kcc_admin' then
    raise exception 'cannot invite kcc_admin';
  end if;

  if v_actor_role = 'company_admin' and p_intended_role in ('company_owner', 'company_admin') then
    raise exception 'company_admin cannot invite role %', p_intended_role;
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into organization_invitations (organization_id, email, intended_role, token_hash, invited_by)
  values (p_organization_id, lower(trim(p_email)), p_intended_role, encode(extensions.digest(v_token, 'sha256'), 'hex'), auth.uid())
  returning id into v_id;

  perform log_domain_event(p_organization_id, 'TEAM_MEMBER_INVITED', 'organization_invitation', v_id,
    jsonb_build_object('email', p_email, 'intended_role', p_intended_role));

  return query select v_id, v_token;
end;
$$;

revoke execute on function invite_team_member(uuid, text, text) from public, anon;
grant execute on function invite_team_member(uuid, text, text) to authenticated;

create or replace function revoke_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv organization_invitations%rowtype;
  v_actor_role text;
begin
  select * into v_inv from organization_invitations where id = p_invitation_id for update;
  if v_inv.id is null then
    raise exception 'invitation not found';
  end if;
  v_actor_role := get_actor_role_in_org(v_inv.organization_id);
  if not (is_kcc_admin() or v_actor_role in ('company_owner', 'company_admin')) then
    raise exception 'not authorized';
  end if;
  if v_inv.status != 'pending' then
    raise exception 'invitation cannot be revoked from status %', v_inv.status;
  end if;

  update organization_invitations set status = 'revoked', updated_at = now() where id = p_invitation_id;
end;
$$;

revoke execute on function revoke_invitation(uuid) from public, anon;
grant execute on function revoke_invitation(uuid) to authenticated;

-- accept_invitation se define completa acá (con verificación de
-- identidad por email) — ver 060 para el hardening que la agregó; se
-- mantiene simple acá (sin esa verificación) porque 060 la reemplaza
-- por completo más adelante en la cadena, y así este archivo refleja
-- lo mínimo necesario para que 057-059 tengan algo sobre lo que
-- aplicar sus CREATE OR REPLACE sin error.
create or replace function accept_invitation(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv organization_invitations%rowtype;
  v_existing_id uuid;
begin
  select * into v_inv from organization_invitations
  where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') for update;

  if v_inv.id is null then
    raise exception 'invalid invitation token';
  end if;
  if v_inv.status != 'pending' then
    raise exception 'invitation is no longer valid (%)', v_inv.status;
  end if;
  if v_inv.expires_at < now() then
    update organization_invitations set status = 'expired', updated_at = now() where id = v_inv.id;
    raise exception 'invitation has expired';
  end if;

  select id into v_existing_id from organization_memberships
  where profile_id = auth.uid() and organization_id = v_inv.organization_id
  limit 1;

  if v_existing_id is not null then
    update organization_memberships
    set role = v_inv.intended_role::membership_role, status = 'active', updated_at = now()
    where id = v_existing_id;
  else
    insert into organization_memberships (profile_id, organization_id, role, status)
    values (auth.uid(), v_inv.organization_id, v_inv.intended_role::membership_role, 'active');
  end if;

  update organization_invitations set status = 'accepted', accepted_by = auth.uid(), accepted_at = now(), updated_at = now() where id = v_inv.id;

  return v_inv.organization_id;
end;
$$;

revoke execute on function accept_invitation(text) from public, anon;
grant execute on function accept_invitation(text) to authenticated;

create or replace function change_member_role(p_membership_id uuid, p_new_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_membership organization_memberships%rowtype;
  v_actor_role text;
  v_owner_count int;
begin
  select * into v_membership from organization_memberships where id = p_membership_id for update;
  if v_membership.id is null then
    raise exception 'membership not found';
  end if;

  v_actor_role := get_actor_role_in_org(v_membership.organization_id);
  if not (is_kcc_admin() or v_actor_role in ('company_owner', 'company_admin')) then
    raise exception 'not authorized';
  end if;

  if p_new_role = 'kcc_admin' then
    raise exception 'cannot assign kcc_admin';
  end if;

  if v_actor_role = 'company_admin' and (p_new_role in ('company_owner', 'company_admin') or v_membership.role::text in ('company_owner', 'company_admin')) then
    raise exception 'company_admin cannot modify owner/admin-level roles';
  end if;

  if v_membership.profile_id = auth.uid() and not is_kcc_admin() then
    raise exception 'cannot change your own role';
  end if;

  if v_membership.role::text = 'company_owner' and p_new_role != 'company_owner' then
    select count(*) into v_owner_count from organization_memberships
    where organization_id = v_membership.organization_id and role = 'company_owner' and status = 'active' and id != p_membership_id;
    if v_owner_count = 0 then
      raise exception 'organization must retain at least one active company_owner';
    end if;
  end if;

  update organization_memberships set role = p_new_role::membership_role, updated_at = now() where id = p_membership_id;

  perform log_domain_event(v_membership.organization_id, 'TEAM_MEMBER_ROLE_CHANGED', 'organization_membership', p_membership_id,
    jsonb_build_object('from_role', v_membership.role, 'to_role', p_new_role));
end;
$$;

revoke execute on function change_member_role(uuid, text) from public, anon;
grant execute on function change_member_role(uuid, text) to authenticated;

create or replace function deactivate_team_member(p_membership_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_membership organization_memberships%rowtype;
  v_actor_role text;
  v_owner_count int;
begin
  select * into v_membership from organization_memberships where id = p_membership_id for update;
  if v_membership.id is null then
    raise exception 'membership not found';
  end if;

  v_actor_role := get_actor_role_in_org(v_membership.organization_id);
  if not (is_kcc_admin() or v_actor_role in ('company_owner', 'company_admin')) then
    raise exception 'not authorized';
  end if;

  if v_actor_role = 'company_admin' and v_membership.role in ('company_owner', 'company_admin') then
    raise exception 'company_admin cannot deactivate owner/admin-level members';
  end if;

  if v_membership.profile_id = auth.uid() and not is_kcc_admin() then
    raise exception 'cannot deactivate your own membership';
  end if;

  if v_membership.role = 'company_owner' then
    select count(*) into v_owner_count from organization_memberships
    where organization_id = v_membership.organization_id and role = 'company_owner' and status = 'active' and id != p_membership_id;
    if v_owner_count = 0 then
      raise exception 'organization must retain at least one active company_owner';
    end if;
  end if;

  update organization_memberships set status = 'inactive', updated_at = now() where id = p_membership_id;

  perform log_domain_event(v_membership.organization_id, 'TEAM_MEMBER_DEACTIVATED', 'organization_membership', p_membership_id, '{}'::jsonb);
end;
$$;

revoke execute on function deactivate_team_member(uuid) from public, anon;
grant execute on function deactivate_team_member(uuid) to authenticated;
