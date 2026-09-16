-- =========================================================
-- 034_phase2_storage_policy_tightening.sql — Marine Cloud Phase 2
-- =========================================================
-- Reemplaza las políticas de vessel-media de Phase 0 (acceso a
-- cualquier technician de la organización) por unas que exigen
-- asignación real al work order específico. Nueva convención de ruta:
-- {organization_id}/{work_order_id}/{category}/{archivo}

drop policy if exists "staff_read_vessel_media" on storage.objects;
drop policy if exists "staff_write_vessel_media" on storage.objects;
drop policy if exists "staff_delete_vessel_media" on storage.objects;

create policy "read_vessel_media_scoped"
  on storage.objects for select
  using (
    bucket_id = 'vessel-media'
    and (
      is_kcc_admin()
      or is_org_staff((storage.foldername(name))[1]::uuid)
      or is_assigned_to_work_order((storage.foldername(name))[2]::uuid)
      or exists (
        select 1 from media_assets
        where storage_path = name
          and visibility = 'customer_visible'
          and is_customer_of_work_order(work_order_id)
      )
    )
  );

create policy "write_vessel_media_scoped"
  on storage.objects for insert
  with check (
    bucket_id = 'vessel-media'
    and (
      is_kcc_admin()
      or is_org_staff((storage.foldername(name))[1]::uuid)
      or is_assigned_to_work_order((storage.foldername(name))[2]::uuid)
    )
  );

create policy "delete_vessel_media_scoped"
  on storage.objects for delete
  using (
    bucket_id = 'vessel-media'
    and (
      is_kcc_admin()
      or is_org_staff((storage.foldername(name))[1]::uuid)
    )
  );
