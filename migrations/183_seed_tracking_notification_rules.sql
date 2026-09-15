-- =========================================================
-- 183_seed_tracking_notification_rules.sql — Marine Cloud Phase 12
-- =========================================================
-- TECHNICIAN_TRACKING_STARTED -> customer (el técnico salió en
-- camino). Nunca se notifica cada punto GPS.
-- =========================================================

insert into notification_rules (organization_id, event_type, payload_filter, severity, recipient_strategy, title_template, body_template, acknowledgement_required) values
  (null, 'TECHNICIAN_TRACKING_STARTED', null, 'info', 'customer',
    'Your technician is on the way', 'Your technician has started their route and live tracking is now available.', false);
