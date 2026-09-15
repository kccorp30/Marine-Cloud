-- =========================================================
-- 012_vessel_media_storage_rls.sql — Marine Cloud Phase 0
-- =========================================================
-- Bucket privado separado del lead-media del sitio web (dominios
-- distintos a propósito — nunca se mezcla media operativa con media
-- de marketing/leads).

insert into storage.buckets (id, name, public, file_size_limit)
values ('vessel-media', 'vessel-media', false, 52428800)
on conflict (id) do nothing;

-- Convención de ruta {organization_id}/{resto}. Decisión Phase 0
-- (conservadora a propósito): solo personal de la compañía (no
-- customer) puede leer/escribir aquí, porque todavía no existe la
-- tabla media_assets con el campo `visibility` que decidirá qué ve
-- un customer — eso llega en Phase 1+. Mientras tanto, cero acceso
-- de customer es más seguro que acceso amplio por error.

create policy "staff_read_vessel_media"
  on storage.objects for select
  using (
    bucket_id = 'vessel-media'
    and (
      is_kcc_admin()
      or (storage.foldername(name))[1]::uuid in (
        select organization_id from organization_memberships
        where profile_id = auth.uid()
          and status = 'active'
          and role in ('company_owner','company_admin','manager','technician')
      )
    )
  );

create policy "staff_write_vessel_media"
  on storage.objects for insert
  with check (
    bucket_id = 'vessel-media'
    and (
      is_kcc_admin()
      or (storage.foldername(name))[1]::uuid in (
        select organization_id from organization_memberships
        where profile_id = auth.uid()
          and status = 'active'
          and role in ('company_owner','company_admin','manager','technician')
      )
    )
  );

create policy "staff_delete_vessel_media"
  on storage.objects for delete
  using (
    bucket_id = 'vessel-media'
    and (
      is_kcc_admin()
      or (storage.foldername(name))[1]::uuid in (
        select organization_id from organization_memberships
        where profile_id = auth.uid()
          and status = 'active'
          and role in ('company_owner','company_admin')
      )
    )
  );
