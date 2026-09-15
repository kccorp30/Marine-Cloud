-- =========================================================
-- 130_seed_kcc_assistance_notification_rules.sql — Marine Cloud Phase 9
-- =========================================================
-- KCC_ASSISTANCE_REQUESTED -> URGENT a todo kcc_admin, con
-- acknowledgement obligatorio. KCC_ASSISTANCE_ACCEPTED -> de vuelta
-- al técnico que la pidió. Verificado con datos reales.
-- =========================================================

insert into notification_rules (organization_id, event_type, payload_filter, severity, recipient_strategy, title_template, body_template, acknowledgement_required) values
  (null, 'KCC_ASSISTANCE_REQUESTED', null, 'urgent', 'kcc_admin',
    'KCC Assistance requested', 'A technician needs help on {{vessel_name}}.', true),
  (null, 'KCC_ASSISTANCE_ACCEPTED', null, 'action_required', 'requesting_technician',
    'KCC accepted your assistance request', 'KCC has accepted your assistance request for {{vessel_name}}.', false);
