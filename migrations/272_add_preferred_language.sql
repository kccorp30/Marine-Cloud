-- =========================================================
-- 272_add_preferred_language.sql — Marine Cloud premium redesign
-- =========================================================
-- BUG REAL: esta columna ya estaba aplicada en la base viva (usada
-- por lib/i18n/server.ts y lib/i18n/actions.ts desde el rediseño
-- premium) pero el archivo de migración nunca se había guardado en
-- el repo — appendonly, nunca se edita una migración vieja.
--
-- Persistencia real de idioma por perfil. Default 'en' — inglés es
-- el idioma primario del producto, nunca español hardcodeado para
-- el customer portal. Perfiles existentes quedan en 'en' de forma
-- segura (default aplicado a filas ya existentes también).
-- =========================================================

alter table profiles add column if not exists preferred_language text not null default 'en' check (preferred_language in ('en', 'es'));
