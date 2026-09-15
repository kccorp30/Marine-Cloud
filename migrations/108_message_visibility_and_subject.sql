-- =========================================================
-- 108_message_visibility_and_subject.sql — Phase 8 hardening
-- =========================================================
-- BUG REAL Y GRAVE: la política de messages solo miraba status !=
-- 'draft' — un mensaje channel='internal' enviado se volvía visible
-- al customer igual, porque su status SÍ pasaba a 'sent'. Se agrega
-- customer_visible explícito — nunca inferido solo del status. Se
-- agrega subject durable y el estado 'queued'.
-- Verificado con datos reales: nota interna nunca visible al
-- customer, incluso después de "enviada".
-- =========================================================

alter table messages add column customer_visible boolean not null default true;
alter table messages add column subject text;

alter table messages drop constraint messages_status_check;
alter table messages add constraint messages_status_check check (status in ('draft', 'queued', 'sent', 'delivered', 'failed'));

alter table messages drop constraint messages_channel_check;
alter table messages add constraint messages_channel_check check (channel in ('internal', 'email'));

alter table messages add constraint chk_internal_never_customer_visible
  check (channel != 'internal' or customer_visible = false);

drop policy if exists "read_messages" on messages;
create policy "read_messages" on messages for select
using (
  is_kcc_admin()
  or exists (select 1 from conversations c where c.id = messages.conversation_id and is_org_staff(c.organization_id))
  or (
    customer_visible = true
    and status in ('sent', 'delivered', 'failed')
    and exists (select 1 from conversations c where c.id = messages.conversation_id and is_own_customer_record(c.customer_id))
  )
);
