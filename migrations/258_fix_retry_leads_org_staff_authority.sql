-- =========================================================
-- 258_fix_retry_leads_org_staff_authority.sql — Phase 14 lifecycle consistency
-- =========================================================
-- BUG REAL encontrado probando 257: retry_commercially_blocked_leads()
-- se rechazaba a sí misma cuando select_organization_plan() (JWT real
-- de company_owner) la invocaba internamente. Corregido agregando
-- is_org_staff(p_organization_id) como autoridad válida.
-- Verificado con datos reales de punta a punta: trial vencido con
-- lead bloqueado -> owner selecciona plan -> lead se convierte
-- automáticamente.
-- =========================================================

create or replace function retry_commercially_blocked_leads(p_organization_id uuid, p_batch_size int default 25)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lead_id uuid;
  v_result jsonb;
  v_converted_count int := 0;
  v_still_blocked_count int := 0;
  v_failed_count int := 0;
begin
  if not (is_kcc_admin() or is_platform_trusted_actor() or is_org_staff(p_organization_id)) then
    raise exception 'not authorized to retry blocked leads';
  end if;
  if p_batch_size is null or p_batch_size <= 0 or p_batch_size > 100 then
    raise exception 'batch size must be between 1 and 100';
  end if;

  for v_lead_id in
    select id from leads
    where assigned_organization_id = p_organization_id and conversion_status = 'blocked_commercial'
    order by created_at asc
    limit p_batch_size
  loop
    begin
      v_result := convert_website_lead(v_lead_id);
      case v_result->>'status'
        when 'created' then v_converted_count := v_converted_count + 1;
        when 'blocked_commercial' then v_still_blocked_count := v_still_blocked_count + 1;
        else v_failed_count := v_failed_count + 1;
      end case;
    exception when others then
      v_failed_count := v_failed_count + 1;
    end;
  end loop;

  return jsonb_build_object('organization_id', p_organization_id, 'converted', v_converted_count, 'still_blocked', v_still_blocked_count, 'failed', v_failed_count);
end;
$$;
