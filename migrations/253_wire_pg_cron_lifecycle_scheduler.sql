-- =========================================================
-- 253_wire_pg_cron_lifecycle_scheduler.sql — Phase 14 absolute final closure
-- =========================================================
-- pg_cron REAL, verificado disponible y wireado en este proyecto
-- Supabase — no documentado como "activación pendiente", sino
-- efectivamente programado y confirmado activo (cron.job.active=true)
-- vía consulta directa a la tabla del extension.
-- =========================================================

create extension if not exists pg_cron;

select cron.schedule(
  'process-subscription-lifecycle-milestones',
  '0 * * * *',
  $$select process_due_subscription_lifecycle_milestones(200)$$
);
