-- =========================================================
-- 017_revoke_public_from_event_functions.sql — Marine Cloud
-- Corrección encontrada durante la verificación de repositorio previa
-- a Phase 1: log_domain_event/log_audit_event seguían con grant
-- heredado de PUBLIC (la migración 016 solo revocó de `anon`
-- directamente, lo cual no alcanza porque `anon` hereda privilegios
-- de PUBLIC salvo que también se revoque ahí). No era explotable en
-- la práctica — la lógica interna de ambas funciones ya rechaza a
-- cualquier llamador sin auth.uid() real — pero se corrige por
-- higiene de mínimo privilegio, coherente con el resto de funciones.
-- =========================================================

revoke execute on function log_domain_event(uuid, text, text, uuid, jsonb) from public;
revoke execute on function log_audit_event(uuid, text, uuid, text, jsonb, jsonb) from public;
grant execute on function log_domain_event(uuid, text, text, uuid, jsonb) to authenticated;
grant execute on function log_audit_event(uuid, text, uuid, text, jsonb, jsonb) to authenticated;
