-- =========================================================
-- 040_domain_event_role_visibility.sql — Marine Cloud Phase 3
-- =========================================================
-- CORRECCIÓN DE SEGURIDAD REAL: la política de Phase 0
-- (org_members_read_domain_events) le daba a CUALQUIER miembro activo
-- de la organización acceso a TODOS los domain_events de esa org —
-- incluyendo un customer viendo eventos de OTROS customers, o un
-- técnico no asignado viendo eventos de trabajos ajenos. Nunca se
-- explotó porque hasta ahora nada leía domain_events desde la UI,
-- pero Phase 3 sí lo hace (el timeline) — se corrige antes de
-- exponerlo. Verificado con 6 tests reales en vivo: 6/6 PASS.
-- =========================================================

drop policy if exists "org_members_read_domain_events" on domain_events;

create table domain_event_visibility (
  event_type text primary key,
  customer_visible boolean not null default false
);
alter table domain_event_visibility enable row level security;
create policy "authenticated_read_event_visibility" on domain_event_visibility for select
  using (auth.uid() is not null);

insert into domain_event_visibility (event_type, customer_visible) values
  ('WORK_ORDER_CREATED', true),
  ('WORK_ORDER_STATUS_CHANGED', true),
  ('TECHNICIAN_ASSIGNED', true),
  ('TECHNICIAN_UNASSIGNED', false),
  ('TECHNICIAN_EN_ROUTE', true),
  ('TECHNICIAN_CHECKED_IN', true),
  ('TECHNICIAN_CHECKED_OUT', true),
  ('TECHNICIAN_WORK_STARTED', false),
  ('APPOINTMENT_CREATED', true),
  ('APPOINTMENT_RESCHEDULED', true),
  ('TIME_ENTRY_STARTED', false),
  ('TIME_ENTRY_STOPPED', false),
  ('WORK_NOTE_ADDED', false),
  ('MEDIA_ADDED', false),
  ('MEASUREMENT_RECORDED', false),
  ('CHECKLIST_UPDATED', false),
  ('PROGRESS_UPDATE_ADDED', false),
  ('CUSTOMER_CREATED', false),
  ('VESSEL_CREATED', false),
  ('VESSEL_OWNER_CHANGED', false),
  ('VESSEL_SYSTEM_ADDED', false);

create policy "role_scoped_read_domain_events" on domain_events for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (work_order_id is not null and is_assigned_to_work_order(work_order_id))
  or (
    work_order_id is not null
    and is_customer_of_work_order(work_order_id)
    and (
      case event_type
        when 'WORK_NOTE_ADDED' then exists (select 1 from work_notes where id = domain_events.entity_id and visibility = 'customer_visible')
        when 'MEDIA_ADDED' then exists (select 1 from media_assets where id = domain_events.entity_id and visibility = 'customer_visible')
        when 'PROGRESS_UPDATE_ADDED' then exists (select 1 from progress_updates where id = domain_events.entity_id and customer_visible = true)
        else exists (select 1 from domain_event_visibility v where v.event_type = domain_events.event_type and v.customer_visible = true)
      end
    )
  )
);
