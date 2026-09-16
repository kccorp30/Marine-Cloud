-- =========================================================
-- 025_multitenant_composite_fk_integrity.sql
-- =========================================================
-- Postgres solo valida que un ID referenciado exista, no que
-- pertenezca a la misma organización. Se corrige con foreign keys
-- COMPUESTAS (resource_id, organization_id) — la garantía vive en la
-- base de datos, no en la capa de aplicación.
-- =========================================================

alter table customers add constraint uq_customers_id_org unique (id, organization_id);
alter table vessels add constraint uq_vessels_id_org unique (id, organization_id);
alter table work_orders add constraint uq_work_orders_id_org unique (id, organization_id);
alter table appointments add constraint uq_appointments_id_org unique (id, organization_id);
alter table service_catalog add constraint uq_service_catalog_id_org unique (id, organization_id);
alter table organization_locations add constraint uq_org_locations_id_org unique (id, organization_id);

alter table vessels drop constraint if exists vessels_current_customer_id_fkey;
alter table vessels add constraint fk_vessels_customer_same_org
  foreign key (current_customer_id, organization_id) references customers(id, organization_id);

alter table vessels drop constraint if exists vessels_location_id_fkey;
alter table vessels add constraint fk_vessels_location_same_org
  foreign key (location_id, organization_id) references organization_locations(id, organization_id);

alter table vessel_ownership_history drop constraint if exists vessel_ownership_history_vessel_id_fkey;
alter table vessel_ownership_history add constraint fk_voh_vessel_same_org
  foreign key (vessel_id, organization_id) references vessels(id, organization_id);

alter table vessel_ownership_history drop constraint if exists vessel_ownership_history_customer_id_fkey;
alter table vessel_ownership_history add constraint fk_voh_customer_same_org
  foreign key (customer_id, organization_id) references customers(id, organization_id);

alter table vessel_systems drop constraint if exists vessel_systems_vessel_id_fkey;
alter table vessel_systems add constraint fk_vessel_systems_vessel_same_org
  foreign key (vessel_id, organization_id) references vessels(id, organization_id);

alter table work_orders drop constraint if exists work_orders_customer_id_fkey;
alter table work_orders add constraint fk_wo_customer_same_org
  foreign key (customer_id, organization_id) references customers(id, organization_id);

alter table work_orders drop constraint if exists work_orders_vessel_id_fkey;
alter table work_orders add constraint fk_wo_vessel_same_org
  foreign key (vessel_id, organization_id) references vessels(id, organization_id);

alter table work_orders drop constraint if exists work_orders_service_id_fkey;
alter table work_orders add constraint fk_wo_service_same_org
  foreign key (service_id, organization_id) references service_catalog(id, organization_id);

alter table appointments drop constraint if exists appointments_work_order_id_fkey;
alter table appointments add constraint fk_appt_work_order_same_org
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id);

alter table appointments drop constraint if exists appointments_location_id_fkey;
alter table appointments add constraint fk_appt_location_same_org
  foreign key (location_id, organization_id) references organization_locations(id, organization_id);

alter table assignments drop constraint if exists assignments_work_order_id_fkey;
alter table assignments add constraint fk_assign_work_order_same_org
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id);

alter table assignments drop constraint if exists assignments_appointment_id_fkey;
alter table assignments add constraint fk_assign_appointment_same_org
  foreign key (appointment_id, organization_id) references appointments(id, organization_id);

-- ---------------------------------------------------------
-- assignments.technician_profile_id — no puede ser una FK compuesta
-- normal porque `profiles` no tiene organization_id (identidad cruza
-- organizaciones a propósito). Se garantiza con un constraint trigger.
-- ---------------------------------------------------------
create or replace function check_assignment_technician_org()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from organization_memberships
    where profile_id = new.technician_profile_id
      and organization_id = new.organization_id
      and status = 'active'
      and role = 'technician'
  ) then
    raise exception 'technician_profile_id must have an active technician membership in this organization';
  end if;
  return new;
end;
$$;

create trigger trg_check_assignment_technician_org
  before insert or update on assignments
  for each row execute function check_assignment_technician_org();

revoke execute on function check_assignment_technician_org() from public, anon, authenticated;
