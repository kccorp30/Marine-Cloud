-- =========================================================
-- 106_commercial_send_functions.sql — Marine Cloud Phase 8
-- =========================================================
-- Envíos comerciales (estimate/invoice/payment receipt) restringidos
-- a company_owner/company_admin/manager — NUNCA technician. Los
-- montos SIEMPRE se resuelven server-side desde el registro real.
-- Idempotencia real vía p_idempotency_key. Verificado con datos
-- reales: técnico bloqueado de enviar email de estimate, admin sí
-- puede, llamar dos veces con la misma key no duplica el mensaje.
-- =========================================================

alter table messages add column idempotency_key text;
create unique index uq_messages_idempotency_key on messages(conversation_id, idempotency_key) where idempotency_key is not null;

create or replace function is_commercial_sender(p_organization_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select is_kcc_admin() or exists (
    select 1 from organization_memberships
    where profile_id = auth.uid() and organization_id = p_organization_id and status = 'active'
      and role in ('company_owner', 'company_admin', 'manager')
  );
$$;

revoke execute on function is_commercial_sender(uuid) from public, anon;
grant execute on function is_commercial_sender(uuid) to authenticated;

create or replace function send_estimate_email(
  p_estimate_id uuid,
  p_body_original text,
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
  v_conversation_id uuid;
  v_message_id uuid;
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

  v_conversation_id := get_or_create_conversation(v_estimate.organization_id, v_estimate.customer_id, v_estimate.vessel_id, v_estimate.work_order_id, null,
    (case when v_estimate.type = 'change_order' then 'Change Order ' else 'Estimate ' end) || v_estimate.estimate_number);

  if p_idempotency_key is not null and exists (select 1 from messages where conversation_id = v_conversation_id and idempotency_key = p_idempotency_key::text) then
    select id into v_message_id from messages where conversation_id = v_conversation_id and idempotency_key = p_idempotency_key::text;
    return v_message_id;
  end if;

  v_message_id := send_message(v_conversation_id, 'email', p_body_original);
  update messages set idempotency_key = p_idempotency_key::text where id = v_message_id and p_idempotency_key is not null;

  perform log_domain_event(v_estimate.organization_id, 'ESTIMATE_EMAIL_SENT', 'estimate', p_estimate_id,
    jsonb_build_object('message_id', v_message_id, 'total', v_version.total));
  perform log_audit_event(v_estimate.organization_id, 'estimate', p_estimate_id, 'estimate_email_sent',
    null, jsonb_build_object('message_id', v_message_id));

  return v_message_id;
end;
$$;

revoke execute on function send_estimate_email(uuid, text, uuid) from public, anon;
grant execute on function send_estimate_email(uuid, text, uuid) to authenticated;

create or replace function send_invoice_email(
  p_invoice_id uuid,
  p_body_original text,
  p_idempotency_key uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice invoices%rowtype;
  v_conversation_id uuid;
  v_message_id uuid;
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

  v_conversation_id := get_or_create_conversation(v_invoice.organization_id, v_invoice.customer_id, v_invoice.vessel_id, v_invoice.work_order_id, null, 'Invoice ' || v_invoice.invoice_number);

  if p_idempotency_key is not null and exists (select 1 from messages where conversation_id = v_conversation_id and idempotency_key = p_idempotency_key::text) then
    select id into v_message_id from messages where conversation_id = v_conversation_id and idempotency_key = p_idempotency_key::text;
    return v_message_id;
  end if;

  v_message_id := send_message(v_conversation_id, 'email', p_body_original);
  update messages set idempotency_key = p_idempotency_key::text where id = v_message_id and p_idempotency_key is not null;

  perform log_domain_event(v_invoice.organization_id, 'INVOICE_EMAIL_SENT', 'invoice', p_invoice_id,
    jsonb_build_object('message_id', v_message_id, 'total', v_invoice.total, 'balance_due', v_invoice.balance_due));
  perform log_audit_event(v_invoice.organization_id, 'invoice', p_invoice_id, 'invoice_email_sent',
    null, jsonb_build_object('message_id', v_message_id));

  return v_message_id;
end;
$$;

revoke execute on function send_invoice_email(uuid, text, uuid) from public, anon;
grant execute on function send_invoice_email(uuid, text, uuid) to authenticated;

create or replace function send_payment_receipt_email(
  p_payment_id uuid,
  p_body_original text,
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
  v_conversation_id uuid;
  v_message_id uuid;
begin
  select * into v_payment from payments where id = p_payment_id;
  if v_payment.id is null then
    raise exception 'payment not found';
  end if;
  if not is_commercial_sender(v_payment.organization_id) then
    raise exception 'not authorized to send commercial communications';
  end if;

  select * into v_invoice from invoices where id = v_payment.invoice_id;

  v_conversation_id := get_or_create_conversation(v_payment.organization_id, v_payment.customer_id, v_invoice.vessel_id, v_payment.work_order_id, null, 'Payment Receipt');

  if p_idempotency_key is not null and exists (select 1 from messages where conversation_id = v_conversation_id and idempotency_key = p_idempotency_key::text) then
    select id into v_message_id from messages where conversation_id = v_conversation_id and idempotency_key = p_idempotency_key::text;
    return v_message_id;
  end if;

  v_message_id := send_message(v_conversation_id, 'email', p_body_original);
  update messages set idempotency_key = p_idempotency_key::text where id = v_message_id and p_idempotency_key is not null;

  perform log_domain_event(v_payment.organization_id, 'PAYMENT_RECEIPT_SENT', 'payment', p_payment_id,
    jsonb_build_object('message_id', v_message_id, 'amount', v_payment.amount, 'invoice_id', v_payment.invoice_id));

  return v_message_id;
end;
$$;

revoke execute on function send_payment_receipt_email(uuid, text, uuid) from public, anon;
grant execute on function send_payment_receipt_email(uuid, text, uuid) to authenticated;

create or replace function send_appointment_email(
  p_appointment_id uuid,
  p_body_original text,
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
  v_conversation_id uuid;
  v_message_id uuid;
begin
  select * into v_appt from appointments where id = p_appointment_id;
  if v_appt.id is null then
    raise exception 'appointment not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_appt.organization_id) or is_assigned_to_work_order(v_appt.work_order_id)) then
    raise exception 'not authorized';
  end if;

  select * into v_wo from work_orders where id = v_appt.work_order_id;

  v_conversation_id := get_or_create_conversation(v_appt.organization_id, v_wo.customer_id, v_wo.vessel_id, v_wo.id, null, 'Appointment Update');

  if p_idempotency_key is not null and exists (select 1 from messages where conversation_id = v_conversation_id and idempotency_key = p_idempotency_key::text) then
    select id into v_message_id from messages where conversation_id = v_conversation_id and idempotency_key = p_idempotency_key::text;
    return v_message_id;
  end if;

  v_message_id := send_message(v_conversation_id, 'email', p_body_original);
  update messages set idempotency_key = p_idempotency_key::text where id = v_message_id and p_idempotency_key is not null;

  perform log_domain_event(v_appt.organization_id, 'APPOINTMENT_CONFIRMATION_SENT', 'appointment', p_appointment_id,
    jsonb_build_object('message_id', v_message_id));

  return v_message_id;
end;
$$;

revoke execute on function send_appointment_email(uuid, text, uuid) from public, anon;
grant execute on function send_appointment_email(uuid, text, uuid) to authenticated;
