-- =========================================================
-- 199_seed_qc_warranty_notification_rules.sql — Marine Cloud Phase 13
-- =========================================================
-- QC_SUBMITTED/QC_FAILED -> staff. WARRANTY_ACTIVATED/CLAIM_APPROVED/
-- CLAIM_REJECTED -> customer. WARRANTY_CLAIM_SUBMITTED -> staff.
-- Verificado con datos reales: notificación real creada para staff
-- al submitir QC.
-- =========================================================

insert into notification_rules (organization_id, event_type, payload_filter, severity, recipient_strategy, title_template, body_template, acknowledgement_required) values
  (null, 'QC_SUBMITTED', null, 'action_required', 'org_staff', 'QC submitted for review', 'A quality control submission is awaiting your review.', false),
  (null, 'QC_FAILED', null, 'action_required', 'org_staff', 'QC failed', 'A quality control inspection failed and needs remediation.', false),
  (null, 'WARRANTY_ACTIVATED', null, 'info', 'customer', 'Your warranty is now active', 'Your service warranty has been activated. You can view coverage details in your account.', false),
  (null, 'WARRANTY_CLAIM_SUBMITTED', null, 'action_required', 'org_staff', 'New warranty claim', 'A customer has submitted a warranty claim requiring review.', false),
  (null, 'WARRANTY_CLAIM_APPROVED', null, 'info', 'customer', 'Your warranty claim was approved', 'Your warranty claim has been approved. We will follow up with next steps.', false),
  (null, 'WARRANTY_CLAIM_REJECTED', null, 'info', 'customer', 'Your warranty claim update', 'There is an update on your warranty claim. Please contact us for details.', false);
