-- =========================================================
-- 116_fix_advisor_findings.sql — Phase 8 hardening
-- =========================================================
-- Hallazgos reales del advisor: send_message() era callable por
-- anon (no debería); validate_template_variables tenía search_path
-- mutable.
-- =========================================================

revoke execute on function send_message(uuid, text, text, text, text, text, text, boolean, text) from anon;

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
