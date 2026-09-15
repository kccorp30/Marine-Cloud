-- =========================================================
-- 123_notifications_core_schema.sql — Marine Cloud Phase 9
-- =========================================================
-- Paso 0 (reportado): nada de notifications/kcc_assistance existía.
-- domain_events ya tiene exactamente la forma documentada en
-- docs/notification-architecture-plan.md — ningún evento existente
-- se toca ni se renombra.
--
-- Hardening desde el día uno: RLS lockdown completo, deduplicación
-- real vía source_domain_event_id. Verificado con datos reales.
-- =========================================================

create table notifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  recipient_user_id uuid not null references profiles(id),
  event_type text not null,
  severity text not null check (severity in ('info', 'action_required', 'urgent', 'critical')),
  title text not null,
  body text,
  related_entity_type text,
  related_entity_id uuid,
  read_at timestamptz,
  acknowledgement_required boolean not null default false,
  acknowledged_at timestamptz,
  acknowledged_by uuid references profiles(id),
  delivery_channels text[] not null default array['in_app']::text[],
  delivery_status text not null default 'delivered' check (delivery_status in ('pending', 'delivered', 'failed')),
  source_domain_event_id uuid references domain_events(id),
  source_rule_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint chk_delivery_channels_supported check (delivery_channels <@ array['in_app', 'push', 'whatsapp', 'email', 'sms']::text[]),
  constraint chk_only_in_app_actually_delivered check (
    delivery_status != 'delivered' or delivery_channels <@ array['in_app']::text[]
  )
);

create unique index uq_notifications_dedup on notifications(source_domain_event_id, recipient_user_id, source_rule_id)
  where source_domain_event_id is not null and source_rule_id is not null;

create index idx_notifications_recipient on notifications(recipient_user_id, created_at desc) where read_at is null;
create index idx_notifications_org on notifications(organization_id, created_at desc);

alter table notifications enable row level security;

create policy "read_own_notifications" on notifications for select
using (is_kcc_admin() or recipient_user_id = auth.uid());

revoke all on notifications from anon, authenticated;
grant select on notifications to authenticated;
