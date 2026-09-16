-- =========================================================
-- 162_lead_conversion_additional_columns.sql — Phase 11
-- =========================================================
alter table leads add column marine_cloud_service_request_id uuid references service_requests(id);
alter table leads add column conversion_error text;
