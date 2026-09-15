-- =========================================================
-- 136_document_acknowledge_semantics.sql — Phase 9 final fix
-- =========================================================
-- Decisión explícita (antes implícita/ambigua): acknowledge_notification()
-- SÍ permite reconocer una notificación con acknowledgement_required=false
-- — es intencional. Reconocer es una acción benigna, y la UI normal
-- solo muestra el botón cuando acknowledgement_required=true de
-- todas formas (ver NotificationItem.tsx). La autorización del
-- destinatario no cambia.
-- =========================================================

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
