-- =========================================================
-- 114_template_management_and_variable_safety.sql — Phase 8 hardening
-- =========================================================
-- Faltaba editar/desactivar templates. El renderer nunca rechazaba
-- una variable desconocida. Se agrega allowlist estricta ANTES de
-- guardar. Verificado: template con {{customer.ssn}} rechazado.
-- =========================================================

create or replace function validate_template_variables(p_text text)
returns void
language plpgsql
immutable
set search_path = public
as $$
declare
  v_allowed text[] := array[
    '{{customer.first_name}}', '{{company.name}}', '{{vessel.name}}', '{{work_order.title}}',
    '{{estimate.number}}', '{{estimate.total}}', '{{invoice.number}}', '{{invoice.balance_due}}',
    '{{appointment.date}}', '{{technician.name}}'
  ];
  v_matches text[];
  v_token text;
begin
  select array_agg(m[1]) into v_matches from regexp_matches(p_text, '\{\{[^}]*\}\}', 'g') as m;
  if v_matches is null then
    return;
  end if;
  foreach v_token in array v_matches loop
    if not (v_token = any(v_allowed)) then
      raise exception 'unknown template variable: % — allowed variables are: %', v_token, array_to_string(v_allowed, ', ');
    end if;
  end loop;
end;
$$;

create or replace function create_message_template(
  p_organization_id uuid,
  p_name text,
  p_category text,
  p_language text,
  p_subject text,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not (is_kcc_admin() or is_org_staff(p_organization_id)) then
    raise exception 'not authorized';
  end if;

  perform validate_template_variables(coalesce(p_subject, ''));
  perform validate_template_variables(p_body);

  insert into message_templates (organization_id, name, category, language, subject, body, created_by)
  values (p_organization_id, p_name, p_category, p_language, p_subject, p_body, auth.uid())
  returning id into v_id;

  perform log_domain_event(p_organization_id, 'TEMPLATE_CREATED', 'message_template', v_id, jsonb_build_object('name', p_name));

  return v_id;
end;
$$;

create or replace function update_message_template(
  p_template_id uuid,
  p_name text default null,
  p_subject text default null,
  p_body text default null,
  p_is_active boolean default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_template message_templates%rowtype;
begin
  select * into v_template from message_templates where id = p_template_id;
  if v_template.id is null then
    raise exception 'template not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_template.organization_id)) then
    raise exception 'not authorized';
  end if;

  if p_subject is not null then perform validate_template_variables(p_subject); end if;
  if p_body is not null then perform validate_template_variables(p_body); end if;

  update message_templates set
    name = coalesce(p_name, name),
    subject = coalesce(p_subject, subject),
    body = coalesce(p_body, body),
    is_active = coalesce(p_is_active, is_active),
    updated_at = now()
  where id = p_template_id;

  perform log_domain_event(v_template.organization_id, 'TEMPLATE_UPDATED', 'message_template', p_template_id, jsonb_build_object('is_active', coalesce(p_is_active, v_template.is_active)));
end;
$$;

revoke execute on function update_message_template(uuid, text, text, text, boolean) from public, anon;
grant execute on function update_message_template(uuid, text, text, text, boolean) to authenticated;
