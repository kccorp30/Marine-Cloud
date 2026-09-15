-- =========================================================
-- 167_record_transferred_lead_media.sql — Marine Cloud Phase 11
-- =========================================================
-- La copia REAL de bytes (lead-media -> vessel-media) ocurre
-- server-side en el sitio (Storage API) — Postgres no puede copiar
-- bytes de storage por sí solo. Esta función solo registra la
-- metadata DESPUÉS de que el archivo ya fue copiado — trusted,
-- idempotente vía client_generated_id determinístico (mismo
-- storage_path siempre produce el mismo id). category='before',
-- visibility='customer_visible' — el customer subió estos archivos,
-- nunca deben volverse staff-only por accidente.
--
-- NOTA: esta versión tenía 2 bugs reales (schema de uuid_generate_v5,
-- vessel_id faltante) corregidos en 168 y 169 aplicadas por separado
-- inmediatamente después. Se deja tal cual se aplicó.
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
  v_category text;
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

  v_client_id := uuid_generate_v5('00000000-0000-0000-0000-000000000000'::uuid, p_storage_path);
  v_category := 'before';

  select id into v_media_id from media_assets where work_order_id = v_wo_id and client_generated_id = v_client_id;
  if v_media_id is not null then
    return v_media_id;
  end if;

  insert into media_assets (
    organization_id, work_order_id, uploaded_by, category, storage_path, mime_type, size_bytes, visibility, client_generated_id, caption
  )
  select wo.organization_id, v_wo_id, coalesce(auth.uid(), wo.created_by), v_category, p_storage_path, p_mime_type, p_size_bytes, 'customer_visible', v_client_id, p_file_name
  from work_orders wo where wo.id = v_wo_id
  returning id into v_media_id;

  return v_media_id;
end;
$$;

revoke execute on function record_transferred_lead_media(uuid, text, text, text, bigint, text) from public, anon;
grant execute on function record_transferred_lead_media(uuid, text, text, text, bigint, text) to authenticated;
