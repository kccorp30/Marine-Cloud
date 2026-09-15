-- =========================================================
-- 219_organization_subscriptions_schema.sql — Marine Cloud Phase 14
-- =========================================================
-- Una sola suscripción AUTORITATIVA vigente por organización. price_
-- snapshot congelado al suscribir — nunca derivado de subscription_
-- plans en el momento de la consulta. Campos de provider preparados
-- para Phase 15, NULL en esta fase.
-- =========================================================

create table organization_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  plan_id uuid not null references subscription_plans(id),
  status text not null default 'trialing' check (status in (
    'trialing', 'active', 'trial_expired', 'past_due', 'grace_period', 'cancelled', 'complimentary'
  )),
  billing_cycle text not null check (billing_cycle in ('weekly', 'monthly', 'annual', 'custom')),
  currency text not null default 'USD',
  price_snapshot numeric(12,2),
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  subscription_started_at timestamptz,
  current_period_started_at timestamptz,
  current_period_ends_at timestamptz,
  grace_period_ends_at timestamptz,
  cancel_at_period_end boolean not null default false,
  cancelled_at timestamptz,
  cancelled_by uuid references profiles(id),
  cancellation_reason text,
  complimentary boolean not null default false,
  complimentary_reason text,
  custom_terms text,
  price_override boolean not null default false,
  billing_provider text,
  provider_customer_id text,
  provider_subscription_id text,
  created_by uuid references profiles(id),
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index uq_org_subscription_current on organization_subscriptions(organization_id) where superseded_at is null;

create index idx_org_subscriptions_org on organization_subscriptions(organization_id);
create index idx_org_subscriptions_status on organization_subscriptions(status);

create trigger trg_org_subscriptions_updated_at before update on organization_subscriptions
  for each row execute function set_updated_at();

alter table organizations add column archived_at timestamptz;
alter table organizations add column archived_by uuid references profiles(id);
alter table organizations add column archive_reason text;
