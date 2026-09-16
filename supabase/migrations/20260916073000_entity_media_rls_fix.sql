drop policy if exists entity_media_read on public.entity_media_attachments;
create policy entity_media_read on public.entity_media_attachments
for select to authenticated
using (
  deleted_at is null and (
    public.is_kcc_admin()
    or public.is_org_staff(organization_id)
    or (
      visibility='customer_visible' and entity_type='service_request' and exists (
        select 1 from public.service_requests sr
        where sr.id=entity_media_attachments.entity_id
          and sr.organization_id=entity_media_attachments.organization_id
          and public.is_own_customer_record(sr.customer_id)
      )
    )
    or (
      visibility='customer_visible' and entity_type='estimate' and exists (
        select 1 from public.estimates e
        where e.id=entity_media_attachments.entity_id
          and e.organization_id=entity_media_attachments.organization_id
          and public.is_own_customer_record(e.customer_id)
      )
    )
    or (
      visibility='customer_visible' and entity_type='conversation' and exists (
        select 1 from public.conversations c
        where c.id=entity_media_attachments.entity_id
          and c.organization_id=entity_media_attachments.organization_id
          and public.is_own_customer_record(c.customer_id)
      )
    )
  )
);
