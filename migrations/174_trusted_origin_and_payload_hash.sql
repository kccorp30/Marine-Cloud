-- =========================================================
-- 174_trusted_origin_and_payload_hash.sql — Phase 11 true closure
-- =========================================================
-- BUG REAL de la auditoría cruzada: el sitio guardaba
-- `source = attribution.source` (derivado de UTM) — y /website-leads
-- filtraba por `source='website'`. Un lead real con
-- utm_source=google/facebook desaparecía de la cola, y la señal de
-- origen confiable dependía de un campo de marketing que un actor no
-- confiable podría enviar con cualquier valor.
--
-- ingestion_source: campo de origen confiable, SOLO lo setea la
-- propia ruta server-side del sitio a 'kcc_website' — nunca derivado
-- de UTM. payload_hash: hash canónico para distinguir un reintento
-- legítimo de un conflicto real de idempotencia.
-- =========================================================

alter table leads add column ingestion_source text;
alter table leads add column payload_hash text;

create index idx_leads_ingestion_source on leads(ingestion_source);
