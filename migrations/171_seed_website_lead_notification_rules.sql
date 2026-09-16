-- =========================================================
-- 171_seed_website_lead_notification_rules.sql — Marine Cloud Phase 11
-- =========================================================
-- WEBSITE_LEAD_ROUTED -> staff de la organización receptora.
-- WEBSITE_LEAD_CONVERSION_FAILED -> kcc_admin. Nunca se notifica al
-- customer por eventos internos de ruteo.
-- Verificado con datos reales: notificación real creada para el
-- staff de la organización que recibió el lead ruteado.
-- =========================================================

insert into notification_rules (organization_id, event_type, payload_filter, severity, recipient_strategy, title_template, body_template, acknowledgement_required) values
  (null, 'WEBSITE_LEAD_ROUTED', null, 'action_required', 'org_staff',
    'New website lead', 'A new KCC Website lead has been routed to your company.', false),
  (null, 'WEBSITE_LEAD_CONVERSION_FAILED', null, 'urgent', 'kcc_admin',
    'Website lead conversion failed', 'A website lead conversion failed and needs attention.', true);
