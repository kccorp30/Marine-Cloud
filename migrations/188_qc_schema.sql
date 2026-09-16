-- =========================================================
-- 188_qc_schema.sql — Marine Cloud Phase 13
-- =========================================================
-- qc_required vive directo en work_orders — snapshot real, nunca
-- cambia retroactivamente por editar configuración de servicio
-- después. qc_submissions/qc_submission_items son un modelo dedicado
-- (el checklist genérico existente no tiene semántica pass/fail a
-- nivel de submission). Evidencia via media_assets existente.
-- =========================================================

alter table work_orders add column qc_required boolean not null default false;

create table qc_submissions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  work_order_id uuid not null references work_orders(id),
  submitted_by uuid references profiles(id),
  reviewed_by uuid references profiles(id),
  status text not null default 'draft' check (status in ('draft', 'submitted', 'passed', 'failed', 'cancelled')),
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  passed_at timestamptz,
  failed_at timestamptz,
  failure_reason text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index uq_qc_submission_open_per_wo
  on qc_submissions(work_order_id)
  where status in ('draft', 'submitted');

create index idx_qc_submissions_work_order on qc_submissions(work_order_id);
create index idx_qc_submissions_org on qc_submissions(organization_id);

create trigger trg_qc_submissions_updated_at before update on qc_submissions
  for each row execute function set_updated_at();

create table qc_submission_items (
  id uuid primary key default gen_random_uuid(),
  qc_submission_id uuid not null references qc_submissions(id),
  label text not null,
  result text not null default 'pending' check (result in ('pending', 'pass', 'fail', 'not_applicable')),
  notes text,
  required boolean not null default true,
  sort_order int not null default 0,
  media_asset_id uuid references media_assets(id),
  created_at timestamptz not null default now()
);

create index idx_qc_submission_items_submission on qc_submission_items(qc_submission_id);
