-- =========================================================
-- 197_warranty_rls.sql — Marine Cloud Phase 13
-- =========================================================
-- Customer ve solo SU garantía/reclamo. Ninguna mutación directa —
-- todo vía RPCs SECURITY DEFINER.
-- =========================================================

alter table warranties enable row level security;
alter table warranty_claims enable row level security;

create policy "warranties_read" on warranties for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or is_own_customer_record(customer_id)
);

create policy "warranty_claims_read" on warranty_claims for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or is_own_customer_record(customer_id)
);

revoke all on warranties from anon;
revoke all on warranty_claims from anon;
grant select on warranties to authenticated;
grant select on warranty_claims to authenticated;
