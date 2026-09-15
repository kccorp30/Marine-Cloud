-- =========================================================
-- 175_auto_register_transferred_media_on_work_order.sql — Phase 11 true closure
-- =========================================================
-- La transferencia REAL de bytes (lead-media -> vessel-media) ocurre
-- en convertLead() del sitio, en la etapa de service_request (apenas
-- se resuelve el vessel) — el path final verificado queda en
-- leads.media[].transferredPath. Este trigger completa el lazo
-- puramente en SQL: en el momento en que el work order nace, lee
-- leads.media directo y registra la metadata SOLO para cada item que
-- YA tiene transferredPath verificado — nunca inventa un path.
--
-- NOTA: esta versión tenía 2 bugs reales encontrados al probarla,
-- corregidos en las migraciones 176 y 177 aplicadas por separado
-- inmediatamente después. Se deja tal cual se aplicó.
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

  select media into v_media from leads where id = NEW.website_lead_id;

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

  return NEW;
end;
$$;

create trigger trg_auto_register_transferred_media_on_work_order
  after insert on work_orders
  for each row execute function auto_register_transferred_media_on_work_order();

revoke execute on function auto_register_transferred_media_on_work_order() from public, anon, authenticated;
