-- =========================================================
-- 165_fix_leads_marine_cloud_fk_targets.sql — Phase 11
-- =========================================================
-- BUG REAL PREEXISTENTE: leads.marine_cloud_customer_id tenía su FK
-- apuntando a profiles(id) en vez de customers(id) — remanente de
-- cuando esta tabla se diseñó del lado del sitio, antes de que
-- customers/vessels/work_orders existieran como tablas propias de
-- Marine Cloud. marine_cloud_vessel_id/work_order_id no tenían FK en
-- absoluto. Se corrigen los tres.
-- =========================================================

alter table leads drop constraint leads_marine_cloud_customer_id_fkey;
alter table leads add constraint leads_marine_cloud_customer_id_fkey foreign key (marine_cloud_customer_id) references customers(id);
alter table leads add constraint leads_marine_cloud_vessel_id_fkey foreign key (marine_cloud_vessel_id) references vessels(id);
alter table leads add constraint leads_marine_cloud_work_order_id_fkey foreign key (marine_cloud_work_order_id) references work_orders(id);
