-- =========================================================
-- 271_reissue_invitation_token.sql — Marine Cloud pilot P1 fix
-- =========================================================
-- Reenviar una invitación pendiente: genera un token NUEVO (el
-- anterior queda invalidado), extiende la expiración. Misma
-- autoridad que invite_team_member(). Verificado con datos reales.
-- =========================================================

create or replace function reissue_invitation_token(p_invitation_id uuid)
returns table(raw_token text, email text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invitation organization_invitations%rowtype;
  v_actor_role text;
  v_token text;
begin
  select * into v_invitation from organization_invitations where id = p_invitation_id for update;
  if v_invitation.id is null then
    raise exception 'invitation not found';
  end if;
  if v_invitation.status != 'pending' then
    raise exception 'only a pending invitation can be reissued (status: %)', v_invitation.status;
  end if;

  v_actor_role := get_actor_role_in_org(v_invitation.organization_id);
  if not (is_kcc_admin() or v_actor_role in ('company_owner', 'company_admin')) then
    raise exception 'not authorized to reissue this invitation';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  update organization_invitations set
    token_hash = encode(extensions.digest(v_token, 'sha256'), 'hex'),
    expires_at = now() + interval '7 days',
    updated_at = now()
  where id = p_invitation_id;

  perform log_domain_event(v_invitation.organization_id, 'TEAM_MEMBER_INVITE_RESENT', 'organization_invitation', p_invitation_id,
    jsonb_build_object('email', v_invitation.email));

  return query select v_token, v_invitation.email;
end;
$$;

revoke execute on function reissue_invitation_token(uuid) from public, anon;
grant execute on function reissue_invitation_token(uuid) to authenticated;
