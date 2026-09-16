-- =========================================================
-- 031_phase2_rls_policies.sql — Marine Cloud Phase 2
-- =========================================================

create policy "read_time_entries" on time_entries for select
  using (is_kcc_admin() or is_org_staff(organization_id) or technician_profile_id = auth.uid());
create policy "technician_insert_own_time_entries" on time_entries for insert
  with check (
    (is_kcc_admin() or is_org_staff(organization_id))
    or (technician_profile_id = auth.uid() and is_assigned_to_work_order(work_order_id))
  );
create policy "technician_update_own_time_entries" on time_entries for update
  using (is_kcc_admin() or is_org_staff(organization_id) or technician_profile_id = auth.uid());

create policy "read_media_assets" on media_assets for select
  using (
    is_kcc_admin()
    or is_org_staff(organization_id)
    or is_assigned_to_work_order(work_order_id)
    or (visibility = 'customer_visible' and is_customer_of_work_order(work_order_id))
  );
create policy "technician_insert_media_assets" on media_assets for insert
  with check (
    (is_kcc_admin() or is_org_staff(organization_id))
    or (uploaded_by = auth.uid() and is_assigned_to_work_order(work_order_id))
  );
create policy "staff_update_media_assets" on media_assets for update
  using (is_kcc_admin() or is_org_staff(organization_id) or (uploaded_by = auth.uid() and is_assigned_to_work_order(work_order_id)));

create policy "read_work_notes" on work_notes for select
  using (
    is_kcc_admin()
    or is_org_staff(organization_id)
    or is_assigned_to_work_order(work_order_id)
    or (visibility = 'customer_visible' and is_customer_of_work_order(work_order_id))
  );
create policy "technician_insert_work_notes" on work_notes for insert
  with check (
    (is_kcc_admin() or is_org_staff(organization_id))
    or (technician_profile_id = auth.uid() and is_assigned_to_work_order(work_order_id))
  );
create policy "staff_update_work_notes" on work_notes for update
  using (is_kcc_admin() or is_org_staff(organization_id) or technician_profile_id = auth.uid());

create policy "read_measurements" on measurements for select
  using (is_kcc_admin() or is_org_staff(organization_id) or is_assigned_to_work_order(work_order_id) or is_customer_of_work_order(work_order_id));
create policy "technician_insert_measurements" on measurements for insert
  with check (
    (is_kcc_admin() or is_org_staff(organization_id))
    or (technician_profile_id = auth.uid() and is_assigned_to_work_order(work_order_id))
  );
create policy "staff_update_measurements" on measurements for update
  using (is_kcc_admin() or is_org_staff(organization_id) or technician_profile_id = auth.uid());

create policy "read_checklist_templates" on checklist_templates for select
  using (is_kcc_admin() or is_org_member(organization_id));
create policy "staff_write_checklist_templates" on checklist_templates for insert
  with check (is_kcc_admin() or is_org_staff(organization_id));
create policy "staff_update_checklist_templates" on checklist_templates for update
  using (is_kcc_admin() or is_org_staff(organization_id));

create policy "read_checklist_template_items" on checklist_template_items for select
  using (is_kcc_admin() or is_org_member(organization_id));
create policy "staff_write_checklist_template_items" on checklist_template_items for insert
  with check (is_kcc_admin() or is_org_staff(organization_id));
create policy "staff_update_checklist_template_items" on checklist_template_items for update
  using (is_kcc_admin() or is_org_staff(organization_id));

create policy "read_checklist_responses" on checklist_responses for select
  using (is_kcc_admin() or is_org_staff(organization_id) or is_assigned_to_work_order(work_order_id) or is_customer_of_work_order(work_order_id));
create policy "technician_insert_checklist_responses" on checklist_responses for insert
  with check (
    (is_kcc_admin() or is_org_staff(organization_id))
    or (technician_profile_id = auth.uid() and is_assigned_to_work_order(work_order_id))
  );
create policy "technician_update_checklist_responses" on checklist_responses for update
  using (
    (is_kcc_admin() or is_org_staff(organization_id))
    or (technician_profile_id = auth.uid() and is_assigned_to_work_order(work_order_id))
  );

create policy "read_progress_updates" on progress_updates for select
  using (
    is_kcc_admin()
    or is_org_staff(organization_id)
    or is_assigned_to_work_order(work_order_id)
    or (customer_visible and is_customer_of_work_order(work_order_id))
  );
create policy "technician_insert_progress_updates" on progress_updates for insert
  with check (
    (is_kcc_admin() or is_org_staff(organization_id))
    or (technician_profile_id = auth.uid() and is_assigned_to_work_order(work_order_id))
  );

create policy "read_progress_update_media" on progress_update_media for select
  using (
    is_kcc_admin() or is_org_staff((select organization_id from work_orders where id = work_order_id))
    or is_assigned_to_work_order(work_order_id) or is_customer_of_work_order(work_order_id)
  );
create policy "technician_insert_progress_update_media" on progress_update_media for insert
  with check (is_kcc_admin() or is_org_staff((select organization_id from work_orders where id = work_order_id)) or is_assigned_to_work_order(work_order_id));

create policy "read_check_ins" on check_ins for select
  using (is_kcc_admin() or is_org_staff(organization_id) or technician_profile_id = auth.uid());
