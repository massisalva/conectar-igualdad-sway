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

printf 'script retirado\n' > "$TEST_HOME/.local/bin/radio-menu"
printf 'herramienta propia desconocida\n' > "$TEST_HOME/.local/bin/obsoleto"
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
[ ! -e "$TEST_HOME/.local/bin/radio-menu" ] || fail "prune no quitó el script retirado"
[ -e "$TEST_HOME/.local/bin/obsoleto" ] || fail "prune quitó una herramienta desconocida"
[ -e "$TEST_HOME/.local/bin/uv" ] || fail "prune quitó una herramienta externa preservada (uv)"
[ -e "$TEST_HOME/.local/bin/rip" ] || fail "prune quitó una herramienta externa preservada (rip)"
[ -d "$TEST_HOME/Música/streamrip" ] || fail "restore no creó ~/Música/streamrip"
[ "$(stat -c '%a' "$TEST_HOME/.config/streamrip/config.toml")" = 600 ] || \
  fail "restore no endureció permisos de ~/.config/streamrip/config.toml a 600"
grep -Fq $'present\t'"$TEST_HOME/.local/bin/radio-menu" "$prune_backup/manifest.tsv" || \
  fail "prune no respaldó el script retirado"

HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --rollback "$prune_backup" -y >/dev/null
[ -f "$TEST_HOME/.local/bin/radio-menu" ] || fail "rollback no recuperó el script retirado"
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

# Una entrada inválida al final no debe ejecutar las entradas anteriores.
printf 'conservar\n' > "$TEST_HOME/preflight-marker"
printf 'missing\t%s/preflight-marker\nmissing\t%s/../fuera\n' \
  "$TEST_HOME" "$TEST_HOME" > "$malicious_backup/manifest.tsv"
if HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --rollback "$malicious_backup" -y >/dev/null 2>&1; then
  fail "rollback aceptó un manifiesto parcialmente inválido"
fi
[ -f "$TEST_HOME/preflight-marker" ] || fail "rollback modificó archivos antes de validar todo"
printf 'directory-mode:999\t%s/.ssh\n' "$TEST_HOME" > "$malicious_backup/manifest.tsv"
if HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --rollback "$malicious_backup" -y >/dev/null 2>&1; then
  fail "rollback aceptó permisos inválidos"
fi
ok "rollback valida el manifiesto completo y los permisos antes de modificar archivos"

# Una ruta léxicamente dentro de HOME puede resolver fuera mediante un enlace.
mkdir -p "$TEST_ROOT/outside"
printf 'intacto\n' > "$TEST_ROOT/outside/marker"
ln -s "$TEST_ROOT/outside" "$TEST_HOME/escape"
printf 'missing\t%s/escape/marker\n' "$TEST_HOME" > "$malicious_backup/manifest.tsv"
if HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --rollback "$malicious_backup" -y >/dev/null 2>&1; then
  fail "rollback siguió un directorio externo enlazado"
fi
[ -f "$TEST_ROOT/outside/marker" ] || fail "rollback borró un archivo externo"

escape_home="$TEST_ROOT/escape-home"
mkdir -p "$escape_home"
ln -s "$TEST_ROOT/outside" "$escape_home/.config"
if HOME="$escape_home" PATH="$MOCK_BIN:$PATH" RESTORE_BACKUP_ROOT="$TEST_ROOT/escape-backups" \
  "$ROOT_DIR/restore.sh" --no-yazi -y >/dev/null 2>&1; then
  fail "restore siguió un directorio externo enlazado"
fi
[ ! -e "$TEST_ROOT/escape-backups" ] || fail "restore comenzó antes de validar los destinos"
ok "restore y rollback rechazan directorios enlazados fuera de HOME"

# Simular un repositorio mínimo con caché local: debe ignorarse, no borrarse.
mini_repo="$TEST_ROOT/mini-repo"
mkdir -p "$mini_repo/home/.cache" "$mini_repo/home/.config"
cp "$ROOT_DIR/restore.sh" "$mini_repo/restore.sh"
cp -a "$ROOT_DIR/lib" "$mini_repo/lib"
printf 'cache\n' > "$mini_repo/home/.cache/marker"
printf 'config\n' > "$mini_repo/home/.config/test.conf"
HOME="$TEST_ROOT/mini-home" PATH="$MOCK_BIN:$PATH" RESTORE_BACKUP_ROOT="$TEST_ROOT/mini-backups" \
  bash "$mini_repo/restore.sh" --no-yazi -y >/dev/null
[ -f "$mini_repo/home/.cache/marker" ] || fail "restore borró la caché del repositorio"
[ ! -e "$TEST_ROOT/mini-home/.cache/marker" ] || fail "restore copió la caché del repositorio"
ok "restore ignora la caché sin borrar archivos del repositorio"

HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --no-user --no-yazi --nftables --dry-run -y > "$TEST_ROOT/nft-dry-run"
grep -Fq 'sudo systemctl restart nftables.service' "$TEST_ROOT/nft-dry-run" || \
  fail "reinstalar nftables no aplicaría las reglas nuevas"
ok "reinstalación de nftables aplica las reglas nuevas"

grep -Fq 'No ejecutes restore.sh como root' "$ROOT_DIR/restore.sh" || \
  fail "restore no protege la ejecución como root"
ok "restore protege los pasos de usuario frente a root"

dry_home="$TEST_ROOT/dry-home"
HOME="$dry_home" PATH="$MOCK_BIN:$PATH" RESTORE_BACKUP_ROOT="$TEST_ROOT/dry-backups" \
  "$ROOT_DIR/restore.sh" --no-yazi --dry-run -y >/dev/null
[ ! -e "$dry_home" ] && [ ! -e "$TEST_ROOT/dry-backups" ] || fail "dry-run creó archivos"
ok "dry-run no modifica HOME ni crea backups"

# H2: el rollback solo acepta las rutas de sistema que instala el proyecto.
printf 'missing\t/etc/audit-demostracion-no-existe\n' > "$malicious_backup/manifest.tsv"
if HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --rollback "$malicious_backup" --dry-run -y > "$TEST_ROOT/h2-out" 2>&1; then
  fail "rollback aceptó una ruta de sistema ajena al proyecto"
fi
! grep -Fq 'sudo rm' "$TEST_ROOT/h2-out" || fail "rollback llegó a proponer borrar una ruta ajena"
printf 'missing\t%s/preflight-marker\nmissing\t/etc/sysctl.d/sub/99-zram.conf\n' \
  "$TEST_HOME" > "$malicious_backup/manifest.tsv"
if HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --rollback "$malicious_backup" -y >/dev/null 2>&1; then
  fail "rollback aceptó una subcarpeta de una ruta de sistema administrada"
fi
[ -f "$TEST_HOME/preflight-marker" ] || fail "rollback modificó archivos antes de rechazar la ruta de sistema"
printf 'missing\t/etc/ssh/sshd_config.d/10-hardening.conf\n' > "$malicious_backup/manifest.tsv"
HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --rollback "$malicious_backup" --dry-run -y > "$TEST_ROOT/h2-ok" 2>&1 || \
  fail "rollback rechazó una ruta de sistema administrada: $(cat "$TEST_ROOT/h2-ok")"
grep -Fq 'sudo rm -f /etc/ssh/sshd_config.d/10-hardening.conf' "$TEST_ROOT/h2-ok" || \
  fail "rollback no propuso recuperar la ruta administrada"
ok "rollback acepta solo las rutas de sistema del proyecto"

# Coincidir en carpeta y extensión no demuestra que el archivo sea del proyecto.
# La entrada válida inicial tampoco debe ejecutarse si otra entrada es ajena.
for target in \
  /etc/ssh/sshd_config.d/99-ajeno-al-proyecto.conf \
  /etc/sysctl.d/99-ajeno-al-proyecto.conf \
  /etc/polkit-1/rules.d/99-ajeno-al-proyecto.rules \
  /etc/systemd/system/ajeno-al-proyecto.mount \
  /etc/systemd/system/ajeno-al-proyecto.automount; do
  printf 'missing\t%s/preflight-marker\nmissing\t%s\n' \
    "$TEST_HOME" "$target" > "$malicious_backup/manifest.tsv"
  if HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
    "$ROOT_DIR/restore.sh" --rollback "$malicious_backup" --dry-run -y > "$TEST_ROOT/h2-out" 2>&1; then
    fail "rollback aceptó un archivo ajeno en una carpeta administrada: $target"
  fi
  grep -Fq "Ruta no permitida en el manifiesto: $target" "$TEST_ROOT/h2-out" || \
    fail "rollback falló por otra causa al validar $target"
  ! grep -Fq 'Quitando archivo' "$TEST_ROOT/h2-out" || \
    fail "rollback comenzó antes de rechazar el archivo ajeno: $target"
done
ok "rollback rechaza archivos ajenos aun con carpeta y extensión administradas"

# Verificar también todos los destinos actuales para evitar una lista incompleta.
# Si se agrega un archivo instalable, este recorrido exige admitir su rollback.
# shellcheck source=lib/system-files.sh
source "$ROOT_DIR/lib/system-files.sh"
mapfile -t managed_targets < <(system_files | cut -d'|' -f4)
for target in "${managed_targets[@]}"; do
  printf 'missing\t%s\n' "$target" > "$malicious_backup/manifest.tsv"
  HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
    "$ROOT_DIR/restore.sh" --rollback "$malicious_backup" --dry-run -y > "$TEST_ROOT/h2-ok" 2>&1 || \
    fail "rollback rechazó un destino administrado: $target: $(cat "$TEST_ROOT/h2-ok")"
  grep -Fq "sudo rm -f $target" "$TEST_ROOT/h2-ok" || \
    fail "rollback no propuso recuperar $target"
