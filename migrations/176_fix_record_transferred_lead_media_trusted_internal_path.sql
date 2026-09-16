-- =========================================================
-- 176_fix_record_transferred_lead_media_trusted_internal_path.sql — Phase 11 true closure
-- =========================================================
-- BUG REAL: record_transferred_lead_media() exige
-- is_platform_trusted_actor() — pero el trigger automático de
-- registro de media corre con el rol de CUALQUIER staff normal que
-- crea el work order. Mismo patrón exacto ya resuelto para
-- attribute_kcc_work() en la migración 158.
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
  v_via_trusted_rpc boolean;
begin
  v_via_trusted_rpc := coalesce(current_setting('app.kcc_generated_via_trusted_rpc', true), '') = 'true';
  if not (is_platform_trusted_actor() or v_via_trusted_rpc) then
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
    organization_id, vessel_id, work_order_id, uploaded_by, category, storage_path, mime_type, size_bytes, visibility, client_generated_id, caption
  )
  select wo.organization_id, wo.vessel_id, v_wo_id, coalesce(auth.uid(), wo.created_by), 'before', p_storage_path, p_mime_type, p_size_bytes, 'customer_visible', v_client_id, p_file_name
  from work_orders wo where wo.id = v_wo_id
  returning id into v_media_id;

  return v_media_id;
end;
$$;

create or replace function auto_register_transferred_media_on_work_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_media jsonb;
  v_item jsonb;
begin
  if NEW.website_lead_id is null then
    return NEW;
  end if;

  select media into v_media from leads where id = NEW.website_lead_id;

  perform set_config('app.kcc_generated_via_trusted_rpc', 'true', true);

  for v_item in select * from jsonb_array_elements(coalesce(v_media, '[]'::jsonb))
  loop
    if v_item ? 'transferredPath' then
      begin
        perform record_transferred_lead_media(
          NEW.website_lead_id,
          v_item->>'transferredPath',
          v_item->>'fileName',
          v_item->>'mimeType',
          (v_item->>'sizeBytes')::bigint,
          v_item->>'kind'
        );
      exception when others then
        raise warning 'media registration failed for lead % item %: %', NEW.website_lead_id, v_item->>'fileName', sqlerrm;
      end;
    end if;
  end loop;

  perform set_config('app.kcc_generated_via_trusted_rpc', 'false', true);

  return NEW;
end;
$$;
