-- =========================================================
-- 076_tenant_safe_estimate_relationships.sql — Phase 6 hardening
-- =========================================================
-- Composite FKs para que organization_id nunca pueda desacordar entre
-- registros vinculados. NOT VALID + VALIDATE — verificado: 0 filas
-- existentes en las 4 tablas nuevas de Phase 6 al momento de aplicar.
--
-- Hallazgo en el camino: service_requests nunca tuvo un
-- unique(id, organization_id) propio — se agrega acá, trivialmente
-- seguro ya que id ya es PK.
--
-- Verificado con datos reales: un INSERT directo con organization_id
-- y work_order_id de tenants distintos es rechazado por la FK
-- compuesta (no solo por la validación de la función).
-- =========================================================

alter table service_requests add constraint uq_service_requests_id_org unique (id, organization_id);

alter table estimates add constraint uq_estimates_id_org unique (id, organization_id);
alter table estimate_versions add constraint uq_estimate_versions_id_org unique (id, organization_id);

alter table estimates add constraint fk_estimates_work_order_same_org
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id) not valid;

alter table estimates add constraint fk_estimates_service_request_same_org
  foreign key (service_request_id, organization_id) references service_requests(id, organization_id) not valid;

alter table estimates add constraint fk_estimates_parent_same_org
  foreign key (parent_estimate_id, organization_id) references estimates(id, organization_id) not valid;

alter table estimate_versions add constraint fk_estimate_versions_estimate_same_org
  foreign key (estimate_id, organization_id) references estimates(id, organization_id) not valid;

alter table estimate_line_items add constraint fk_line_items_version_same_org
  foreign key (estimate_version_id, organization_id) references estimate_versions(id, organization_id) not valid;

alter table estimate_decisions add constraint fk_decisions_estimate_same_org
  foreign key (estimate_id, organization_id) references estimates(id, organization_id) not valid;
alter table estimate_decisions add constraint fk_decisions_version_same_org
  foreign key (estimate_version_id, organization_id) references estimate_versions(id, organization_id) not valid;

alter table estimates validate constraint fk_estimates_work_order_same_org;
alter table estimates validate constraint fk_estimates_service_request_same_org;
alter table estimates validate constraint fk_estimates_parent_same_org;
alter table estimate_versions validate constraint fk_estimate_versions_estimate_same_org;
alter table estimate_line_items validate constraint fk_line_items_version_same_org;
alter table estimate_decisions validate constraint fk_decisions_estimate_same_org;
alter table estimate_decisions validate constraint fk_decisions_version_same_org;
