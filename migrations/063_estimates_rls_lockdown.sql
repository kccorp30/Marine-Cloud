-- =========================================================
-- 063_estimates_rls_lockdown.sql — Marine Cloud Phase 6
-- =========================================================
-- Aprendiendo de las rondas de hardening de Phase 4B/5 — acá se hace
-- bien desde el inicio: SOLO SELECT va a `authenticated` en las 5
-- tablas nuevas. Ninguna mutación directa. Todo pasa por funciones
-- SECURITY DEFINER.
-- =========================================================

alter table estimates enable row level security;
alter table estimate_versions enable row level security;
alter table estimate_line_items enable row level security;
alter table estimate_decisions enable row level security;
alter table estimate_number_counters enable row level security;

create policy "read_estimates" on estimates for select
using (is_kcc_admin() or is_org_staff(organization_id) or is_own_customer_record(customer_id));

revoke all on estimates from anon, authenticated;
grant select on estimates to authenticated;

create policy "read_estimate_versions" on estimate_versions for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (status != 'draft' and exists (
    select 1 from estimates e where e.id = estimate_versions.estimate_id and is_own_customer_record(e.customer_id)
  ))
);

revoke all on estimate_versions from anon, authenticated;
grant select on estimate_versions to authenticated;

create policy "read_estimate_line_items" on estimate_line_items for select
using (
  is_kcc_admin()
  or exists (select 1 from estimate_versions v where v.id = estimate_line_items.estimate_version_id and is_org_staff(v.organization_id))
  or (
    customer_visible = true
    and exists (
      select 1 from estimate_versions v
      join estimates e on e.id = v.estimate_id
      where v.id = estimate_line_items.estimate_version_id and v.status != 'draft' and is_own_customer_record(e.customer_id)
    )
  )
);

revoke all on estimate_line_items from anon, authenticated;
grant select on estimate_line_items to authenticated;

create policy "read_estimate_decisions" on estimate_decisions for select
using (is_kcc_admin() or is_org_staff(organization_id) or is_own_customer_record(customer_id));

revoke all on estimate_decisions from anon, authenticated;
grant select on estimate_decisions to authenticated;

-- estimate_number_counters: RLS habilitada A PROPÓSITO sin ninguna
-- policy — nadie via authenticated/anon la toca jamás, ni para leer.
-- Solo generate_estimate_number() (revocada de authenticated) la usa,
-- y como SECURITY DEFINER bypasea RLS igual.
revoke all on estimate_number_counters from anon, authenticated;
