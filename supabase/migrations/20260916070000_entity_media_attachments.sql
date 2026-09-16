-- Phase 2: customer/staff media for service requests, estimates and support conversations.
create table if not exists public.entity_media_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  entity_type text not null check (entity_type in ('service_request','estimate','conversation')),
  entity_id uuid not null,
  vessel_id uuid null,
  uploaded_by uuid not null references public.profiles(id),
  uploaded_by_role text not null check (uploaded_by_role in ('customer','staff','technician','kcc_admin')),
  visibility text not null default 'customer_visible' check (visibility in ('customer_visible','internal')),
  category text not null default 'reference' check (category in ('reference','damage','diagnosis','before','progress','after','document')),
  caption text null,
  storage_path text not null unique,
  mime_type text not null,
  size_bytes bigint null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz null
);

create index if not exists idx_entity_media_entity on public.entity_media_attachments(entity_type,entity_id,created_at desc) where deleted_at is null;
create index if not exists idx_entity_media_org on public.entity_media_attachments(organization_id,created_at desc) where deleted_at is null;

alter table public.entity_media_attachments enable row level security;

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
        where sr.id=entity_id and sr.organization_id=entity_media_attachments.organization_id and public.is_own_customer_record(sr.customer_id)
      )
    )
    or (
      visibility='customer_visible' and entity_type='estimate' and exists (
        select 1 from public.estimates e
        where e.id=entity_id and e.organization_id=entity_media_attachments.organization_id and public.is_own_customer_record(e.customer_id)
      )
    )
    or (
      visibility='customer_visible' and entity_type='conversation' and exists (
        select 1 from public.conversations c
        where c.id=entity_id and c.organization_id=entity_media_attachments.organization_id and public.is_own_customer_record(c.customer_id)
      )
    )
  )
);

-- Writes intentionally remain server-side through the trusted service client after explicit authorization.
revoke insert,update,delete on public.entity_media_attachments from anon,authenticated;
grant select on public.entity_media_attachments to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('portal-media','portal-media',false,12582912,array['image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict (id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;
