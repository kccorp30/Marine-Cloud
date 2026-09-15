-- =========================================================
-- 218_subscription_plans_schema.sql — Marine Cloud Phase 14
-- =========================================================
-- Dominio financiero SEPARADO de invoices/payments (customer<->
-- company, no KCC<->company). NUMERIC para dinero, nunca float.
-- Nunca se borran planes referenciados históricamente.
-- =========================================================

create table subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  status text not null default 'active' check (status in ('active', 'inactive', 'archived')),
  currency text not null default 'USD',
  weekly_price numeric(12,2),
  monthly_price numeric(12,2),
  annual_price numeric(12,2),
  trial_default_days int,
  is_public boolean not null default true,
  is_custom boolean not null default false,
  sort_order int not null default 0,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_subscription_plans_updated_at before update on subscription_plans
  for each row execute function set_updated_at();

create table plan_module_entitlements (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references subscription_plans(id),
  module_key text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  unique (plan_id, module_key)
);
