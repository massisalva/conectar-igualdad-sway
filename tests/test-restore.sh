#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
TEST_HOME="$TEST_ROOT/home"
BACKUP_ROOT="$TEST_ROOT/backups"
MOCK_BIN="$ROOT_DIR/tests/fixtures/mock-bin"

cleanup() {
  [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

ok() {
  printf '[OK] %s\n' "$*"
}

latest_backup() {
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort | tail -n1
}

mkdir -p "$TEST_HOME/.local/bin"
printf 'contenido anterior\n' > "$TEST_HOME/.local/bin/disk-status"

HOME="$TEST_HOME" \
PATH="$MOCK_BIN:$PATH" \
RESTORE_BACKUP_ROOT="$BACKUP_ROOT" \
  "$ROOT_DIR/restore.sh" --no-yazi -y >/dev/null

backup="$(latest_backup)"
[ -n "$backup" ] || fail "la restauración no creó backup"
grep -Fq $'present\t'"$TEST_HOME/.local/bin/disk-status" "$backup/manifest.tsv" || \
  fail "el manifiesto no registró el archivo existente"
grep -Fq $'missing\t'"$TEST_HOME/.local/bin/waybar-battery" "$backup/manifest.tsv" || \
  fail "el manifiesto no registró el archivo nuevo"
cmp -s "$ROOT_DIR/home/.local/bin/disk-status" "$TEST_HOME/.local/bin/disk-status" || \
  fail "la restauración no instaló el archivo del repo"
ok "restauración con manifiesto"

HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --rollback "$backup" -y >/dev/null

grep -Fxq 'contenido anterior' "$TEST_HOME/.local/bin/disk-status" || \
  fail "rollback no restauró el contenido anterior"
[ ! -e "$TEST_HOME/.local/bin/waybar-battery" ] || \
  fail "rollback no quitó el archivo creado por restore"
ok "rollback de archivos existentes y nuevos"

printf 'script residual\n' > "$TEST_HOME/.local/bin/obsoleto"
printf 'herramienta externa\n' > "$TEST_HOME/.local/bin/uv"
HOME="$TEST_HOME" \
PATH="$MOCK_BIN:$PATH" \
RESTORE_BACKUP_ROOT="$BACKUP_ROOT" \
  "$ROOT_DIR/restore.sh" --no-yazi --prune -y >/dev/null

prune_backup="$(latest_backup)"
[ ! -e "$TEST_HOME/.local/bin/obsoleto" ] || fail "prune no quitó el script residual"
[ -e "$TEST_HOME/.local/bin/uv" ] || fail "prune quitó una herramienta externa preservada"
grep -Fq $'present\t'"$TEST_HOME/.local/bin/obsoleto" "$prune_backup/manifest.tsv" || \
  fail "prune no respaldó el script residual"

HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --rollback "$prune_backup" -y >/dev/null
[ -f "$TEST_HOME/.local/bin/obsoleto" ] || fail "rollback no recuperó el script residual"
ok "prune recuperable"

malicious_backup="$TEST_ROOT/malicious-backup"
mkdir -p "$malicious_backup"
printf 'missing\t%s/../restore-no-permitido\n' "$TEST_HOME" > "$malicious_backup/manifest.tsv"
if HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --rollback "$malicious_backup" -y >/dev/null 2>&1; then
  fail "rollback aceptó una ruta fuera de los destinos permitidos"
fi
ok "rollback rechaza rutas no permitidas"

printf 'Pruebas de restore: OK\n'
