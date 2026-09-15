-- =========================================================
-- 112_commercial_email_server_rendered.sql — Phase 8 hardening
-- =========================================================
-- BUG REAL: send_estimate_email/send_invoice_email aceptaban
-- p_body_original como texto libre. Ahora el cuerpo COMERCIAL
-- (número, total, balance, vencimiento) se arma 100% server-side; el
-- staff solo agrega una intro opcional. send_payment_receipt_email
-- valida que el pago esté 'settled' y usa el monto real de la fila.
-- Firmas cambiadas -> se dropean las viejas primero (evita el bug de
-- overload duplicado encontrado en 113).
-- =========================================================

drop function if exists send_estimate_email(uuid, text, uuid);
drop function if exists send_invoice_email(uuid, text, uuid);
drop function if exists send_payment_receipt_email(uuid, text, uuid);
drop function if exists send_appointment_email(uuid, text, uuid);

create function send_estimate_email(
  p_estimate_id uuid,
  p_custom_intro text default null,
  p_idempotency_key uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estimate estimates%rowtype;
  v_version estimate_versions%rowtype;
  v_customer customers%rowtype;
  v_org organizations%rowtype;
  v_conversation_id uuid;
  v_message_id uuid;
  v_body text;
  v_subject text;
begin
  select * into v_estimate from estimates where id = p_estimate_id;
  if v_estimate.id is null then
    raise exception 'estimate not found';
  end if;
  if not is_commercial_sender(v_estimate.organization_id) then
    raise exception 'not authorized to send commercial communications';
  end if;
  if v_estimate.status = 'draft' then
    raise exception 'cannot email a draft estimate — send it first';
  end if;

  select * into v_version from estimate_versions where id = v_estimate.current_version_id;
  select * into v_customer from customers where id = v_estimate.customer_id;
  select * into v_org from organizations where id = v_estimate.organization_id;

  v_subject := (case when v_estimate.type = 'change_order' then 'Change Order ' else 'Estimate ' end) || v_estimate.estimate_number || ' Ready for Review';

  v_body := coalesce('Hi ' || v_customer.first_name || ',' || E'\n\n', '');
  if p_custom_intro is not null and length(trim(p_custom_intro)) > 0 then
    v_body := v_body || p_custom_intro || E'\n\n';
  end if;
  v_body := v_body
    || (case when v_estimate.type = 'change_order' then 'Change Order ' else 'Estimate ' end) || v_estimate.estimate_number || E'\n'
    || 'Total: $' || to_char(v_version.total, 'FM999,999,990.00') || E'\n'
    || (case when v_version.valid_until is not null then 'Valid until: ' || to_char(v_version.valid_until, 'FMMonth DD, YYYY') || E'\n' else '' end)
    || E'\nPlease log in to Marine Cloud to review and respond.\n\n'
    || coalesce(v_org.name, '');

  v_conversation_id := get_or_create_conversation(v_estimate.organization_id, v_estimate.customer_id, v_estimate.vessel_id, v_estimate.work_order_id, null,
    (case when v_estimate.type = 'change_order' then 'Change Order ' else 'Estimate ' end) || v_estimate.estimate_number);

  v_message_id := send_message(v_conversation_id, 'email', v_body, v_subject, null, null, null, true, p_idempotency_key::text);

  perform log_domain_event(v_estimate.organization_id, 'ESTIMATE_EMAIL_SENT', 'estimate', p_estimate_id,
    jsonb_build_object('message_id', v_message_id, 'total', v_version.total));
  perform log_audit_event(v_estimate.organization_id, 'estimate', p_estimate_id, 'estimate_email_sent',
    null, jsonb_build_object('message_id', v_message_id));

  return v_message_id;
end;
$$;

create function send_invoice_email(
  p_invoice_id uuid,
  p_custom_intro text default null,
  p_idempotency_key uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice invoices%rowtype;
  v_customer customers%rowtype;
  v_settings organization_payment_settings%rowtype;
  v_conversation_id uuid;
  v_message_id uuid;
  v_body text;
  v_subject text;
  v_payment_lines text := '';
begin
  select * into v_invoice from invoices where id = p_invoice_id;
  if v_invoice.id is null then
    raise exception 'invoice not found';
  end if;
  if not is_commercial_sender(v_invoice.organization_id) then
    raise exception 'not authorized to send commercial communications';
  end if;
  if v_invoice.status = 'draft' then
    raise exception 'cannot email a draft invoice — issue it first';
  end if;

  select * into v_customer from customers where id = v_invoice.customer_id;
  select * into v_settings from organization_payment_settings where organization_id = v_invoice.organization_id;

  v_subject := 'Invoice ' || v_invoice.invoice_number;

  if v_settings.manual_payments_enabled and v_settings.accepted_payment_methods is not null then
    v_payment_lines := E'\nAccepted payment methods: ' || array_to_string(v_settings.accepted_payment_methods, ', ');
  end if;

  v_body := 'Hi ' || v_customer.first_name || ',' || E'\n\n';
  if p_custom_intro is not null and length(trim(p_custom_intro)) > 0 then
    v_body := v_body || p_custom_intro || E'\n\n';
  end if;
  v_body := v_body
    || 'Invoice ' || v_invoice.invoice_number || E'\n'
    || 'Total: $' || to_char(v_invoice.total, 'FM999,999,990.00') || E'\n'
    || 'Paid: $' || to_char(v_invoice.amount_paid, 'FM999,999,990.00') || E'\n'
    || 'Balance due: $' || to_char(v_invoice.balance_due, 'FM999,999,990.00') || E'\n'
    || (case when v_invoice.due_date is not null then 'Due: ' || to_char(v_invoice.due_date, 'FMMonth DD, YYYY') || E'\n' else '' end)
    || v_payment_lines
    || E'\n\nPlease log in to Marine Cloud to view details.';

  v_conversation_id := get_or_create_conversation(v_invoice.organization_id, v_invoice.customer_id, v_invoice.vessel_id, v_invoice.work_order_id, null, 'Invoice ' || v_invoice.invoice_number);

  v_message_id := send_message(v_conversation_id, 'email', v_body, v_subject, null, null, null, true, p_idempotency_key::text);

  perform log_domain_event(v_invoice.organization_id, 'INVOICE_EMAIL_SENT', 'invoice', p_invoice_id,
    jsonb_build_object('message_id', v_message_id, 'total', v_invoice.total, 'balance_due', v_invoice.balance_due));
  perform log_audit_event(v_invoice.organization_id, 'invoice', p_invoice_id, 'invoice_email_sent',
    null, jsonb_build_object('message_id', v_message_id));

  return v_message_id;
end;
$$;

create function send_payment_receipt_email(
  p_payment_id uuid,
  p_custom_intro text default null,
  p_idempotency_key uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment payments%rowtype;
  v_invoice invoices%rowtype;
  v_customer customers%rowtype;
  v_conversation_id uuid;
  v_message_id uuid;
  v_body text;
begin
  select * into v_payment from payments where id = p_payment_id;
  if v_payment.id is null then
    raise exception 'payment not found';
  end if;
  if not is_commercial_sender(v_payment.organization_id) then
    raise exception 'not authorized to send commercial communications';
  end if;
  if v_payment.status != 'settled' then
    raise exception 'cannot send a receipt for a payment that is not settled (status: %)', v_payment.status;
  end if;

  select * into v_invoice from invoices where id = v_payment.invoice_id;
  select * into v_customer from customers where id = v_payment.customer_id;

  v_body := 'Hi ' || v_customer.first_name || ',' || E'\n\n';
  if p_custom_intro is not null and length(trim(p_custom_intro)) > 0 then
    v_body := v_body || p_custom_intro || E'\n\n';
  end if;
  v_body := v_body
    || 'Payment received: $' || to_char(v_payment.amount, 'FM999,999,990.00') || ' via ' || replace(v_payment.method, '_', ' ') || E'\n'
    || 'Invoice: ' || v_invoice.invoice_number || E'\n'
    || 'Remaining balance: $' || to_char(v_invoice.balance_due, 'FM999,999,990.00');

  v_conversation_id := get_or_create_conversation(v_payment.organization_id, v_payment.customer_id, v_invoice.vessel_id, v_payment.work_order_id, null, 'Payment Receipt');

  v_message_id := send_message(v_conversation_id, 'email', v_body, 'Payment Receipt — ' || v_invoice.invoice_number, null, null, null, true, p_idempotency_key::text);

  perform log_domain_event(v_payment.organization_id, 'PAYMENT_RECEIPT_SENT', 'payment', p_payment_id,
    jsonb_build_object('message_id', v_message_id, 'amount', v_payment.amount, 'invoice_id', v_payment.invoice_id));

  return v_message_id;
end;
$$;

create function send_appointment_email(
  p_appointment_id uuid,
  p_custom_intro text default null,
  p_idempotency_key uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appt appointments%rowtype;
  v_wo work_orders%rowtype;
  v_customer customers%rowtype;
  v_conversation_id uuid;
  v_message_id uuid;
  v_body text;
begin
  select * into v_appt from appointments where id = p_appointment_id;
  if v_appt.id is null then
    raise exception 'appointment not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_appt.organization_id) or is_assigned_to_work_order(v_appt.work_order_id)) then
    raise exception 'not authorized';
  end if;

  select * into v_wo from work_orders where id = v_appt.work_order_id;
  select * into v_customer from customers where id = v_wo.customer_id;

  v_body := 'Hi ' || v_customer.first_name || ',' || E'\n\n';
  if p_custom_intro is not null and length(trim(p_custom_intro)) > 0 then
    v_body := v_body || p_custom_intro || E'\n\n';
  end if;
  v_body := v_body || 'Appointment: ' || to_char(v_appt.scheduled_start, 'FMMonth DD, YYYY "at" HH12:MI AM');

  v_conversation_id := get_or_create_conversation(v_appt.organization_id, v_wo.customer_id, v_wo.vessel_id, v_wo.id, null, 'Appointment Update');

  v_message_id := send_message(v_conversation_id, 'email', v_body, 'Appointment Confirmation', null, null, null, true, p_idempotency_key::text);

  perform log_domain_event(v_appt.organization_id, 'APPOINTMENT_CONFIRMATION_SENT', 'appointment', p_appointment_id,
    jsonb_build_object('message_id', v_message_id));

  return v_message_id;
end;
$$;

revoke execute on function send_estimate_email(uuid, text, uuid) from public, anon;
grant execute on function send_estimate_email(uuid, text, uuid) to authenticated;
revoke execute on function send_invoice_email(uuid, text, uuid) from public, anon;
grant execute on function send_invoice_email(uuid, text, uuid) to authenticated;
revoke execute on function send_payment_receipt_email(uuid, text, uuid) from public, anon;
grant execute on function send_payment_receipt_email(uuid, text, uuid) to authenticated;
revoke execute on function send_appointment_email(uuid, text, uuid) from public, anon;
grant execute on function send_appointment_email(uuid, text, uuid) to authenticated;
