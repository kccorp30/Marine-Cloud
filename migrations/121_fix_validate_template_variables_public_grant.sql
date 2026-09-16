-- =========================================================
-- 121_fix_validate_template_variables_public_grant.sql — Phase 8 final fix
-- =========================================================
-- Misma clase de hallazgo que 120: validate_template_variables()
-- (propia de Phase 8) nunca tuvo su revoke explícito de public/anon
-- tras crearse — sin riesgo real de datos (no toca ninguna tabla),
-- pero se cierra por consistencia. Otras funciones con el mismo
-- hallazgo en el barrido (calculate_deposit_amount,
-- current_organization_id, set_updated_at, sync_lead_media_count)
-- son preexistentes de fases anteriores o triggers sin acceso real a
-- datos vía RPC — fuera de alcance de este pase.
-- =========================================================

revoke execute on function validate_template_variables(text) from public, anon;
grant execute on function validate_template_variables(text) to authenticated;
