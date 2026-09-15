-- =========================================================
-- 060_bind_invitation_to_email.sql — Marine Cloud Phase 5 hardening
-- =========================================================
-- BUG REAL: un token válido alcanzaba por sí solo — cualquier cuenta
-- autenticada que consiguiera el token podía canjearlo, sin importar
-- si era la persona realmente invitada. Se exige ahora que el email
-- de la cuenta autenticada coincida con el email de la invitación —
-- el email se lee de auth.users vía el propio auth.uid() (identidad
-- segura de la sesión, nunca un parámetro que mande el cliente),
-- comparado case-insensitive.
--
-- Verificado: cuenta correcta + token válido acepta (PASS); cuenta
-- equivocada + token válido rechazada (PASS); token expirado
-- rechazado (PASS); token revocado rechazado (PASS); invitación ya
-- aceptada no se puede reusar (PASS).
-- =========================================================

create or replace function accept_invitation(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv organization_invitations%rowtype;
  v_existing_id uuid;
  v_actor_email text;
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

  select email into v_actor_email from auth.users where id = auth.uid();
  if v_actor_email is null or lower(trim(v_actor_email)) != lower(trim(v_inv.email)) then
    raise exception 'this invitation was sent to a different email address';
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
