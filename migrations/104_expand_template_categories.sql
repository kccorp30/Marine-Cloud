-- =========================================================
-- 104_expand_template_categories.sql — Marine Cloud Phase 8
-- =========================================================
-- Amplía las categorías al set exacto que pide el brief (sección 12).
-- =========================================================

alter table message_templates drop constraint message_templates_category_check;
alter table message_templates add constraint message_templates_category_check check (category in (
  'estimate_ready', 'estimate_reminder', 'estimate_approved', 'estimate_declined',
  'invoice_ready', 'deposit_required', 'payment_received', 'balance_due',
  'appointment_confirmation', 'appointment_reminder', 'service_update', 'work_completed',
  'general'
));
