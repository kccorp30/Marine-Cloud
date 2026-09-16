-- =========================================================
-- 261_platform_billing_rls.sql — Marine Cloud Phase 15
-- =========================================================
create policy "billing_charges_read" on platform_billing_charges for select
using (
  is_kcc_admin()
  or exists (
    select 1 from organization_memberships om join organizations o on o.id = om.organization_id
    where om.profile_id = auth.uid() and om.organization_id = platform_billing_charges.organization_id
      and om.status = 'active' and om.role in ('company_owner', 'company_admin') and o.status = 'active'
  )
);

create policy "payment_methods_read" on platform_payment_methods for select
using (active = true or is_kcc_admin());

create policy "platform_payments_read" on platform_payments for select
using (
  is_kcc_admin()
  or exists (
    select 1 from organization_memberships om join organizations o on o.id = om.organization_id
    where om.profile_id = auth.uid() and om.organization_id = platform_payments.organization_id
      and om.status = 'active' and om.role in ('company_owner', 'company_admin') and o.status = 'active'
  )
);

create policy "payment_evidence_read" on platform_payment_evidence for select
using (
  is_kcc_admin()
  or exists (
    select 1 from organization_memberships om join organizations o on o.id = om.organization_id
    where om.profile_id = auth.uid() and om.organization_id = platform_payment_evidence.organization_id
      and om.status = 'active' and om.role in ('company_owner', 'company_admin') and o.status = 'active'
  )
);

create policy "allocations_read" on platform_payment_allocations for select
using (
  is_kcc_admin()
  or exists (
    select 1 from platform_payments pp
    join organization_memberships om on om.organization_id = pp.organization_id
    join organizations o on o.id = om.organization_id
    where pp.id = platform_payment_allocations.payment_id
      and om.profile_id = auth.uid() and om.status = 'active' and om.role in ('company_owner', 'company_admin') and o.status = 'active'
  )
);

create policy "ledger_kcc_only" on platform_ledger_entries for select using (is_kcc_admin());

revoke all on platform_billing_charges from anon;
revoke all on platform_payment_methods from anon;
revoke all on platform_payments from anon;
revoke all on platform_payment_evidence from anon;
revoke all on platform_payment_allocations from anon;
revoke all on platform_ledger_entries from anon;
grant select on platform_billing_charges to authenticated;
grant select on platform_payment_methods to authenticated;
grant select on platform_payments to authenticated;
grant select on platform_payment_evidence to authenticated;
grant select on platform_payment_allocations to authenticated;
grant select on platform_ledger_entries to authenticated;
