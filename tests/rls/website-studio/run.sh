#!/usr/bin/env bash
# Prueba la migración del sitio web + los textos borrador + las reglas
# de seguridad (RLS) en un Postgres 16 LOCAL y desechable que imita lo
# mínimo de Supabase. No toca ninguna base real.
#
#   bash tests/rls/website-studio/run.sh
#
# Requiere: initdb, pg_ctl y psql de PostgreSQL 16 en el PATH (o en
# /usr/lib/postgresql/16/bin). Termina con "fail = 0" si todo pasa.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
DIR="$(mktemp -d)"
PORT="${PORT:-55433}"
"$PGBIN/initdb" -D "$DIR/data" -U postgres --auth=trust >/dev/null
"$PGBIN/pg_ctl" -D "$DIR/data" -o "-p $PORT -k $DIR" -l "$DIR/log" start >/dev/null
trap '"$PGBIN/pg_ctl" -D "$DIR/data" stop >/dev/null; rm -rf "$DIR"' EXIT
sleep 2
PSQL="psql -h $DIR -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
$PSQL -f "$HERE/00-supabase-stubs.sql"
$PSQL -f "$ROOT/supabase/migrations/20261001000000_website_studio.sql" 2>/dev/null
$PSQL -f "$ROOT/supabase/migrations/20261001000000_website_studio.sql" 2>/dev/null   # idempotente
$PSQL -f "$ROOT/supabase/seed/website-content-drafts.sql" >/dev/null
$PSQL -f "$ROOT/supabase/seed/website-content-drafts.sql" >/dev/null                # idempotente
psql -h "$DIR" -p "$PORT" -U postgres -f "$HERE/10-website-studio-rls.sql" 2>&1 | grep -v "^SET\|^RESET\|^$"
