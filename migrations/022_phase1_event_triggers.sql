-- =========================================================
-- 022_phase1_event_triggers.sql — Marine Cloud Phase 1
-- =========================================================

create or replace function trg_emit_customer_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform log_domain_event(new.organization_id, 'CUSTOMER_CREATED', 'customer', new.id,
    jsonb_build_object('first_name', new.first_name, 'last_name', new.last_name));
  return new;
end; $$;
create trigger trg_customers_domain_event after insert on customers
  for each row execute function trg_emit_customer_created();

create or replace function trg_emit_vessel_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform log_domain_event(new.organization_id, 'VESSEL_CREATED', 'vessel', new.id,
    jsonb_build_object('name', new.name, 'hin', new.hin));
  return new;
end; $$;
create trigger trg_vessels_domain_event after insert on vessels
  for each row execute function trg_emit_vessel_created();

create or replace function trg_emit_vessel_owner_changed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform log_domain_event(new.organization_id, 'VESSEL_OWNER_CHANGED', 'vessel', new.vessel_id,
    jsonb_build_object('customer_id', new.customer_id, 'start_date', new.start_date));
  return new;
end; $$;
create trigger trg_vessel_ownership_domain_event after insert on vessel_ownership_history
  for each row execute function trg_emit_vessel_owner_changed();

create or replace function trg_emit_vessel_system_added() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform log_domain_event(new.organization_id, 'VESSEL_SYSTEM_ADDED', 'vessel_system', new.id,
    jsonb_build_object('vessel_id', new.vessel_id, 'system_type', new.system_type));
  return new;
end; $$;
create trigger trg_vessel_systems_domain_event after insert on vessel_systems
  for each row execute function trg_emit_vessel_system_added();

create or replace function trg_emit_work_order_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform log_domain_event(new.organization_id, 'WORK_ORDER_CREATED', 'work_order', new.id,
    jsonb_build_object('title', new.title, 'customer_id', new.customer_id, 'vessel_id', new.vessel_id));
  return new;
end; $$;
create trigger trg_work_orders_domain_event after insert on work_orders
  for each row execute function trg_emit_work_order_created();

create or replace function trg_emit_appointment_event() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if TG_OP = 'INSERT' then
    perform log_domain_event(new.organization_id, 'APPOINTMENT_CREATED', 'appointment', new.id,
      jsonb_build_object('work_order_id', new.work_order_id, 'scheduled_start', new.scheduled_start));
  elsif TG_OP = 'UPDATE' and (old.scheduled_start is distinct from new.scheduled_start) then
    perform log_domain_event(new.organization_id, 'APPOINTMENT_RESCHEDULED', 'appointment', new.id,
      jsonb_build_object('work_order_id', new.work_order_id, 'old_start', old.scheduled_start, 'new_start', new.scheduled_start));
  end if;
  return new;
end; $$;
create trigger trg_appointments_domain_event after insert or update on appointments
  for each row execute function trg_emit_appointment_event();

create or replace function trg_emit_assignment_event() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if TG_OP = 'INSERT' then
    perform log_domain_event(new.organization_id, 'TECHNICIAN_ASSIGNED', 'work_order', new.work_order_id,
      jsonb_build_object('technician_profile_id', new.technician_profile_id, 'assignment_id', new.id));
  elsif TG_OP = 'UPDATE' and old.status = 'active' and new.status = 'removed' then
    perform log_domain_event(new.organization_id, 'TECHNICIAN_UNASSIGNED', 'work_order', new.work_order_id,
      jsonb_build_object('technician_profile_id', new.technician_profile_id, 'assignment_id', new.id));
  end if;
  return new;
end; $$;
create trigger trg_assignments_domain_event after insert or update on assignments
  for each row execute function trg_emit_assignment_event();

-- ---------------------------------------------------------
-- Audit events — cambios sensibles (item 13 del brief)
-- ---------------------------------------------------------
create trigger trg_audit_customers after update on customers
  for each row
  when (old.first_name is distinct from new.first_name or old.last_name is distinct from new.last_name
        or old.email is distinct from new.email or old.phone is distinct from new.phone)
  execute function trg_audit_row_change();

create trigger trg_audit_vessels after update on vessels
  for each row
  when (old.hin is distinct from new.hin)
  execute function trg_audit_row_change();

create trigger trg_audit_appointments after update on appointments
  for each row
  when (old.scheduled_start is distinct from new.scheduled_start or old.scheduled_end is distinct from new.scheduled_end)
  execute function trg_audit_row_change();

create trigger trg_audit_assignments_insert after insert on assignments
  for each row execute function trg_audit_row_change();

create trigger trg_audit_assignments_update after update on assignments
  for each row
  when (old.status is distinct from new.status)
  execute function trg_audit_row_change();
