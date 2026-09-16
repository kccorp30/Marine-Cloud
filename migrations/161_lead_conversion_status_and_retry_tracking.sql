-- =========================================================
-- 161_lead_conversion_status_and_retry_tracking.sql — Phase 11
-- =========================================================
-- conversion_status necesita 'needs_routing' — no existía. Se
-- agregan attempt_count/last_attempt_at para el modelo de reintento
-- durable.
-- =========================================================

alter table leads drop constraint leads_conversion_status_check;
alter table leads add constraint leads_conversion_status_check check (conversion_status in ('not_converted', 'needs_routing', 'in_progress', 'converted', 'failed'));

alter table leads add column attempt_count int not null default 0;
alter table leads add column last_attempt_at timestamptz;
