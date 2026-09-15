-- =========================================================
-- 254_fix_lifecycle_processor_cron_authority.sql — Phase 14 absolute final closure
-- =========================================================
-- BUG REAL: process_due_subscription_lifecycle_milestones() exigía
-- is_kcc_admin() OR is_platform_trusted_actor(), ambas dependientes
-- de claims JWT que NUNCA existen cuando pg_cron invoca la función
-- (corre sin contexto HTTP). El job de 253 habría fallado
-- silenciosamente cada hora en producción real. Detectado ejecutando
-- la función directamente sin contexto JWT (replicando el entorno
-- real de pg_cron) — nunca asumido solo porque cron.schedule() no
-- dio error. Corregido: ausencia TOTAL de contexto JWT (nunca un
-- actor equivocado, sino ningún actor) se trata como invocación
-- interna de plataforma confiable.
-- Verificado con datos reales: funciona sin JWT (contexto cron real),
-- sigue rechazando a un actor incorrecto CON JWT presente.
-- =========================================================

create or replace function process_due_subscription_lifecycle_milestones(p_batch_size int default 100)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_milestone subscription_lifecycle_milestones%rowtype;
  v_event_type text;
  v_processed_count int := 0;
  v_has_jwt_context boolean;
begin
  v_has_jwt_context := current_setting('request.jwt.claims', true) is not null and current_setting('request.jwt.claims', true) != '';

  if v_has_jwt_context and not (is_kcc_admin() or is_platform_trusted_actor()) then
    raise exception 'not authorized to process lifecycle milestones';
  end if;

  for v_milestone in
    select * from subscription_lifecycle_milestones
    where processed_at is null and scheduled_for <= now()
    order by scheduled_for asc
    limit p_batch_size
    for update skip locked
  loop
    v_event_type := case v_milestone.milestone
      when 'trial_7d' then 'SUBSCRIPTION_TRIAL_7_DAYS_REMAINING'
      when 'trial_3d' then 'SUBSCRIPTION_TRIAL_3_DAYS_REMAINING'
      when 'trial_1d' then 'SUBSCRIPTION_TRIAL_1_DAY_REMAINING'
      when 'trial_expired' then 'SUBSCRIPTION_TRIAL_EXPIRED'
      when 'grace_expired' then 'SUBSCRIPTION_GRACE_PERIOD_EXPIRED'
      when 'scheduled_cancellation' then 'SUBSCRIPTION_CANCELLED'
    end;

    update subscription_lifecycle_milestones set processed_at = now() where id = v_milestone.id;

    perform log_domain_event(v_milestone.organization_id, v_event_type, 'organization', v_milestone.organization_id,
      jsonb_build_object('subscription_id', v_milestone.subscription_id, 'milestone', v_milestone.milestone));

    v_processed_count := v_processed_count + 1;
  end loop;

  return jsonb_build_object('processed', v_processed_count);
end;
$$;
