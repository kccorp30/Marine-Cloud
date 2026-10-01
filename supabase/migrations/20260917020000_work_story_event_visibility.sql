-- =========================================================
-- 20260917020000_work_story_event_visibility.sql — Work Story
-- =========================================================
-- El Work Story unificado se apoya en domain_events + la policy
-- role_scoped_read_domain_events, que para un customer consulta
-- domain_event_visibility en su rama ELSE. Sin fila => no visible
-- (fail-closed, correcto por defecto).
--
-- Huecos reales encontrados al auditar el feed:
--
-- 1. VISIT_FINISHED (nuevo en 20260917010000) no tenía fila: el
--    customer no podía ver que la visita de hoy terminó ni que hay
--    una próxima. El brief pide explícitamente "continuation" en el
--    Work Story del customer.
-- 2. ESTIMATE_SENT / ESTIMATE_APPROVED no tenían fila: el brief pide
--    "approval events" en el feed, y el customer es quien aprueba.
-- 3. CUSTOMER_SERVICE_REQUEST_SUBMITTED / _CANCELLED no tenían fila:
--    son acciones del propio customer; ocultárselas no tiene sentido.
--
-- NO se toca TECHNICIAN_WORK_STARTED: el customer ya ve el inicio del
-- trabajo por WORK_ORDER_STATUS_CHANGED → work_in_progress (que sí es
-- visible). Marcarlo visible duplicaría la entrada y rompería
-- tests/rls/phase3-timeline-tests.sql sin ganar información real.
--
-- Las filas internas se insertan EXPLÍCITAS en false para que el
-- fail-closed quede documentado en datos y no por omisión.
-- =========================================================

insert into domain_event_visibility (event_type, customer_visible) values
  ('VISIT_FINISHED', true),
  ('ESTIMATE_SENT', true),
  ('ESTIMATE_APPROVED', true),
  ('CUSTOMER_SERVICE_REQUEST_SUBMITTED', true),
  ('CUSTOMER_SERVICE_REQUEST_CANCELLED', true),
  ('TECHNICIAN_TRACKING_STARTED', false),
  ('TECHNICIAN_TRACKING_STOPPED', false),
  ('ESTIMATE_CREATED', false),
  ('ESTIMATE_VERSION_CREATED', false),
  ('ESTIMATE_SUPERSEDED', false),
  ('ESTIMATE_VIEWED', false),
  ('ESTIMATE_EMAIL_SENT', false),
  ('ESTIMATE_EXPIRED', false),
  ('SERVICE_REQUEST_CONVERTED', false),
  ('KCC_ASSISTANCE_REQUESTED', false),
  ('EMAIL_SENT', false),
  ('MESSAGE_DRAFT_CREATED', false),
  ('MESSAGE_FAILED', false),
  ('COMPENSATION_AGREEMENT_CREATED', false),
  ('TEMPLATE_CREATED', false),
  ('TEMPLATE_UPDATED', false),
  ('TEAM_MEMBER_INVITED', false),
  ('TEAM_MEMBER_INVITE_RESENT', false)
on conflict (event_type) do update set customer_visible = excluded.customer_visible;
