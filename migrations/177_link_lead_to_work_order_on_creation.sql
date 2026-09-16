-- =========================================================
-- 177_link_lead_to_work_order_on_creation.sql — Phase 11 true closure
-- =========================================================
-- BUG REAL Y GENUINO: NADA actualizaba leads.marine_cloud_work_order_id
-- cuando nacía un work order originado en un lead del sitio —
-- record_transferred_lead_media() siempre rechazaba (correctamente,
-- según su propio chequeo) porque esa columna quedaba NULL para
-- siempre. Esto habría fallado también en producción real.
--
-- Verificado con datos reales de punta a punta: el lead queda
-- enlazado al work order real, solo el item con transferredPath
-- verificado se registra en media_assets con el path correcto y
-- visibility='customer_visible', el item sin transferir nunca se
-- registra.
-- =========================================================

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

  update leads set marine_cloud_work_order_id = NEW.id, updated_at = now()
  where id = NEW.website_lead_id and marine_cloud_work_order_id is null;

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
