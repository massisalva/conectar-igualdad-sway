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

mkdir -p "$TEST_HOME/.local/bin" "$TEST_HOME/.config" "$TEST_HOME/.ssh"
chmod 700 "$TEST_HOME" "$TEST_HOME/.config" "$TEST_HOME/.local"
chmod 750 "$TEST_HOME/.ssh"
printf 'clave de prueba\n' > "$TEST_HOME/.ssh/authorized_keys"
chmod 640 "$TEST_HOME/.ssh/authorized_keys"
printf 'archivo externo no ejecutable\n' > "$TEST_HOME/.local/bin/documento"
chmod 644 "$TEST_HOME/.local/bin/documento"
printf 'contenido anterior\n' > "$TEST_HOME/.local/bin/disk-status"
printf 'configuración externa\n' > "$TEST_ROOT/external-theme"
mkdir -p "$TEST_HOME/.config/environment.d"
ln -s "$TEST_ROOT/external-theme" "$TEST_HOME/.config/environment.d/10-visual-theme.conf"
export TEST_SYSTEMCTL_LOG="$TEST_ROOT/systemctl.log"

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
for dir in "$TEST_HOME" "$TEST_HOME/.config" "$TEST_HOME/.local"; do
  [ "$(stat -c '%a' "$dir")" = 700 ] || fail "restore cambió los permisos privados de $dir"
done
[ "$(stat -c '%a' "$backup")" = 700 ] || fail "el backup no es privado"
[ "$(stat -c '%a' "$TEST_HOME/.local/bin/documento")" = 644 ] || fail "restore cambió permisos de un archivo externo"
[ "$(stat -c '%a' "$TEST_HOME/.ssh")" = 700 ] || fail "restore no protegió ~/.ssh"
[ "$(stat -c '%a' "$TEST_HOME/.ssh/authorized_keys")" = 600 ] || fail "restore no protegió authorized_keys"
grep -Fxq -- '--user enable --now mpd.service' "$TEST_SYSTEMCTL_LOG" || fail "restore no habilitó e inició MPD en la cuenta nueva"
ok "directorios privados preservados, backup privado y MPD habilitado"
grep -Fxq 'configuración externa' "$TEST_ROOT/external-theme" || fail "restore sobrescribió el destino de un enlace preexistente"
[ ! -L "$TEST_HOME/.config/environment.d/10-visual-theme.conf" ] || fail "restore no reemplazó el enlace por la configuración administrada"

HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --rollback "$backup" -y >/dev/null

grep -Fxq 'contenido anterior' "$TEST_HOME/.local/bin/disk-status" || \
  fail "rollback no restauró el contenido anterior"
[ ! -e "$TEST_HOME/.local/bin/waybar-battery" ] || \
  fail "rollback no quitó el archivo creado por restore"
ok "rollback de archivos existentes y nuevos"
for dir in "$TEST_HOME" "$TEST_HOME/.config" "$TEST_HOME/.local"; do
  [ "$(stat -c '%a' "$dir")" = 700 ] || fail "rollback alteró los permisos privados de $dir"
done
[ "$(stat -c '%a' "$TEST_HOME/.ssh")" = 750 ] || fail "rollback no recuperó los permisos de ~/.ssh"
[ "$(stat -c '%a' "$TEST_HOME/.ssh/authorized_keys")" = 640 ] || fail "rollback no recuperó los permisos de authorized_keys"
ok "rollback recupera los permisos ajustados explícitamente"
[ "$(readlink "$TEST_HOME/.config/environment.d/10-visual-theme.conf")" = "$TEST_ROOT/external-theme" ] || \
  fail "rollback no recuperó un enlace preexistente"

printf 'script residual\n' > "$TEST_HOME/.local/bin/obsoleto"
printf 'herramienta externa\n' > "$TEST_HOME/.local/bin/uv"
printf 'herramienta externa\n' > "$TEST_HOME/.local/bin/rip"
mkdir -p "$TEST_HOME/.config/streamrip"
printf 'arl = "secreto"\n' > "$TEST_HOME/.config/streamrip/config.toml"
chmod 644 "$TEST_HOME/.config/streamrip/config.toml"
HOME="$TEST_HOME" \
PATH="$MOCK_BIN:$PATH" \
RESTORE_BACKUP_ROOT="$BACKUP_ROOT" \
  "$ROOT_DIR/restore.sh" --no-yazi --prune -y >/dev/null

prune_backup="$(latest_backup)"
[ ! -e "$TEST_HOME/.local/bin/obsoleto" ] || fail "prune no quitó el script residual"
[ -e "$TEST_HOME/.local/bin/uv" ] || fail "prune quitó una herramienta externa preservada (uv)"
[ -e "$TEST_HOME/.local/bin/rip" ] || fail "prune quitó una herramienta externa preservada (rip)"
[ -d "$TEST_HOME/Música/streamrip" ] || fail "restore no creó ~/Música/streamrip"
[ "$(stat -c '%a' "$TEST_HOME/.config/streamrip/config.toml")" = 600 ] || \
  fail "restore no endureció permisos de ~/.config/streamrip/config.toml a 600"
grep -Fq $'present\t'"$TEST_HOME/.local/bin/obsoleto" "$prune_backup/manifest.tsv" || \
  fail "prune no respaldó el script residual"

HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --rollback "$prune_backup" -y >/dev/null
[ -f "$TEST_HOME/.local/bin/obsoleto" ] || fail "rollback no recuperó el script residual"
[ "$(stat -c '%a' "$TEST_HOME/.config/streamrip/config.toml")" = 644 ] || fail "rollback no recuperó los permisos previos de Streamrip"
ok "prune recuperable"

malicious_backup="$TEST_ROOT/malicious-backup"
mkdir -p "$malicious_backup"
printf 'missing\t%s/../restore-no-permitido\n' "$TEST_HOME" > "$malicious_backup/manifest.tsv"
if HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --rollback "$malicious_backup" -y >/dev/null 2>&1; then
  fail "rollback aceptó una ruta fuera de los destinos permitidos"
fi
ok "rollback rechaza rutas no permitidas"

grep -Fq 'No ejecutes restore.sh como root' "$ROOT_DIR/restore.sh" || \
  fail "restore no protege la ejecución como root"
ok "restore protege los pasos de usuario frente a root"

dry_home="$TEST_ROOT/dry-home"
HOME="$dry_home" PATH="$MOCK_BIN:$PATH" RESTORE_BACKUP_ROOT="$TEST_ROOT/dry-backups" \
  "$ROOT_DIR/restore.sh" --no-yazi --dry-run -y >/dev/null
[ ! -e "$dry_home" ] && [ ! -e "$TEST_ROOT/dry-backups" ] || fail "dry-run creó archivos"
ok "dry-run no modifica HOME ni crea backups"

printf 'Pruebas de restore: OK\n'
