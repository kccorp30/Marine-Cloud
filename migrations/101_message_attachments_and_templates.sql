-- =========================================================
-- 101_message_attachments_and_templates.sql — Marine Cloud Phase 8
-- =========================================================
-- Adjuntos: referencia segura a media_assets ya existente — NO se
-- toca esa tabla (work_order_id sigue NOT NULL, misma limitación
-- documentada desde Phase 4B). Subir un archivo NUEVO directo al
-- chat queda fuera de esta fase, documentado como limitación.
-- Templates reutilizables por organización.
--
-- Hallazgo en el camino: media_assets no tenía
-- unique(id, organization_id) — se agrega acá, trivialmente seguro.
-- (messages.uq_messages_id_org ya la crea la migración 100 — quitada
-- de acá tras el hardening: una cadena limpia no puede repetir la
-- misma constraint dos veces.)
-- =========================================================

alter table media_assets add constraint uq_media_assets_id_org unique (id, organization_id);

create table message_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  message_id uuid not null references messages(id),
  media_asset_id uuid not null references media_assets(id),
  created_at timestamptz not null default now()
);

alter table message_attachments add constraint fk_attachments_message_same_org
  foreign key (message_id, organization_id) references messages(id, organization_id) not valid;
alter table message_attachments add constraint fk_attachments_media_same_org
  foreign key (media_asset_id, organization_id) references media_assets(id, organization_id) not valid;
alter table message_attachments validate constraint fk_attachments_message_same_org;
alter table message_attachments validate constraint fk_attachments_media_same_org;

alter table message_attachments enable row level security;
create policy "read_message_attachments" on message_attachments for select
using (
  is_kcc_admin()
  or exists (select 1 from messages m where m.id = message_attachments.message_id and is_org_staff(m.organization_id))
  or exists (
    select 1 from messages m join conversations c on c.id = m.conversation_id
    where m.id = message_attachments.message_id and m.status != 'draft' and is_own_customer_record(c.customer_id)
  )
);
revoke all on message_attachments from anon, authenticated;
grant select on message_attachments to authenticated;

create table message_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  name text not null,
  category text not null default 'general' check (category in ('general', 'estimate', 'invoice', 'appointment', 'service_request', 'welcome')),
  language text not null default 'en' check (language in ('en', 'es')),
  subject text,
  body text not null,
  is_active boolean not null default true,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_message_templates_org on message_templates(organization_id, category, is_active);

alter table message_templates enable row level security;
create policy "read_message_templates" on message_templates for select
using (is_kcc_admin() or is_org_staff(organization_id));
revoke all on message_templates from anon, authenticated;
grant select on message_templates to authenticated;
