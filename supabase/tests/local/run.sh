#!/usr/bin/env bash
# Valida migrations + seed + pgTAP em um Postgres local "puro" (sem Docker).
# Uso: supabase/tests/local/run.sh [dbname]   (requer: psql como superusuário via PGUSER/PGHOST ou `su postgres`)
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB="${1:-transtornar_local}"
PSQL="psql -v ON_ERROR_STOP=1 -q"
$PSQL -d postgres -c "drop database if exists $DB" -c "create database $DB"
$PSQL -d postgres -c "alter database $DB set search_path = public, extensions"
$PSQL -d "$DB" -f supabase/tests/local/shim.sql
for f in supabase/migrations/*.sql; do echo "== $f"; $PSQL -d "$DB" -f "$f"; done
echo "== seed.sql"; $PSQL -d "$DB" -f supabase/seed.sql
$PSQL -d "$DB" -c "create extension if not exists pgtap"
fail=0
[ "${SKIP_TESTS:-0}" = "1" ] && { echo "MIGRATIONS OK (tests skipped)"; exit 0; }
for t in supabase/tests/*.sql; do
  [ -e "$t" ] || continue
  echo "== test $t"
  out=$(psql -d "$DB" -v ON_ERROR_STOP=1 -X -q -t -A -f "$t" 2>&1) || { echo "$out"; fail=1; continue; }
  echo "$out" | grep -E '^(not ok|# )' && fail=1 || true
  echo "$out" | grep -cE '^ok ' | sed 's/^/   ok: /'
done
[ "$fail" -eq 0 ] && echo "ALL GREEN" || { echo "FAILURES"; exit 1; }
