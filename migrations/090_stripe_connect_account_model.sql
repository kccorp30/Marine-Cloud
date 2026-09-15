-- =========================================================
-- 090_stripe_connect_account_model.sql — Marine Cloud Phase 7
-- =========================================================
-- Solo el MODELO de cuenta — nunca claves secretas por tenant. La
-- invoice NUNCA depende de que esto exista: deshabilitado, todo sigue
-- funcionando vía pagos manuales.
--
-- LIMITACIÓN HONESTA: este entorno no tiene acceso real a la API de
-- Stripe (sin credenciales de plataforma disponibles) — estas
-- funciones modelan y persisten el ESTADO de la cuenta tal como lo
-- reportaría un webhook real de Stripe Connect, pero no ejecutan el
-- onboarding real ni llamadas reales a Stripe.
-- =========================================================

create table payment_provider_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  provider text not null default 'stripe' check (provider in ('stripe')),
  provider_account_id text,
  enabled boolean not null default false,
  onboarding_status text not null default 'not_started' check (onboarding_status in ('not_started', 'pending', 'complete')),
  charges_enabled boolean not null default false,
  payouts_enabled boolean not null default false,
  connected_at timestamptz,
  disconnected_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint uq_provider_accounts_org_provider unique (organization_id, provider)
);

alter table payment_provider_accounts enable row level security;

create policy "read_payment_provider_accounts" on payment_provider_accounts for select
using (is_kcc_admin() or is_org_staff(organization_id));

revoke all on payment_provider_accounts from anon, authenticated;
grant select on payment_provider_accounts to authenticated;

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
  if not (is_kcc_admin() or is_org_staff(p_organization_id)) then
    raise exception 'not authorized';
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

create or replace function disable_stripe_account(p_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (is_kcc_admin() or is_org_staff(p_organization_id)) then
    raise exception 'not authorized';
  end if;

  update payment_provider_accounts set enabled = false, disconnected_at = now(), updated_at = now()
  where organization_id = p_organization_id and provider = 'stripe';

  update organization_payment_settings set stripe_connect_enabled = false, updated_at = now()
  where organization_id = p_organization_id;

  perform log_domain_event(p_organization_id, 'STRIPE_ACCOUNT_DISABLED', 'organization', p_organization_id, '{}'::jsonb);
  perform log_audit_event(p_organization_id, 'payment_provider_account', p_organization_id, 'stripe_account_disabled', null, null);
end;
$$;

revoke execute on function disable_stripe_account(uuid) from public, anon;
grant execute on function disable_stripe_account(uuid) to authenticated;
