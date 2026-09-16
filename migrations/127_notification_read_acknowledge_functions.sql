-- =========================================================
-- 127_notification_read_acknowledge_functions.sql — Marine Cloud Phase 9
-- =========================================================
-- Único camino de mutación sobre notifications. Verificado: el
-- destinatario real puede leer/reconocer, otro usuario no.
-- =========================================================

create or replace function mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient uuid;
begin
  select recipient_user_id into v_recipient from notifications where id = p_notification_id;
  if v_recipient is null then
    raise exception 'notification not found';
  end if;
  if v_recipient != auth.uid() and not is_kcc_admin() then
    raise exception 'not authorized to mark this notification as read';
  end if;

  update notifications set read_at = coalesce(read_at, now()), updated_at = now() where id = p_notification_id;
end;
$$;

revoke execute on function mark_notification_read(uuid) from public, anon;
grant execute on function mark_notification_read(uuid) to authenticated;

create or replace function mark_all_notifications_read()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update notifications set read_at = now(), updated_at = now()
  where recipient_user_id = auth.uid() and read_at is null;
end;
$$;

revoke execute on function mark_all_notifications_read() from public, anon;
grant execute on function mark_all_notifications_read() to authenticated;

create or replace function acknowledge_notification(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_notif notifications%rowtype;
begin
  select * into v_notif from notifications where id = p_notification_id for update;
  if v_notif.id is null then
    raise exception 'notification not found';
  end if;
  if v_notif.recipient_user_id != auth.uid() and not is_kcc_admin() then
    raise exception 'not authorized to acknowledge this notification';
  end if;

  update notifications set
    read_at = coalesce(read_at, now()),
    acknowledged_at = coalesce(acknowledged_at, now()),
    acknowledged_by = coalesce(acknowledged_by, auth.uid()),
    updated_at = now()
  where id = p_notification_id;
end;
$$;

revoke execute on function acknowledge_notification(uuid) from public, anon;
grant execute on function acknowledge_notification(uuid) to authenticated;
