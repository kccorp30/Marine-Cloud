-- =========================================================
-- 192_qc_rls.sql — Marine Cloud Phase 13
-- =========================================================
-- Customer nunca lee QC interno — solo ve estado simplificado
-- derivado en la app. Staff/técnico asignado/kcc_admin sí. Ninguna
-- mutación directa — todo vía RPCs.
-- Verificado con datos reales: customer bloqueado, Org B bloqueada
-- tanto en SELECT como en start_qc_submission.
-- =========================================================

alter table qc_submissions enable row level security;
alter table qc_submission_items enable row level security;

create policy "qc_submissions_read" on qc_submissions for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (is_assigned_to_work_order(work_order_id))
);

create policy "qc_submission_items_read" on qc_submission_items for select
using (
  exists (
    select 1 from qc_submissions qs
    where qs.id = qc_submission_items.qc_submission_id
      and (is_kcc_admin() or is_org_staff(qs.organization_id) or is_assigned_to_work_order(qs.work_order_id))
  )
);

revoke all on qc_submissions from anon;
revoke all on qc_submission_items from anon;
grant select on qc_submissions to authenticated;
grant select on qc_submission_items to authenticated;
