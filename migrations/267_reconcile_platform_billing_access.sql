-- =========================================================
-- 267_reconcile_platform_billing_access.sql — Marine Cloud Phase 15
-- =========================================================
-- Nunca reactiva organización archivada ni suscripción cancelada.
-- Termina grace_period/past_due si el balance real queda al día.
-- Reintenta leads bloqueados. Verificado con datos reales: acceso
-- restaurado desde past_due, lead bloqueado reintentado, organización
-- archivada NUNCA reactivada por esta función.
-- =========================================================

create or replace function reconcile_organization_platform_billing(p_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org organizations%rowtype;
  v_sub organization_subscriptions%rowtype;
  v_is_current boolean;
begin
  select * into v_org from organizations where id = p_organization_id;
  if v_org.id is null then
    return;
  end if;

  if v_org.status != 'active' then
    return;
  end if;

  select * into v_sub from organization_subscriptions where organization_id = p_organization_id and superseded_at is null;
  if v_sub.id is null then
    return;
  end if;

  if v_sub.status = 'cancelled' then
    return;
  end if;

  v_is_current := organization_billing_is_current(p_organization_id);

  if v_is_current and v_sub.status = 'grace_period' then
    update organization_subscriptions set status = 'active', grace_period_ends_at = null, updated_at = now()
    where id = v_sub.id;
    perform log_domain_event(p_organization_id, 'PLATFORM_ACCESS_RESTORED_AFTER_PAYMENT', 'organization', p_organization_id,
      jsonb_build_object('subscription_id', v_sub.id, 'previous_status', 'grace_period'));
  elsif v_is_current and v_sub.status = 'past_due' then
    update organization_subscriptions set status = 'active', updated_at = now()
    where id = v_sub.id;
    perform log_domain_event(p_organization_id, 'PLATFORM_ACCESS_RESTORED_AFTER_PAYMENT', 'organization', p_organization_id,
      jsonb_build_object('subscription_id', v_sub.id, 'previous_status', 'past_due'));
  end if;

  perform retry_commercially_blocked_leads(p_organization_id, 25);
end;
$$;

revoke execute on function reconcile_organization_platform_billing(uuid) from public, anon;
grant execute on function reconcile_organization_platform_billing(uuid) to authenticated;