done
ok "rollback admite todos los destinos de sistema instalados por el proyecto"

# H1: chmod sigue enlaces; restore los rechaza antes de tocar nada.
for case_name in authorized_keys streamrip ssh_dir; do
  link_home="$TEST_ROOT/link-home-$case_name"
  external="$TEST_ROOT/external-$case_name"
  mkdir -p "$link_home/.ssh" "$link_home/.config/streamrip"
  case "$case_name" in
    authorized_keys)
      printf 'clave\n' > "$external"; chmod 644 "$external"
      ln -s "$external" "$link_home/.ssh/authorized_keys" ;;
    streamrip)
      printf 'config\n' > "$external"; chmod 644 "$external"
      ln -s "$external" "$link_home/.config/streamrip/config.toml" ;;
    ssh_dir)
      rmdir "$link_home/.ssh"; mkdir -p "$external"; chmod 755 "$external"
      ln -s "$external" "$link_home/.ssh" ;;
  esac
  if HOME="$link_home" PATH="$MOCK_BIN:$PATH" RESTORE_BACKUP_ROOT="$TEST_ROOT/link-backups-$case_name" \
    "$ROOT_DIR/restore.sh" --no-yazi -y >/dev/null 2>&1; then
    fail "restore aceptó un enlace en un archivo endurecido ($case_name)"
  fi
  [ "$(stat -c '%a' "$external")" = 644 ] || [ "$(stat -c '%a' "$external")" = 755 ] || \
    fail "restore cambió los permisos del destino del enlace ($case_name)"
  [ ! -e "$TEST_ROOT/link-backups-$case_name" ] || fail "restore empezó antes de rechazar el enlace ($case_name)"
  [ ! -e "$link_home/.local/bin" ] || fail "restore copió archivos antes de rechazar el enlace ($case_name)"
done
ok "restore rechaza enlaces en archivos con permisos endurecidos, sin cambios parciales"

# H4: si sshd -t falla, vuelven los archivos anteriores y no se recarga sshd.
sshd_bin="$TEST_ROOT/sshd-bin"
mkdir -p "$sshd_bin"
printf '#!/usr/bin/env bash\nexec "$@"\n' > "$sshd_bin/sudo"
printf '#!/usr/bin/env bash\nexit "${SSHD_STATUS:-0}"\n' > "$sshd_bin/sshd"
chmod +x "$sshd_bin/sudo" "$sshd_bin/sshd"
sshd_dir="$TEST_ROOT/sshd_config.d"
run_sshd() {
  : > "$TEST_SYSTEMCTL_LOG"
  HOME="$TEST_HOME" PATH="$sshd_bin:$MOCK_BIN:$PATH" RESTORE_SSHD_DIR="$sshd_dir" \
    RESTORE_BACKUP_ROOT="$TEST_ROOT/sshd-backups" SSHD_STATUS="$1" \
    "$ROOT_DIR/restore.sh" --no-user --no-yazi --sshd -y >/dev/null 2>&1
}
mkdir -p "$sshd_dir"
printf 'anterior\n' > "$sshd_dir/10-hardening.conf"
if run_sshd 1; then fail "restore informó éxito con sshd -t fallando"; fi
[ "$(cat "$sshd_dir/10-hardening.conf")" = anterior ] || fail "sshd -t falló y quedó instalado el archivo nuevo"
! grep -q 'reload sshd' "$TEST_SYSTEMCTL_LOG" || fail "sshd se recargó con una configuración inválida"
rm -f "$sshd_dir/10-hardening.conf"
if run_sshd 1; then fail "restore informó éxito con sshd -t fallando (sin archivo previo)"; fi
[ ! -e "$sshd_dir/10-hardening.conf" ] || fail "sshd -t falló y quedó un archivo que antes no existía"
run_sshd 0 || fail "restore falló con una configuración de sshd válida"
cmp -s "$ROOT_DIR/sshd/10-hardening.conf" "$sshd_dir/10-hardening.conf" || fail "no se instaló la configuración válida"
grep -q 'reload sshd.service' "$TEST_SYSTEMCTL_LOG" || fail "no se recargó sshd con la configuración válida"
ok "sshd vuelve a los archivos anteriores si sshd -t falla"

