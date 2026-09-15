-- =========================================================
-- 100_communications_core_schema.sql — Marine Cloud Phase 8
-- =========================================================
-- Paso 0 (reportado): no existe ningún conversations/messages previo.
-- docs/notification-architecture-plan.md y
-- docs/notification-event-mapping.md SÍ existen pero describen un
-- Notification Center INTERNO (alertas in-app, badges, sonido) para
-- una fase separada — no se solapan con este Phase 8 (comunicación
-- con el customer vía email/mensajes). Se reusa: customers.email,
-- organizations.branding_json/phone/email, organization_settings.locale.
--
-- Hardening aplicado desde el día uno: RLS lockdown completo, FKs
-- compuestas tenant-safe, visibilidad del customer basada en
-- evidencia real (status != 'draft'), no solo texto simple.
-- Verificado con datos reales: body_original nunca sobreescrito al
-- traducir, customer ve mensajes enviados, técnico bloqueado de
-- crear conversación.
-- =========================================================

create table conversations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  customer_id uuid not null,
  vessel_id uuid references vessels(id),
  work_order_id uuid references work_orders(id),
  service_request_id uuid references service_requests(id),
  status text not null default 'open' check (status in ('open', 'closed', 'archived')),
  subject text,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_message_at timestamptz,

  constraint fk_conversations_customer_same_org foreign key (customer_id, organization_id) references customers(id, organization_id)
);

alter table conversations add constraint uq_conversations_id_org unique (id, organization_id);
alter table conversations add constraint fk_conversations_vessel_same_org
  foreign key (vessel_id, organization_id) references vessels(id, organization_id) not valid;
alter table conversations add constraint fk_conversations_work_order_same_org
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id) not valid;
alter table conversations add constraint fk_conversations_service_request_same_org
  foreign key (service_request_id, organization_id) references service_requests(id, organization_id) not valid;
alter table conversations validate constraint fk_conversations_vessel_same_org;
alter table conversations validate constraint fk_conversations_work_order_same_org;
alter table conversations validate constraint fk_conversations_service_request_same_org;

create index idx_conversations_org_customer on conversations(organization_id, customer_id, last_message_at desc);

create table messages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  conversation_id uuid not null references conversations(id),
  sender_type text not null check (sender_type in ('staff', 'customer', 'system')),
  sender_profile_id uuid references profiles(id),
  customer_id uuid,
  direction text not null check (direction in ('outbound', 'inbound')),
  channel text not null check (channel in ('internal', 'email')),
  body_original text not null,
  body_rendered text,
  language_original text,
  language_rendered text,
  status text not null default 'draft' check (status in ('draft', 'sent', 'delivered', 'failed')),
  provider_message_id text,
  reply_to_message_id uuid references messages(id),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  delivered_at timestamptz,
  failed_at timestamptz,
  failure_reason text
);

alter table messages add constraint uq_messages_id_org unique (id, organization_id);
alter table messages add constraint fk_messages_conversation_same_org
  foreign key (conversation_id, organization_id) references conversations(id, organization_id) not valid;
alter table messages validate constraint fk_messages_conversation_same_org;

create index idx_messages_conversation on messages(conversation_id, created_at);
create unique index uq_messages_provider_message_id on messages(provider_message_id) where provider_message_id is not null;

alter table conversations enable row level security;
alter table messages enable row level security;

create policy "read_conversations" on conversations for select
using (is_kcc_admin() or is_org_staff(organization_id) or is_own_customer_record(customer_id));

revoke all on conversations from anon, authenticated;
grant select on conversations to authenticated;

create policy "read_messages" on messages for select
using (
  is_kcc_admin()
  or exists (select 1 from conversations c where c.id = messages.conversation_id and is_org_staff(c.organization_id))
  or (
    status != 'draft'
    and exists (select 1 from conversations c where c.id = messages.conversation_id and is_own_customer_record(c.customer_id))
  )
);

revoke all on messages from anon, authenticated;
grant select on messages to authenticated;
