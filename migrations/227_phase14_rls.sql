-- =========================================================
-- 227_phase14_rls.sql — Marine Cloud Phase 14
-- =========================================================
-- Planes públicos legibles por cualquiera. Suscripciones: solo la
-- propia organización, nunca la de otra. Ninguna mutación directa.
-- Verificado con datos reales: Org B no lee la suscripción de Org A.
-- =========================================================

alter table subscription_plans enable row level security;
alter table plan_module_entitlements enable row level security;
alter table organization_subscriptions enable row level security;

create policy "subscription_plans_read" on subscription_plans for select
using (
  is_kcc_admin()
  or (is_public = true and status = 'active')
  or exists (select 1 from organization_subscriptions os where os.plan_id = subscription_plans.id and os.organization_id in (
    select organization_id from organization_memberships where profile_id = auth.uid() and status = 'active'
  ))
);

create policy "plan_module_entitlements_read" on plan_module_entitlements for select
using (
  is_kcc_admin()
  or exists (select 1 from subscription_plans sp where sp.id = plan_module_entitlements.plan_id and sp.is_public = true and sp.status = 'active')
  or exists (
    select 1 from organization_subscriptions os
    join organization_memberships om on om.organization_id = os.organization_id
    where os.plan_id = plan_module_entitlements.plan_id and om.profile_id = auth.uid() and om.status = 'active'
  )
);

create policy "organization_subscriptions_read" on organization_subscriptions for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
);

revoke all on subscription_plans from anon;
revoke all on plan_module_entitlements from anon;
revoke all on organization_subscriptions from anon;
grant select on subscription_plans to authenticated;
grant select on plan_module_entitlements to authenticated;
grant select on organization_subscriptions to authenticated;
