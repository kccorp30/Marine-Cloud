-- =========================================================
-- 168_fix_record_transferred_lead_media_uuid_schema.sql — Phase 11
-- =========================================================
-- BUG REAL: uuid_generate_v5() vive en el schema `extensions`
-- (convención de Supabase), no en `public` — search_path='public'
-- de la función no lo encontraba. Se califica el schema directo en
-- vez de ampliar el search_path.
-- =========================================================

create or replace function record_transferred_lead_media(
  p_lead_id uuid,
  p_storage_path text,
  p_file_name text,
  p_mime_type text,
  p_size_bytes bigint,
  p_kind text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lead leads%rowtype;
  v_wo_id uuid;
  v_client_id uuid;
  v_media_id uuid;
begin
  if not is_platform_trusted_actor() then
    raise exception 'only trusted platform infrastructure can register transferred lead media';
  end if;

  select * into v_lead from leads where id = p_lead_id;
  if v_lead.id is null then
    raise exception 'lead not found';
  end if;
  if v_lead.marine_cloud_work_order_id is null then
    raise exception 'lead has no associated work order yet — media can only be attached once conversion reaches a work order';
  end if;
  v_wo_id := v_lead.marine_cloud_work_order_id;

  v_client_id := extensions.uuid_generate_v5('00000000-0000-0000-0000-000000000000'::uuid, p_storage_path);

  select id into v_media_id from media_assets where work_order_id = v_wo_id and client_generated_id = v_client_id;
  if v_media_id is not null then
    return v_media_id;
  end if;

  insert into media_assets (
    organization_id, work_order_id, uploaded_by, category, storage_path, mime_type, size_bytes, visibility, client_generated_id, caption
  )
  select wo.organization_id, v_wo_id, coalesce(auth.uid(), wo.created_by), 'before', p_storage_path, p_mime_type, p_size_bytes, 'customer_visible', v_client_id, p_file_name
  from work_orders wo where wo.id = v_wo_id
  returning id into v_media_id;

  return v_media_id;
end;
$$;
