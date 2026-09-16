-- =========================================================
-- 273_password_credentials_and_customer_invites.sql
-- Credential-state + customer invitation hardening
-- =========================================================

-- Tracks whether the account has successfully established/used a password.
-- This is UX/auth-flow state only; Supabase Auth remains the authority that
-- validates the actual credential.
alter table profiles add column if not exists password_set_at timestamptz;

-- Customer portal users use the same invitation lifecycle as staff.
alter table organization_invitations
  drop constraint if exists organization_invitations_intended_role_check;

alter table organization_invitations
  add constraint organization_invitations_intended_role_check
  check (intended_role in ('company_owner', 'company_admin', 'manager', 'technician', 'customer'));

-- Normalize historical duplicate pending invitations before enforcing one
-- live invitation per role/email/workspace.
with ranked as (
  select id,
         row_number() over (
           partition by organization_id, lower(email), intended_role
           order by created_at desc, id desc
         ) as rn
  from organization_invitations
  where status = 'pending'
)
update organization_invitations i
set status = 'revoked', updated_at = now()
from ranked r
where i.id = r.id and r.rn > 1;

create unique index if not exists uq_org_pending_invitation_identity
  on organization_invitations (organization_id, lower(email), intended_role)
  where status = 'pending';

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
  v_email text;
  v_existing organization_invitations%rowtype;
begin
  v_actor_role := get_actor_role_in_org(p_organization_id);
  v_email := lower(trim(p_email));

  if not (
    is_kcc_admin()
    or v_actor_role in ('company_owner', 'company_admin')
    or (v_actor_role = 'manager' and p_intended_role = 'customer')
  ) then
    raise exception 'not authorized to invite users';
  end if;

  if p_intended_role not in ('company_owner', 'company_admin', 'manager', 'technician', 'customer') then
    raise exception 'invalid invitation role %', p_intended_role;
  end if;

  if v_actor_role = 'company_admin' and p_intended_role in ('company_owner', 'company_admin') then
    raise exception 'company_admin cannot invite role %', p_intended_role;
  end if;

  select * into v_existing
  from organization_invitations
  where organization_id = p_organization_id
    and lower(email) = v_email
    and intended_role = p_intended_role
    and status = 'pending'
  order by created_at desc
  limit 1
  for update;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  if v_existing.id is not null then
    update organization_invitations
    set token_hash = encode(extensions.digest(v_token, 'sha256'), 'hex'),
        expires_at = now() + interval '7 days',
        updated_at = now()
    where id = v_existing.id;
    v_id := v_existing.id;
  else
    insert into organization_invitations (organization_id, email, intended_role, token_hash, invited_by)
    values (p_organization_id, v_email, p_intended_role, encode(extensions.digest(v_token, 'sha256'), 'hex'), auth.uid())
    returning id into v_id;
  end if;

  perform log_domain_event(
    p_organization_id,
    case when v_existing.id is null then 'TEAM_MEMBER_INVITED' else 'TEAM_MEMBER_INVITE_RESENT' end,
    'organization_invitation',
    v_id,
    jsonb_build_object('email', v_email, 'intended_role', p_intended_role)
  );

  return query select v_id, v_token;
end;
$$;

revoke execute on function invite_team_member(uuid, text, text) from public, anon;
grant execute on function invite_team_member(uuid, text, text) to authenticated;
