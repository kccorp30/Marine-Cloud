-- =========================================================
-- 260_platform_billing_schema.sql — Marine Cloud Phase 15
-- =========================================================
-- Dominio financiero SEPARADO de invoices/payments de customer.
-- NUMERIC para dinero, nunca float. Deuda (charge) y pago (payment)
-- son objetos DISTINTOS.
-- =========================================================

create table platform_billing_charges (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  subscription_id uuid not null references organization_subscriptions(id),
  billing_period_start timestamptz not null,
  billing_period_end timestamptz not null,
  issued_at timestamptz not null default now(),
  due_at timestamptz not null,
  currency text not null default 'USD',
  subtotal numeric(12,2) not null,
  discount_amount numeric(12,2) not null default 0,
  tax_amount numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null,
  amount_paid numeric(12,2) not null default 0,
  balance_due numeric(12,2) not null,
  status text not null default 'open' check (status in ('draft', 'open', 'partially_paid', 'paid', 'overdue', 'void')),
  description text,
  source text not null default 'subscription' check (source in ('subscription', 'manual', 'setup_fee', 'onboarding', 'custom_service')),
  voided_at timestamptz,
  voided_by uuid references profiles(id),
  void_reason text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (total_amount >= 0 and subtotal >= 0 and discount_amount >= 0 and tax_amount >= 0 and amount_paid >= 0),
  check (billing_period_end > billing_period_start),
  check (due_at >= billing_period_start)
);

create unique index uq_billing_charge_period on platform_billing_charges (subscription_id, billing_period_start, billing_period_end);
create index idx_billing_charges_org on platform_billing_charges (organization_id);
create index idx_billing_charges_status on platform_billing_charges (status);

create trigger trg_billing_charges_updated_at before update on platform_billing_charges
  for each row execute function set_updated_at();

create table platform_payment_methods (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  type text not null check (type in ('zelle', 'cash', 'bank_transfer', 'nequi', 'other_manual', 'epayco', 'stripe')),
  currency text,
  instructions text,
  active boolean not null default true,
  requires_reference boolean not null default false,
  requires_proof boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_payment_methods_updated_at before update on platform_payment_methods
  for each row execute function set_updated_at();

insert into platform_payment_methods (code, name, type, currency, requires_reference, requires_proof, sort_order) values
  ('zelle', 'Zelle', 'zelle', 'USD', true, true, 1),
  ('cash', 'Cash', 'cash', null, false, false, 2),
  ('bank_transfer', 'Bank Transfer', 'bank_transfer', null, true, true, 3),
  ('nequi', 'Nequi', 'nequi', 'COP', true, true, 4),
  ('other_manual', 'Other Manual', 'other_manual', null, false, false, 5);

create table platform_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  payment_method_id uuid not null references platform_payment_methods(id),
  provider text not null default 'manual' check (provider in ('manual', 'epayco', 'stripe')),
  provider_payment_id text,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null default 'USD',
  status text not null default 'pending_verification' check (status in ('pending_verification', 'verified', 'rejected', 'reversed')),
  reference text,
  receipt_number text unique,
  received_at timestamptz not null default now(),
  recorded_by uuid references profiles(id),
  submitted_by_role text,
  verified_by uuid references profiles(id),
  verified_at timestamptz,
  rejected_by uuid references profiles(id),
  rejected_at timestamptz,
  rejection_reason text,
  reversed_by uuid references profiles(id),
  reversed_at timestamptz,
  reversal_reason text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_platform_payments_org on platform_payments (organization_id);
create index idx_platform_payments_status on platform_payments (status);

create trigger trg_platform_payments_updated_at before update on platform_payments
  for each row execute function set_updated_at();

create table platform_payment_evidence (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  payment_id uuid not null references platform_payments(id),
  storage_path text not null,
  mime_type text,
  uploaded_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

create index idx_payment_evidence_payment on platform_payment_evidence (payment_id);

create table platform_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references platform_payments(id),
  billing_charge_id uuid not null references platform_billing_charges(id),
  amount numeric(12,2) not null check (amount > 0),
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  unique (payment_id, billing_charge_id)
);

create index idx_allocations_payment on platform_payment_allocations (payment_id);
create index idx_allocations_charge on platform_payment_allocations (billing_charge_id);

create table platform_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  entry_type text not null check (entry_type in ('subscription_charge', 'manual_payment', 'payment_reversal', 'credit', 'refund', 'kcc_commission', 'assistance_revenue')),
  source_type text not null,
  source_id uuid not null,
  currency text not null default 'USD',
  amount numeric(12,2) not null,
  direction text not null check (direction in ('debit', 'credit')),
  occurred_at timestamptz not null default now(),
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index idx_ledger_org on platform_ledger_entries (organization_id);
create index idx_ledger_type on platform_ledger_entries (entry_type);

alter table platform_billing_charges enable row level security;
alter table platform_payment_methods enable row level security;
alter table platform_payments enable row level security;
alter table platform_payment_evidence enable row level security;
alter table platform_payment_allocations enable row level security;
alter table platform_ledger_entries enable row level security;
