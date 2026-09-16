-- =========================================================
-- 239_tighten_subscription_visibility_owner_admin_only.sql — Phase 14 final integrity
-- =========================================================
-- DECISIÓN EXPLÍCITA: is_org_staff() incluye manager, pero los
-- términos comerciales de suscripción son información financiera
-- sensible, no visibilidad operacional general — restringido a
-- company_owner/company_admin únicamente.
-- Verificado con datos reales: manager no puede leer la suscripción.
-- =========================================================

drop policy "organization_subscriptions_read" on organization_subscriptions;
create policy "organization_subscriptions_read" on organization_subscriptions for select
using (
  is_kcc_admin()
  or exists (
    select 1 from organization_memberships om join organizations o on o.id = om.organization_id
    where om.profile_id = auth.uid() and om.organization_id = organization_subscriptions.organization_id
      and om.status = 'active' and om.role in ('company_owner', 'company_admin') and o.status = 'active'
  )
);
