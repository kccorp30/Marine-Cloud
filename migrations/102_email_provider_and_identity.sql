-- =========================================================
-- 102_email_provider_and_identity.sql — Marine Cloud Phase 8
-- =========================================================
-- Mismo patrón que payment_provider_accounts (Phase 7): nunca claves
-- secretas por tenant en tablas normales. Un tenant NUNCA puede
-- suplantar la identidad de otro — sender_email/verification_status/
-- enabled son autoritativos, solo kcc_admin los toca
-- (set_email_provider_state), igual que Stripe.
-- =========================================================

create table organization_email_settings (
  organization_id uuid primary key references organizations(id),
  provider text not null default 'resend' check (provider in ('resend')),
  sender_name text,
  sender_email text,
  reply_to_email text,
  enabled boolean not null default false,
  verification_status text not null default 'unverified' check (verification_status in ('unverified', 'pending', 'verified')),
  signature_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table organization_email_settings enable row level security;

create policy "read_email_settings" on organization_email_settings for select
using (is_kcc_admin() or is_org_staff(organization_id));

revoke all on organization_email_settings from anon, authenticated;
grant select on organization_email_settings to authenticated;

create or replace function update_email_settings(
  p_organization_id uuid,
  p_sender_name text default null,
  p_reply_to_email text default null,
  p_signature_text text default null
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

  insert into organization_email_settings (organization_id) values (p_organization_id)
  on conflict (organization_id) do nothing;

  update organization_email_settings set
    sender_name = coalesce(p_sender_name, sender_name),
    reply_to_email = coalesce(p_reply_to_email, reply_to_email),
    signature_text = coalesce(p_signature_text, signature_text),
    updated_at = now()
  where organization_id = p_organization_id;
end;
$$;

revoke execute on function update_email_settings(uuid, text, text, text) from public, anon;
grant execute on function update_email_settings(uuid, text, text, text) to authenticated;

create or replace function set_email_provider_state(
  p_organization_id uuid,
  p_sender_email text,
  p_verification_status text,
  p_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_kcc_admin() then
    raise exception 'only platform-authoritative actors can set email provider state';
  end if;

  insert into organization_email_settings (organization_id, sender_email, verification_status, enabled)
  values (p_organization_id, p_sender_email, p_verification_status, p_enabled)
  on conflict (organization_id) do update set
    sender_email = excluded.sender_email,
    verification_status = excluded.verification_status,
    enabled = excluded.enabled,
    updated_at = now();
end;
$$;

revoke execute on function set_email_provider_state(uuid, text, text, boolean) from public, anon;
grant execute on function set_email_provider_state(uuid, text, text, boolean) to authenticated;
