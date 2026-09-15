-- =========================================================
-- 252_seed_lifecycle_milestone_notification_rules.sql — Phase 14 absolute final closure
-- =========================================================
-- Reglas de notificación reales para los eventos de milestone —
-- reusa el Notification Core existente, nunca un sistema paralelo.
-- =========================================================

insert into notification_rules (organization_id, event_type, payload_filter, severity, recipient_strategy, title_template, body_template, acknowledgement_required) values
  (null, 'SUBSCRIPTION_TRIAL_7_DAYS_REMAINING', null, 'info', 'billing_admin', '7 days left in your trial', 'Your Marine Cloud trial ends in 7 days. Choose a plan to keep full access.', false),
  (null, 'SUBSCRIPTION_TRIAL_3_DAYS_REMAINING', null, 'action_required', 'billing_admin', '3 days left in your trial', 'Your Marine Cloud trial ends in 3 days. Choose a plan to keep full access.', false),
  (null, 'SUBSCRIPTION_TRIAL_1_DAY_REMAINING', null, 'action_required', 'billing_admin', 'Trial ends tomorrow', 'Your Marine Cloud trial ends tomorrow. Choose a plan to keep full access.', false),
  (null, 'SUBSCRIPTION_TRIAL_EXPIRED', null, 'action_required', 'billing_admin', 'Your trial has ended', 'Your Marine Cloud trial has ended. Choose a plan to restore full access — your data remains safe.', false),
  (null, 'SUBSCRIPTION_GRACE_PERIOD_STARTED', null, 'action_required', 'billing_admin', 'Grace period started', 'Your Marine Cloud account is in a grace period.', false);
