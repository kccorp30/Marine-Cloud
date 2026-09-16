-- =========================================================
-- 126_seed_platform_notification_rules.sql — Marine Cloud Phase 9
-- =========================================================
-- Las 5 notificaciones mínimas exigidas por el brief, mapeadas 1:1 a
-- domain_events YA existentes — ningún evento nuevo,
-- ninguna CUSTOMER_ACTION_REQUIRED ni WORK_COMPLETED inventada.
-- =========================================================

insert into notification_rules (organization_id, event_type, payload_filter, severity, recipient_strategy, title_template, body_template, acknowledgement_required) values
  (null, 'TECHNICIAN_ASSIGNED', null, 'info', 'customer',
    'Technician assigned', 'A technician has been assigned to your service on {{vessel_name}}.', false),
  (null, 'TECHNICIAN_EN_ROUTE', null, 'info', 'customer',
    'Technician on the way', 'Your technician is on the way to {{vessel_name}}.', false),
  (null, 'TECHNICIAN_CHECKED_IN', null, 'info', 'customer',
    'Technician arrived', 'Your technician has arrived at {{vessel_name}}.', false),
  (null, 'TECHNICIAN_WORK_STARTED', null, 'info', 'customer',
    'Work started', 'Work has started on {{vessel_name}}.', false),
  (null, 'WORK_ORDER_STATUS_CHANGED', '{"to_status": "awaiting_approval"}'::jsonb, 'action_required', 'customer',
    'Approval needed', 'Please review and approve the estimate for {{vessel_name}}.', false),
  (null, 'WORK_ORDER_STATUS_CHANGED', '{"to_status": "waiting_customer_approval"}'::jsonb, 'action_required', 'customer',
    'Approval needed', 'Please review and approve pending work for {{vessel_name}}.', false),
  (null, 'WORK_ORDER_STATUS_CHANGED', '{"to_status": "completed"}'::jsonb, 'info', 'customer',
    'Work completed', 'Service on {{vessel_name}} has been completed.', false);