# Todo script que el proyecto instaló y ya no está en home/.local/bin tiene que
# figurar como retirado: si no, --prune lo dejaría como si fuera ajeno.
if git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  while IFS= read -r name; do
    [ -e "$ROOT_DIR/home/.local/bin/$name" ] && continue
    grep -Fqx -- "$name" "$ROOT_DIR/docs/local-bin-retired.txt" || \
      fail "$name salió de home/.local/bin y falta en docs/local-bin-retired.txt"
  done < <(git -C "$ROOT_DIR" log --all --name-only --format= -- home/.local/bin |
    sed -n 's|^home/.local/bin/||p' | sort -u)
  ok "la lista de scripts retirados cubre el historial de git"
fi

HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" \
  "$ROOT_DIR/restore.sh" --no-user --no-yazi --power --dry-run -y > "$TEST_ROOT/power-dry-run"
grep -Fq 'sudo systemctl enable --now upower.service' "$TEST_ROOT/power-dry-run" || fail "--power no habilita UPower"
ok "--power habilita UPower"

# H6 (2026-11-20): una pieza suelta hace solo eso; --user/--yazi la amplían.
# Las tres salidas posibles de install_yazi_packages.
YAZI_RAN='^==> (No existe .*/yazi/package\.toml|ya no está disponible|Instalando plugins/flavors de Yazi)'
restore_out() {  # salida de restore.sh --dry-run con las opciones dadas
  HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" "$ROOT_DIR/restore.sh" --dry-run -y "$@" 2>&1
}
out="$(restore_out --power)"
grep -Fq 'upower.service' <<< "$out" || fail "--power solo no habilitó UPower"
! grep -Fq 'Restaurando archivos de usuario' <<< "$out" || fail "--power solo también restauró \$HOME"
! grep -Eq "$YAZI_RAN" <<< "$out" || fail "--power solo también instaló lo de Yazi"
out="$(restore_out --power --user --yazi)"
grep -Fq 'Restaurando archivos de usuario' <<< "$out" || fail "--power --user no restauró \$HOME"
grep -Eq "$YAZI_RAN" <<< "$out" || fail "--power --yazi no instaló lo de Yazi"
out="$(restore_out)"
grep -Fq 'Restaurando archivos de usuario' <<< "$out" || fail "sin opciones ya no restaura \$HOME"
grep -Eq "$YAZI_RAN" <<< "$out" || fail "sin opciones ya no instala lo de Yazi"
if restore_out --power --prune >/dev/null; then
  fail "--prune con una pieza suelta no avisó que necesita --user"
fi
ok "una pieza suelta no restaura \$HOME ni Yazi, salvo con --user/--yazi"

# H6 (2026-11-20): con los permisos ya correctos no se respaldan ni se tocan
# (antes cada restauración copiaba otra vez el config.toml de Streamrip).
perm_home="$TEST_ROOT/perm-home"
perm_backups="$TEST_ROOT/perm-backups"
mkdir -p "$perm_home/.ssh" "$perm_home/.config/streamrip"
printf 'clave\n' > "$perm_home/.ssh/authorized_keys"
printf 'arl = "secreto"\n' > "$perm_home/.config/streamrip/config.toml"
chmod 700 "$perm_home/.ssh"
chmod 600 "$perm_home/.ssh/authorized_keys" "$perm_home/.config/streamrip/config.toml"
in_manifest() {  # ruta -> ¿figura en el último backup?
  local last
  last="$(find "$perm_backups" -mindepth 1 -maxdepth 1 -type d | sort | tail -n1)"
  awk -F'\t' -v p="$1" '$2 == p { found = 1 } END { exit !found }' "$last/manifest.tsv"
}
HOME="$perm_home" PATH="$MOCK_BIN:$PATH" RESTORE_BACKUP_ROOT="$perm_backups" \
  "$ROOT_DIR/restore.sh" --no-yazi -y >/dev/null
for target in "$perm_home/.ssh" "$perm_home/.ssh/authorized_keys" "$perm_home/.config/streamrip/config.toml"; do
  ! in_manifest "$target" || fail "respaldó $target aunque sus permisos ya estaban bien"
done
chmod 644 "$perm_home/.config/streamrip/config.toml"
sleep 1  # el nombre del backup lleva la hora: que el segundo sea distinto
HOME="$perm_home" PATH="$MOCK_BIN:$PATH" RESTORE_BACKUP_ROOT="$perm_backups" \
  "$ROOT_DIR/restore.sh" --no-yazi -y >/dev/null
in_manifest "$perm_home/.config/streamrip/config.toml" || fail "no respaldó config.toml antes de cerrarle los permisos"
[ "$(stat -c '%a' "$perm_home/.config/streamrip/config.toml")" = 600 ] || fail "no cerró los permisos de config.toml"
ok "permisos ya correctos no se respaldan; los abiertos se respaldan y se cierran"

printf 'Pruebas de restore: OK\n'
