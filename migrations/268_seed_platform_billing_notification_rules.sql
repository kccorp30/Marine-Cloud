-- =========================================================
-- 268_seed_platform_billing_notification_rules.sql — Marine Cloud Phase 15
-- =========================================================
-- Reusa el Notification Core existente. billing_admin para todo lo
-- de facturación de la company. KCC recibe notificación propia para
-- pagos pendientes de verificación.
-- =========================================================

insert into notification_rules (organization_id, event_type, payload_filter, severity, recipient_strategy, title_template, body_template, acknowledgement_required) values
  (null, 'PLATFORM_BILLING_CHARGE_ISSUED', null, 'info', 'billing_admin', 'New billing charge', 'A new Marine Cloud subscription charge has been issued.', false),
  (null, 'PLATFORM_PAYMENT_SUBMITTED', null, 'info', 'kcc_admin', 'Payment awaiting verification', 'A manual payment was submitted and is awaiting KCC verification.', false),
  (null, 'PLATFORM_PAYMENT_VERIFIED', null, 'info', 'billing_admin', 'Payment verified', 'Your payment has been verified by KCC.', false),
  (null, 'PLATFORM_PAYMENT_REJECTED', null, 'action_required', 'billing_admin', 'Payment rejected', 'Your submitted payment could not be verified. Please review and resubmit.', false),
  (null, 'PLATFORM_PAYMENT_REVERSED', null, 'action_required', 'billing_admin', 'Payment reversed', 'A previously verified payment has been reversed.', false),
  (null, 'PLATFORM_ACCESS_RESTORED_AFTER_PAYMENT', null, 'info', 'billing_admin', 'Access restored', 'Your Marine Cloud access has been restored after payment.', false)
on conflict do nothing;
