-- =========================================================
-- 096_harden_stripe_provider_authority.sql — Phase 7 hardening
-- =========================================================
-- BUG REAL: set_stripe_account_state() permitía a cualquier staff de
-- la organización auto-declararse charges_enabled=true/
-- payouts_enabled=true — nada de esto es autoritativo. Separación
-- real: preferencia (staff, inofensiva) vs. estado autoritativo (solo
-- kcc_admin, representando el camino de webhook/plataforma de
-- confianza). Verificado: staff normal rechazado al intentar forjar
-- el estado, sí puede setear la preferencia; kcc_admin sí puede
-- setear el estado real; deshabilitar preserva el registro histórico.
-- =========================================================

create or replace function set_stripe_account_state(
  p_organization_id uuid,
  p_provider_account_id text,
  p_onboarding_status text,
  p_charges_enabled boolean,
  p_payouts_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_kcc_admin() then
    raise exception 'only platform-authoritative actors can set Stripe provider state';
  end if;

  insert into payment_provider_accounts (organization_id, provider, provider_account_id, enabled, onboarding_status, charges_enabled, payouts_enabled, connected_at)
  values (p_organization_id, 'stripe', p_provider_account_id, true, p_onboarding_status, p_charges_enabled, p_payouts_enabled, now())
  on conflict (organization_id, provider) do update set
    provider_account_id = excluded.provider_account_id,
    enabled = true,
    onboarding_status = excluded.onboarding_status,
    charges_enabled = excluded.charges_enabled,
    payouts_enabled = excluded.payouts_enabled,
    connected_at = coalesce(payment_provider_accounts.connected_at, now()),
    disconnected_at = null,
    updated_at = now();

  update organization_payment_settings set stripe_connect_enabled = (p_charges_enabled and p_payouts_enabled), updated_at = now()
  where organization_id = p_organization_id;

  perform log_domain_event(p_organization_id, 'STRIPE_ACCOUNT_CONNECTED', 'organization', p_organization_id,
    jsonb_build_object('onboarding_status', p_onboarding_status, 'charges_enabled', p_charges_enabled));
  perform log_audit_event(p_organization_id, 'payment_provider_account', p_organization_id, 'stripe_account_connected',
    null, jsonb_build_object('onboarding_status', p_onboarding_status));
end;
$$;

revoke execute on function set_stripe_account_state(uuid, text, text, boolean, boolean) from public, anon;
grant execute on function set_stripe_account_state(uuid, text, text, boolean, boolean) to authenticated;

create or replace function set_stripe_preference(p_organization_id uuid, p_wants_stripe boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (is_kcc_admin() or is_org_staff(p_organization_id)) then
    raise exception 'not authorized';
  end if;

  insert into payment_provider_accounts (organization_id, provider, enabled)
  values (p_organization_id, 'stripe', p_wants_stripe)
  on conflict (organization_id, provider) do update set
    enabled = p_wants_stripe,
    disconnected_at = case when p_wants_stripe then null else now() end,
    updated_at = now();

  if not p_wants_stripe then
    update organization_payment_settings set stripe_connect_enabled = false, updated_at = now()
    where organization_id = p_organization_id;
  end if;

  perform log_audit_event(p_organization_id, 'payment_provider_account', p_organization_id, 'stripe_preference_updated',
    null, jsonb_build_object('wants_stripe', p_wants_stripe));
end;
$$;

revoke execute on function set_stripe_preference(uuid, boolean) from public, anon;
grant execute on function set_stripe_preference(uuid, boolean) to authenticated;
