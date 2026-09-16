-- =========================================================
-- 011_events_read_policies.sql — Marine Cloud Phase 0
-- =========================================================

-- Domain events: miembros activos de la organización + kcc_admin.
-- La visibilidad diferenciada por rol (qué eventos ve un customer vs
-- un technician) se refina en Phase 3 — por ahora, cualquier miembro
-- ve los eventos de SU organización.
create policy "org_members_read_domain_events"
  on domain_events for select
  using (
    is_kcc_admin()
    or organization_id in (
      select organization_id from organization_memberships
      where profile_id = auth.uid() and status = 'active'
    )
  );

-- Audit events: kcc_admin ve todo; company_owner/company_admin ven
-- los de su propia organización (accountability), nadie más.
create policy "admins_read_audit_events"
  on audit_events for select
  using (
    is_kcc_admin()
    or organization_id in (
      select organization_id from organization_memberships
      where profile_id = auth.uid()
        and status = 'active'
        and role in ('company_owner', 'company_admin')
    )
  );
