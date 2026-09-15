-- =========================================================
-- 105_render_message_template.sql — Marine Cloud Phase 8
-- =========================================================
-- Reemplazo de variables — SOLO desde registros reales de la base,
-- nunca texto que mande el cliente para el valor en sí. Variable no
-- disponible -> se omite limpio (string vacío), nunca un valor
-- inventado. work_orders no tiene un campo "number" — se usa
-- {{work_order.title}} en su lugar, desviación menor documentada.
--
-- NOTA: esta versión tenía un bug real (el subject solo aplicaba
-- {{customer.first_name}}, el resto de variables quedaban sin
-- reemplazar si aparecían ahí) — corregido en 107, aplicada por
-- separado inmediatamente después.
-- =========================================================

create or replace function render_message_template(
  p_template_id uuid,
  p_customer_id uuid,
  p_vessel_id uuid default null,
  p_work_order_id uuid default null,
  p_estimate_id uuid default null,
  p_invoice_id uuid default null,
  p_appointment_id uuid default null
)
returns table(rendered_subject text, rendered_body text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_template message_templates%rowtype;
  v_subject text;
  v_body text;
  v_customer customers%rowtype;
  v_org organizations%rowtype;
  v_vessel vessels%rowtype;
  v_wo work_orders%rowtype;
  v_estimate_number text;
  v_estimate_total numeric;
  v_invoice_number text;
  v_invoice_balance numeric;
  v_appt_date text;
  v_tech_name text;
begin
  select * into v_template from message_templates where id = p_template_id;
  if v_template.id is null then
    raise exception 'template not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_template.organization_id)) then
    raise exception 'not authorized';
  end if;

  select * into v_customer from customers where id = p_customer_id and organization_id = v_template.organization_id;
  if v_customer.id is null then
    raise exception 'customer does not belong to this organization';
  end if;

  select * into v_org from organizations where id = v_template.organization_id;

  if p_vessel_id is not null then
    select * into v_vessel from vessels where id = p_vessel_id and organization_id = v_template.organization_id;
  end if;
  if p_work_order_id is not null then
    select * into v_wo from work_orders where id = p_work_order_id and organization_id = v_template.organization_id;
    select p.full_name into v_tech_name from assignments a join profiles p on p.id = a.technician_profile_id
    where a.work_order_id = p_work_order_id and a.status = 'active' limit 1;
  end if;
  if p_estimate_id is not null then
    select e.estimate_number, ev.total into v_estimate_number, v_estimate_total
    from estimates e join estimate_versions ev on ev.id = e.current_version_id
    where e.id = p_estimate_id and e.organization_id = v_template.organization_id;
  end if;
  if p_invoice_id is not null then
    select invoice_number, balance_due into v_invoice_number, v_invoice_balance
    from invoices where id = p_invoice_id and organization_id = v_template.organization_id;
  end if;
  if p_appointment_id is not null then
    select to_char(scheduled_start, 'FMMonth DD, YYYY "at" HH12:MI AM') into v_appt_date
    from appointments where id = p_appointment_id and organization_id = v_template.organization_id;
  end if;

  v_subject := coalesce(v_template.subject, '');
  v_body := v_template.body;

  v_subject := replace(v_subject, '{{customer.first_name}}', coalesce(v_customer.first_name, ''));
  v_body := replace(v_body, '{{customer.first_name}}', coalesce(v_customer.first_name, ''));
  v_body := replace(v_body, '{{company.name}}', coalesce(v_org.name, ''));
  v_body := replace(v_body, '{{vessel.name}}', coalesce(v_vessel.name, ''));
  v_body := replace(v_body, '{{work_order.title}}', coalesce(v_wo.title, ''));
  v_body := replace(v_body, '{{estimate.number}}', coalesce(v_estimate_number, ''));
  v_body := replace(v_body, '{{estimate.total}}', coalesce(to_char(v_estimate_total, 'FM999,999,990.00'), ''));
  v_body := replace(v_body, '{{invoice.number}}', coalesce(v_invoice_number, ''));
  v_body := replace(v_body, '{{invoice.balance_due}}', coalesce(to_char(v_invoice_balance, 'FM999,999,990.00'), ''));
  v_body := replace(v_body, '{{appointment.date}}', coalesce(v_appt_date, ''));
  v_body := replace(v_body, '{{technician.name}}', coalesce(v_tech_name, ''));

  return query select v_subject, v_body;
end;
$$;

revoke execute on function render_message_template(uuid, uuid, uuid, uuid, uuid, uuid, uuid) from public, anon;
grant execute on function render_message_template(uuid, uuid, uuid, uuid, uuid, uuid, uuid) to authenticated;
