-- =========================================================
-- 033_phase2_event_and_audit_triggers.sql — Marine Cloud Phase 2
-- =========================================================

create or replace function trg_emit_media_added() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform log_domain_event(new.organization_id, 'MEDIA_ADDED', 'media_asset', new.id,
    jsonb_build_object('work_order_id', new.work_order_id, 'category', new.category));
  return new;
end; $$;
create trigger trg_media_assets_domain_event after insert on media_assets
  for each row execute function trg_emit_media_added();

create or replace function trg_emit_work_note_added() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform log_domain_event(new.organization_id, 'WORK_NOTE_ADDED', 'work_note', new.id,
    jsonb_build_object('work_order_id', new.work_order_id, 'note_type', new.note_type));
  return new;
end; $$;
create trigger trg_work_notes_domain_event after insert on work_notes
  for each row execute function trg_emit_work_note_added();

create or replace function trg_emit_measurement_recorded() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform log_domain_event(new.organization_id, 'MEASUREMENT_RECORDED', 'measurement', new.id,
    jsonb_build_object('work_order_id', new.work_order_id, 'measurement_type', new.measurement_type, 'value', new.value, 'unit', new.unit));
  return new;
end; $$;
create trigger trg_measurements_domain_event after insert on measurements
  for each row execute function trg_emit_measurement_recorded();

create or replace function trg_emit_checklist_updated() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform log_domain_event(new.organization_id, 'CHECKLIST_UPDATED', 'checklist_response', new.id,
    jsonb_build_object('work_order_id', new.work_order_id, 'template_item_id', new.template_item_id));
  return new;
end; $$;
create trigger trg_checklist_responses_domain_event after insert or update on checklist_responses
  for each row execute function trg_emit_checklist_updated();

create or replace function trg_emit_progress_update_added() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform log_domain_event(new.organization_id, 'PROGRESS_UPDATE_ADDED', 'progress_update', new.id,
    jsonb_build_object('work_order_id', new.work_order_id, 'customer_visible', new.customer_visible));
  return new;
end; $$;
create trigger trg_progress_updates_domain_event after insert on progress_updates
  for each row execute function trg_emit_progress_update_added();

create trigger trg_audit_time_entries after update on time_entries
  for each row
  when (old.start_time is distinct from new.start_time or old.end_time is distinct from new.end_time or old.status is distinct from new.status)
  execute function trg_audit_row_change();

create trigger trg_audit_media_visibility after update on media_assets
  for each row
  when (old.visibility is distinct from new.visibility or old.deleted_at is distinct from new.deleted_at)
  execute function trg_audit_row_change();

create trigger trg_audit_measurements_voided after update on measurements
  for each row
  when (old.voided_at is distinct from new.voided_at or old.value is distinct from new.value)
  execute function trg_audit_row_change();

create trigger trg_audit_work_notes_deleted after update on work_notes
  for each row
  when (old.deleted_at is distinct from new.deleted_at)
  execute function trg_audit_row_change();

create trigger trg_audit_appointments_actual_times after update on appointments
  for each row
  when (old.actual_start is distinct from new.actual_start or old.actual_end is distinct from new.actual_end)
  execute function trg_audit_row_change();

revoke execute on function trg_emit_media_added() from public, anon, authenticated;
revoke execute on function trg_emit_work_note_added() from public, anon, authenticated;
revoke execute on function trg_emit_measurement_recorded() from public, anon, authenticated;
revoke execute on function trg_emit_checklist_updated() from public, anon, authenticated;
revoke execute on function trg_emit_progress_update_added() from public, anon, authenticated;
