-- =========================================================
-- 229_seed_subscription_notification_rules.sql — Marine Cloud Phase 14
-- =========================================================
-- Reusa el Notification Core de Phase 9. Recordatorios de "días
-- restantes" requieren un scheduler de fechas futuras que no existe
-- todavía — diferidos explícitos, nunca fingidos como funcionando.
-- =========================================================

insert into notification_rules (organization_id, event_type, payload_filter, severity, recipient_strategy, title_template, body_template, acknowledgement_required) values
  (null, 'SUBSCRIPTION_TRIAL_STARTED', null, 'info', 'org_staff', 'Your trial has started', 'Your Marine Cloud trial is now active. Explore the platform and choose a plan before it ends.', false),
  (null, 'SUBSCRIPTION_TRIAL_EXTENDED', null, 'info', 'org_staff', 'Your trial was extended', 'KCC has extended your trial period.', false),
  (null, 'SUBSCRIPTION_ACTIVATED', null, 'info', 'org_staff', 'Your subscription is active', 'Your Marine Cloud subscription is now active.', false),
  (null, 'SUBSCRIPTION_PLAN_CHANGED', null, 'info', 'org_staff', 'Your plan has changed', 'Your Marine Cloud subscription plan has been updated.', false),
  (null, 'SUBSCRIPTION_CANCELLED', null, 'action_required', 'org_staff', 'Your subscription was cancelled', 'Your Marine Cloud subscription has been cancelled. Your data remains safe.', false),
  (null, 'ORGANIZATION_ARCHIVED', null, 'action_required', 'org_staff', 'Your account has been archived', 'Your Marine Cloud account has been archived by KCC. Contact support for details.', false),
  (null, 'ORGANIZATION_REACTIVATED', null, 'info', 'org_staff', 'Your account has been reactivated', 'Your Marine Cloud account is active again.', false);
