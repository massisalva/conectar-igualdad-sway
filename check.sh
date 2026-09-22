#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FAILS=0
WARNS=0
STRICT_SYSTEM=0
ALLOW_SUDO_PROMPT=0
SUDO_READY=0
LOCAL_BIN_KEEP_FILE="$ROOT_DIR/docs/local-bin-keep.txt"

usage() {
  cat <<'EOF'
Uso: ./check.sh [opciones]

Por defecto verifica el estado de usuario, paquetes, Yazi, XDG y repo.
Los archivos de sistema en polkit/, bootloader/, sshd/, nftables/, iwd/, sysctl/ y zram/ se reportan como advertencia.

Opciones:
  --system    Trata polkit/, bootloader/, sshd/, nftables/, iwd/, sysctl/ y zram/ como checks obligatorios.
  --sudo      Permite pedir contraseña para verificar archivos de sistema
              si hay una terminal interactiva disponible.
  -h, --help  Muestra esta ayuda.
EOF
}

ok() {
  printf '[OK] %s\n' "$*"
}

warn() {
  WARNS=$((WARNS + 1))
  printf '[WARN] %s\n' "$*"
}

fail() {
  FAILS=$((FAILS + 1))
  printf '[FAIL] %s\n' "$*"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

sudo_check() {
  [ "$SUDO_READY" -eq 1 ] || return 1

  if [ "$ALLOW_SUDO_PROMPT" -eq 1 ]; then
    sudo "$@" 2>/dev/null
  else
    sudo -n "$@" 2>/dev/null
  fi
}

prepare_sudo() {
  if [ "$ALLOW_SUDO_PROMPT" -eq 1 ]; then
    if [ ! -t 0 ]; then
      fail "no puedo pedir contraseña de sudo sin una terminal interactiva"
      return
    fi

    if sudo -v; then
      SUDO_READY=1
    else
      fail "no se pudo obtener credencial sudo; revisá contraseña, layout o bloqueo de faillock"
    fi
    return
  fi

  if sudo -n true 2>/dev/null; then
    SUDO_READY=1
  fi
}

sudo_check_label() {
  if [ "$ALLOW_SUDO_PROMPT" -eq 1 ]; then
    printf 'con sudo'
  else
    printf 'sin sudo'
  fi
}

check_cmd() {
  if has_cmd "$1"; then
    ok "comando disponible: $1"
  else
    fail "falta comando: $1"
  fi
}

check_file() {
  if [ -f "$1" ]; then
    ok "archivo existe: $1"
  else
    fail "falta archivo: $1"
  fi
}

check_executable() {
  if [ -x "$1" ]; then
    ok "ejecutable: $1"
  else
    fail "no ejecutable o ausente: $1"
  fi
}

check_same_file() {
  local repo_file="$1"
  local active_file="$2"
  local severity="${3:-fail}"

  if [ ! -f "$repo_file" ]; then
    if [ "$severity" = "warn" ]; then
      warn "falta en repo: $repo_file"
    else
      fail "falta en repo: $repo_file"
    fi
  elif [ ! -f "$active_file" ]; then
    if [ "$severity" = "warn" ]; then
      warn "falta activo: $active_file"
    else
      fail "falta activo: $active_file"
    fi
  elif cmp -s "$repo_file" "$active_file"; then
    ok "coincide: $active_file"
  else
    if [ "$severity" = "warn" ]; then
      warn "difiere de repo: $active_file"
    else
      fail "difiere de repo: $active_file"
    fi
  fi
}

check_same_system_file() {
  local repo_file="$1"
  local active_file="$2"
  local severity="${3:-warn}"

  if [ ! -f "$repo_file" ]; then
    if [ "$severity" = "warn" ]; then
      warn "falta en repo: $repo_file"
    else
      fail "falta en repo: $repo_file"
    fi
    return
  fi

  if [ -f "$active_file" ]; then
    check_same_file "$repo_file" "$active_file" "$severity"
    return
  fi

  if ! sudo_check true; then
    if [ "$severity" = "warn" ]; then
      warn "no puedo verificar $(sudo_check_label): $active_file"
    else
      fail "no puedo verificar $(sudo_check_label): $active_file"
    fi
    return
  fi

  if ! sudo_check test -f "$active_file"; then
    if [ "$severity" = "warn" ]; then
      warn "falta activo: $active_file"
    else
      fail "falta activo: $active_file"
    fi
    return
  fi

  if sudo_check cmp -s "$repo_file" "$active_file"; then
    ok "coincide: $active_file"
  elif [ "$severity" = "warn" ]; then
    warn "difiere de repo: $active_file"
  else
    fail "difiere de repo: $active_file"
  fi
}

check_packages() {
  local label="$1"
  local file="$2"
  local missing=0
  local pkg

  check_file "$file"
  [ -f "$file" ] || return

  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    case "$pkg" in \#*) continue ;; esac

    if pacman -Q "$pkg" >/dev/null 2>&1; then
      :
    else
      printf '[FAIL] falta paquete %s: %s\n' "$label" "$pkg"
      missing=$((missing + 1))
    fi
  done < "$file"

  if [ "$missing" -eq 0 ]; then
    ok "paquetes $label instalados"
  else
    FAILS=$((FAILS + missing))
  fi
}

check_repo_state() {
  if ! [ -d "$ROOT_DIR/.git" ]; then
    warn "no es un repo git: $ROOT_DIR"
    return
  fi

  if [ -z "$(git -C "$ROOT_DIR" status --porcelain)" ]; then
    ok "repo sin cambios locales"
  else
    warn "repo con cambios locales"
    git -C "$ROOT_DIR" status --short
  fi

  local upstream
  upstream="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [ -z "$upstream" ]; then
    warn "rama sin upstream configurado"
    return
  fi

  local local_rev upstream_rev
  local_rev="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  upstream_rev="$(git -C "$ROOT_DIR" rev-parse "$upstream" 2>/dev/null || true)"
  if [ "$local_rev" = "$upstream_rev" ]; then
    ok "repo sincronizado con $upstream"
  else
    warn "HEAD local difiere de $upstream"
  fi
}

check_user_files() {
  local rel
  while IFS= read -r rel; do
    check_same_file "$ROOT_DIR/$rel" "$HOME/${rel#home/}"
  done < <(find "$ROOT_DIR/home/.config" -type f -printf 'home/.config/%P\n' | sort)

  while IFS= read -r rel; do
    check_same_file "$ROOT_DIR/$rel" "$HOME/${rel#home/}"
    check_executable "$HOME/${rel#home/}"
  done < <(find "$ROOT_DIR/home/.local/bin" -type f -printf 'home/.local/bin/%P\n' | sort)

  while IFS= read -r rel; do
    check_same_file "$ROOT_DIR/$rel" "$HOME/${rel#home/}"
    if has_cmd desktop-file-validate; then
      if desktop-file-validate "$ROOT_DIR/$rel"; then
        ok "desktop válido: $ROOT_DIR/$rel"
      else
        fail "desktop inválido: $ROOT_DIR/$rel"
      fi
    fi
  done < <(find "$ROOT_DIR/home/.local/share/applications" -type f -name '*.desktop' -printf 'home/.local/share/applications/%P\n' | sort)
}

check_polkit() {
  local file
  local severity="warn"
  [ "$STRICT_SYSTEM" -eq 1 ] && severity="fail"

  for file in "$ROOT_DIR"/polkit/*.rules; do
    [ -f "$file" ] || continue
    check_same_system_file "$file" "/etc/polkit-1/rules.d/$(basename "$file")" "$severity"
  done
}

check_bootloader() {
  local severity="warn"
  [ "$STRICT_SYSTEM" -eq 1 ] && severity="fail"

  check_same_system_file "$ROOT_DIR/bootloader/loader.conf" /boot/loader/loader.conf "$severity"
  check_same_system_file "$ROOT_DIR/bootloader/arch.conf" /boot/loader/entries/arch.conf "$severity"
}

check_sshd() {
  local severity="warn"
  [ "$STRICT_SYSTEM" -eq 1 ] && severity="fail"

  local file
  for file in "$ROOT_DIR"/sshd/*.conf; do
    [ -f "$file" ] || continue
    check_same_system_file "$file" "/etc/ssh/sshd_config.d/$(basename "$file")" "$severity"
  done

  if ! sudo_check true; then
    if [ "$severity" = "warn" ]; then
      warn "no puedo verificar la configuración efectiva de SSH $(sudo_check_label)"
    else
      fail "no puedo verificar la configuración efectiva de SSH $(sudo_check_label)"
    fi
    return
  fi

  if sudo_check sshd -t; then
    ok "sintaxis efectiva de SSH válida"
  elif [ "$severity" = "warn" ]; then
    warn "la configuración efectiva de SSH tiene errores de sintaxis"
  else
    fail "la configuración efectiva de SSH tiene errores de sintaxis"
  fi

  local effective setting expected actual
  effective="$(sudo_check sshd -T \
    -C user=massisalva,host=localhost,addr=127.0.0.1 2>/dev/null || true)"
  if [ -z "$effective" ]; then
    if [ "$severity" = "warn" ]; then
      warn "sshd -T no devolvió la configuración efectiva"
    else
      fail "sshd -T no devolvió la configuración efectiva"
    fi
    return
  fi

  while read -r setting expected; do
    actual="$(printf '%s\n' "$effective" | awk -v key="$setting" 'tolower($1) == key {$1=""; sub(/^ /, ""); print; exit}')"
    if [ "$actual" = "$expected" ]; then
      ok "SSH efectivo: $setting $expected"
    elif [ "$severity" = "warn" ]; then
      warn "SSH efectivo: $setting esperado '$expected', actual '${actual:-desconocido}'"
    else
      fail "SSH efectivo: $setting esperado '$expected', actual '${actual:-desconocido}'"
    fi
  done <<'EOF'
allowusers massisalva
permitrootlogin no
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
permitemptypasswords no
maxauthtries 3
logingracetime 30
x11forwarding no
EOF
}

check_nftables() {
  local severity="warn"
  [ "$STRICT_SYSTEM" -eq 1 ] && severity="fail"
  local output active_state sub_state result unit_file_state

  check_same_system_file "$ROOT_DIR/nftables/nftables.conf" /etc/nftables.conf "$severity"

  if has_cmd nft; then
    ok "comando disponible: nft"
  else
    fail "falta comando: nft"
  fi

  output="$(systemctl show nftables.service -p ActiveState -p SubState -p Result -p UnitFileState 2>/dev/null || true)"
  if [ -z "$output" ]; then
    if systemctl is-enabled nftables.service >/dev/null 2>&1; then
      warn "nftables no pudo verificarse por permisos del entorno"
      return
    fi

    if [ "$severity" = "warn" ]; then
      warn "nftables no está aplicado o habilitado"
    else
      fail "nftables no está aplicado o habilitado"
    fi
    return
  fi

  active_state="$(printf '%s\n' "$output" | awk -F= '/^ActiveState=/{print $2}')"
  sub_state="$(printf '%s\n' "$output" | awk -F= '/^SubState=/{print $2}')"
  result="$(printf '%s\n' "$output" | awk -F= '/^Result=/{print $2}')"
  unit_file_state="$(printf '%s\n' "$output" | awk -F= '/^UnitFileState=/{print $2}')"

  if [ "$unit_file_state" = "enabled" ] && [ "$result" = "success" ] && { [ "$active_state" = "inactive" ] || [ "$active_state" = "active" ]; }; then
    ok "nftables aplicado y habilitado"
  else
    if [ "$severity" = "warn" ]; then
      warn "nftables no está aplicado o habilitado"
    else
      fail "nftables no está aplicado o habilitado"
    fi
  fi


  if ! sudo_check true; then
    if [ "$severity" = "warn" ]; then
      warn "no puedo verificar el ruleset vivo de nftables $(sudo_check_label)"
    else
      fail "no puedo verificar el ruleset vivo de nftables $(sudo_check_label)"
    fi
    return
  fi

  local ruleset
  ruleset="$(sudo_check nft list table inet filter || true)"
  if [ -z "$ruleset" ]; then
    if [ "$severity" = "warn" ]; then
      warn "no existe el ruleset vivo esperado de nftables"
    else
      fail "no existe el ruleset vivo esperado de nftables"
    fi
    return
  fi

  local pattern label
  while IFS='|' read -r pattern label; do
    if printf '%s\n' "$ruleset" | grep -Eq "$pattern"; then
      ok "nftables vivo: $label"
    elif [ "$severity" = "warn" ]; then
      warn "nftables vivo no confirma: $label"
    else
      fail "nftables vivo no confirma: $label"
    fi
  done <<'EOF'
hook input .*policy drop|entrada con política drop
hook forward .*policy drop|forwarding con política drop
hook output .*policy accept|salida con política accept
192\.168\.1\.0/24|LAN confiable 192.168.1.0/24
tcp dport 22 accept|SSH permitido por la regla esperada
tcp dport 53317 accept|LocalSend TCP permitido
udp dport 53317 accept|LocalSend UDP permitido
EOF
}

check_iwd() {
  local severity="warn"
  [ "$STRICT_SYSTEM" -eq 1 ] && severity="fail"
  local service output resolv_target

  check_same_system_file "$ROOT_DIR/iwd/main.conf" /etc/iwd/main.conf "$severity"
  check_same_system_file "$ROOT_DIR/iwd/wireless-regdom.conf" /etc/conf.d/wireless-regdom "$severity"

  for service in iwd.service systemd-resolved.service; do
    output="$(systemctl is-enabled "$service" 2>&1)"
    if [ "$output" = "enabled" ]; then
      ok "$service habilitado"
    elif printf '%s\n' "$output" | grep -Eq 'Operation not permitted|Failed to connect to system scope bus'; then
      warn "no puedo verificar $service por permisos del entorno"
    elif [ "$severity" = "warn" ]; then
      warn "$service no está habilitado"
    else
      fail "$service no está habilitado"
    fi
  done

  if pacman -Q networkmanager >/dev/null 2>&1; then
    if [ "$severity" = "warn" ]; then
      warn "NetworkManager sigue instalado junto a iwd"
    else
      fail "NetworkManager sigue instalado junto a iwd"
    fi
  else
    ok "NetworkManager no está instalado"
  fi

  if pacman -Q tlp-rdw >/dev/null 2>&1; then
    if [ "$severity" = "warn" ]; then
      warn "tlp-rdw sigue instalado y requiere NetworkManager"
    else
      fail "tlp-rdw sigue instalado y requiere NetworkManager"
    fi
  else
    ok "tlp-rdw no está instalado"
  fi

  resolv_target="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
  if [ "$resolv_target" = /run/systemd/resolve/stub-resolv.conf ]; then
    ok "/etc/resolv.conf usa systemd-resolved"
  elif [ "$severity" = "warn" ]; then
    warn "/etc/resolv.conf no usa el stub de systemd-resolved"
  else
    fail "/etc/resolv.conf no usa el stub de systemd-resolved"
  fi
}

check_sysctl() {
  local severity="warn"
  [ "$STRICT_SYSTEM" -eq 1 ] && severity="fail"
  local actual

  check_same_system_file "$ROOT_DIR/sysctl/99-local-hardening.conf" /etc/sysctl.d/99-local-hardening.conf "$severity"
  actual="$(sysctl -n kernel.kptr_restrict 2>/dev/null || true)"
  if [ "$actual" = "1" ]; then
    ok "kernel.kptr_restrict = 1"
  elif [ "$severity" = "warn" ]; then
    warn "kernel.kptr_restrict esperado 1, actual ${actual:-desconocido}"
  else
    fail "kernel.kptr_restrict esperado 1, actual ${actual:-desconocido}"
  fi

  check_same_system_file "$ROOT_DIR/sysctl/99-zram.conf" /etc/sysctl.d/99-zram.conf "$severity"
  actual="$(sysctl -n vm.swappiness 2>/dev/null || true)"
  if [ "$actual" = "100" ]; then
    ok "vm.swappiness = 100"
  elif [ "$severity" = "warn" ]; then
    warn "vm.swappiness esperado 100, actual ${actual:-desconocido}"
  else
    fail "vm.swappiness esperado 100, actual ${actual:-desconocido}"
  fi
}

check_zram() {
  local severity="warn"
  [ "$STRICT_SYSTEM" -eq 1 ] && severity="fail"
  local swap_info priority comp_algorithm zram_bytes ram_bytes ratio device_present=0

  check_same_system_file "$ROOT_DIR/zram/zram-generator.conf" /etc/systemd/zram-generator.conf "$severity"
  if [ -e /dev/zram0 ]; then
    device_present=1
    ok "/dev/zram0 presente"
  fi

  if ! has_cmd swapon; then
    if [ "$severity" = "warn" ]; then
      warn "falta comando: swapon"
    else
      fail "falta comando: swapon"
    fi
  else
    swap_info="$(swapon --noheadings --raw --show=NAME,PRIO 2>/dev/null || true)"
    priority="$(printf '%s\n' "$swap_info" | awk '$1 == "/dev/zram0" {print $2; exit}')"
    if [ "$priority" = "100" ]; then
      ok "/dev/zram0 activa como swap con prioridad 100"
    elif [ -n "$priority" ]; then
      if [ "$severity" = "warn" ]; then
        warn "/dev/zram0 activa con prioridad inesperada: $priority"
      else
        fail "/dev/zram0 activa con prioridad inesperada: $priority"
      fi
    elif [ "$severity" = "warn" ]; then
      warn "/dev/zram0 no está activa como swap"
    else
      fail "/dev/zram0 no está activa como swap"
    fi
  fi

  if [ "$device_present" -eq 0 ] && [ -z "$priority" ]; then
    if [ "$severity" = "warn" ]; then
      warn "/dev/zram0 no encontrado"
    else
      fail "/dev/zram0 no encontrado"
    fi
    return
  elif [ "$device_present" -eq 0 ]; then
    ok "/dev/zram0 detectado mediante la swap activa"
  fi

  if [ -r /sys/block/zram0/comp_algorithm ]; then
    comp_algorithm="$(tr '\n' ' ' < /sys/block/zram0/comp_algorithm)"
    if printf '%s\n' "$comp_algorithm" | grep -Eq '(^|[[:space:]])\[zstd\]([[:space:]]|$)'; then
      ok "/dev/zram0 usa compresión zstd"
    elif [ "$severity" = "warn" ]; then
      warn "/dev/zram0 no tiene zstd seleccionado: ${comp_algorithm:-desconocido}"
    else
      fail "/dev/zram0 no tiene zstd seleccionado: ${comp_algorithm:-desconocido}"
    fi
  elif [ "$severity" = "warn" ]; then
    warn "no puedo leer el algoritmo de compresión de /dev/zram0"
  else
    fail "no puedo leer el algoritmo de compresión de /dev/zram0"
  fi

  if [ -r /sys/block/zram0/disksize ] && [ -r /proc/meminfo ]; then
    zram_bytes="$(cat /sys/block/zram0/disksize 2>/dev/null || true)"
    ram_bytes="$(awk '/^MemTotal:/{print $2 * 1024; exit}' /proc/meminfo)"
    ratio="$(awk -v zram="$zram_bytes" -v ram="$ram_bytes" 'BEGIN { if (ram > 0) print zram / ram }')"
    if awk -v ratio="$ratio" 'BEGIN { exit !(ratio >= 0.49 && ratio <= 0.51) }'; then
      ok "/dev/zram0 tiene un tamaño equivalente al 50 % de la RAM"
    elif [ "$severity" = "warn" ]; then
      warn "/dev/zram0 tiene tamaño inesperado: ${ratio:-desconocido} de la RAM"
    else
      fail "/dev/zram0 tiene tamaño inesperado: ${ratio:-desconocido} de la RAM"
    fi
  elif [ "$severity" = "warn" ]; then
    warn "no puedo calcular el tamaño de /dev/zram0 respecto de la RAM"
  else
    fail "no puedo calcular el tamaño de /dev/zram0 respecto de la RAM"
  fi
}

check_xdg_dirs() {
  if ! has_cmd xdg-user-dir; then
    fail "falta comando: xdg-user-dir"
    return
  fi

  local expected actual
  while IFS='=' read -r key expected; do
    actual="$(xdg-user-dir "$key" 2>/dev/null || true)"
    if [ "$actual" = "$expected" ]; then
      ok "XDG $key -> $actual"
    else
      fail "XDG $key esperado $expected, actual ${actual:-vacío}"
    fi
  done <<EOF
DESKTOP=$HOME/Escritorio
DOWNLOAD=$HOME/Descargas
TEMPLATES=$HOME/Plantillas
PUBLICSHARE=$HOME/Público
DOCUMENTS=$HOME/Documentos
MUSIC=$HOME/Música
PICTURES=$HOME/Imágenes
VIDEOS=$HOME/Vídeos
EOF
}

check_trash() {
  local base="$HOME/.local/share/Trash"
  local files_write=1
  local info_write=1
  local output
  local tmp

  if [ -d "$base/files" ] && [ -d "$base/info" ]; then
    ok "papelera XDG disponible: $base"
  else
    fail "falta papelera XDG en $base/{files,info}"
  fi

  tmp="$base/files/.check-write-$$"
  if output="$( { : > "$tmp"; } 2>&1)"; then
    rm -f "$tmp"
    files_write=0
  fi

  tmp="$base/info/.check-write-$$"
  if output="$( { : > "$tmp"; } 2>&1)"; then
    rm -f "$tmp"
    info_write=0
  fi

  if [ "$files_write" -eq 0 ] && [ "$info_write" -eq 0 ]; then
    ok "papelera XDG escribible"
  elif [ -O "$base/files" ] && [ -O "$base/info" ] && [ -w "$base/files" ] && [ -w "$base/info" ]; then
    warn "no puedo verificar escritura de papelera por permisos del entorno"
  elif printf '%s\n' "$output" | grep -Eq 'Read-only file system|Operation not permitted'; then
    warn "no puedo verificar escritura de papelera por permisos del entorno"
  else
    fail "papelera XDG no escribible"
  fi

  check_cmd trash-put
  check_cmd trash-list
  check_cmd trash-restore
  check_cmd trash-empty
}

check_yazi() {
  check_cmd yazi
  check_cmd ya
  has_cmd yazi || return

  local theme="$HOME/.config/yazi/theme.toml"
  if [ -f "$theme" ] && grep -Eq '^[[:space:]]*dark[[:space:]]*=[[:space:]]*"catppuccin-mocha"[[:space:]]*$' "$theme"; then
    ok "Yazi usa Catppuccin Mocha"
  else
    fail "Yazi no configura Catppuccin Mocha"
  fi

  local dep
  for dep in "pdftoppm" "magick" "fzf" "chafa" "zoxide"; do
    if has_cmd "$dep"; then
      ok "Yazi tiene dependencia disponible: $dep"
    else
      warn "Yazi no tiene dependencia disponible: $dep"
    fi
  done

  if has_cmd ya; then
    local packages
    packages="$(ya pkg list 2>/dev/null || true)"
    local item
    for item in full-border smart-enter smart-filter git mount chmod catppuccin-mocha; do
      if printf '%s\n' "$packages" | grep -q "$item"; then
        ok "Yazi paquete instalado: $item"
      else
        fail "falta paquete Yazi: $item"
      fi
    done
  fi

  local keymap="$HOME/.config/yazi/keymap.toml"
  if [ -f "$keymap" ] && grep -q 'run = "remove"' "$keymap"; then
    ok "Yazi mueve a papelera con tecla d"
  else
    fail "Yazi no tiene mapeada la papelera en keymap.toml"
  fi

  if [ -f "$keymap" ] && grep -q 'run = "remove --permanently"' "$keymap"; then
    ok "Yazi conserva borrado permanente en tecla D"
  else
    warn "Yazi no tiene mapeado borrado permanente explícito"
  fi

  if [ -f "$keymap" ] && grep -q 'run = "cd ~/.local/share/Trash/files"' "$keymap"; then
    ok "Yazi tiene atajo directo a papelera"
  else
    fail "Yazi no tiene atajo directo a papelera"
  fi
}

check_mpd_ncmpcpp() {
  local output

  check_cmd mpd
  check_cmd mpc
  check_cmd ncmpcpp

  if output="$(systemctl --user is-active mpd.service 2>&1)"; then
    ok "MPD activo"
  elif printf '%s\n' "$output" | grep -Eq 'Operation not permitted|Failed to connect to user scope bus'; then
    warn "no puedo verificar MPD activo por permisos del entorno"
  else
    fail "MPD no está activo"
  fi

  if output="$(systemctl --user is-enabled mpd.service 2>&1)"; then
    ok "MPD habilitado"
  elif printf '%s\n' "$output" | grep -Eq 'Operation not permitted|Failed to connect to user scope bus'; then
    warn "no puedo verificar si MPD está habilitado por permisos del entorno"
  else
    warn "MPD no está habilitado al inicio de sesión"
  fi

  if output="$(mpc status 2>&1)"; then
    ok "mpc conecta con MPD"
  elif printf '%s\n' "$output" | grep -q 'Operation not permitted'; then
    warn "no puedo verificar conexión mpc por permisos del entorno"
  else
    fail "mpc no puede conectar con MPD"
  fi

  if [ -d "$HOME/Música" ]; then
    ok "biblioteca musical existe: $HOME/Música"
  else
    fail "falta biblioteca musical: $HOME/Música"
  fi

  if [ -p /tmp/mpd.fifo ]; then
    ok "FIFO de visualizador MPD disponible"
  else
    warn "FIFO de visualizador MPD no disponible"
  fi
}

check_bash_scripts() {
  local script
  for script in "$ROOT_DIR"/home/.local/bin/* "$ROOT_DIR"/restore.sh; do
    [ -f "$script" ] || continue
    if bash -n "$script"; then
      ok "bash -n: $script"
    else
      fail "error de sintaxis bash: $script"
    fi
  done
}

check_session_config() {
  local output

  if output="$(HOME="$ROOT_DIR/home" sway -C -c "$ROOT_DIR/home/.config/sway/config" 2>&1)"; then
    ok "configuración de Sway válida"
  elif printf '%s\n' "$output" | grep -Eq 'Operation not permitted|Unable to create backend|Could not connect to remote display'; then
    warn "no puedo validar Sway por permisos del entorno"
  else
    fail "configuración de Sway inválida"
    printf '%s\n' "$output"
  fi

  if python -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' \
      "$ROOT_DIR/home/.config/waybar/config.jsonc"; then
    ok "configuración JSON de Waybar válida"
  else
    fail "configuración JSON de Waybar inválida"
  fi

  local script
  for script in waybar-battery disk-status; do
    if "$ROOT_DIR/home/.local/bin/$script" | python -c 'import json, sys; json.load(sys.stdin)'; then
      ok "salida JSON válida: $script"
    else
      fail "salida JSON inválida: $script"
    fi
  done
}

check_session_processes() {
  local process expected count output

  for process in swayidle disk-notify; do
    expected=1
    if [ "$process" = "swayidle" ]; then
      count="$(pgrep -u "$(id -u)" -xc swayidle 2>/dev/null || true)"
    else
      count="$(pgrep -u "$(id -u)" -fc "$HOME/.local/bin/disk-notify" 2>/dev/null || true)"
    fi

    if [ "$count" = "$expected" ]; then
      ok "una instancia activa: $process"
    elif [ "$count" -gt "$expected" ] 2>/dev/null; then
      fail "hay $count instancias activas de $process"
    else
      warn "$process no está activo"
    fi
  done

  for process in \
    sway-session.target \
    graphical-session.target \
    waybar.service \
    mako.service \
    sway-polkit-agent.service \
    sway-udiskie.service \
    disk-notify.service \
    swayidle.service; do
    if output="$(systemctl --user is-active "$process" 2>&1)"; then
      ok "$process activo"
    elif printf '%s\n' "$output" | grep -Eq 'Operation not permitted|Failed to connect to user scope bus'; then
      warn "no puedo verificar $process por permisos del entorno"
    else
      fail "$process no está activo"
    fi
  done
}

check_package_hygiene() {
  local orphans
  orphans="$(pacman -Qdtq 2>/dev/null || true)"
  if [ -z "$orphans" ]; then
    ok "sin paquetes huérfanos"
  else
    warn "paquetes huérfanos detectados: $(printf '%s' "$orphans" | tr '\n' ' ')"
  fi
}

check_managed_bin_extras() {
  local file name
  local extras=0

  for file in "$HOME"/.local/bin/*; do
    [ -f "$file" ] || continue
    name="$(basename "$file")"
    if [ ! -f "$ROOT_DIR/home/.local/bin/$name" ]; then
      if [ -f "$LOCAL_BIN_KEEP_FILE" ] && grep -Fqx -- "$name" "$LOCAL_BIN_KEEP_FILE"; then
        ok "herramienta externa preservada: $file"
      else
        warn "script local no administrado por el repo: $file"
        extras=$((extras + 1))
      fi
    fi
  done

  if [ "$extras" -eq 0 ]; then
    ok "sin scripts residuales en ~/.local/bin"
  fi
}

check_project_tests() {
  local test
  for test in "$ROOT_DIR"/tests/test-*.sh; do
    [ -f "$test" ] || continue
    if "$test" >/dev/null; then
      ok "prueba automatizada: $(basename "$test")"
    else
      fail "falló prueba automatizada: $(basename "$test")"
    fi
  done
}

check_system_health() {
  [ "$STRICT_SYSTEM" -eq 1 ] || return 0

  local failed journal_errors root_source root_disk smart_output listeners
  failed="$(systemctl --failed --no-legend --plain 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l)"
  if [ "$failed" -eq 0 ]; then
    ok "sin unidades de sistema fallidas"
  else
    fail "$failed unidades de sistema fallidas"
    systemctl --failed --no-pager || true
  fi

  # JSON emite un registro por línea; la salida humana puede incluir stacks
  # multilínea y exagerar el número real de eventos.
  journal_errors="$(journalctl -b -p err --no-pager -q -o json 2>/dev/null | wc -l)"
  if [ "$journal_errors" -eq 0 ]; then
    ok "journal del arranque sin errores"
  else
    warn "$journal_errors entradas de error en el journal del arranque"
  fi

  listeners="$(ss -lntH 2>/dev/null | awk '{print $4}' | sort -u | tr '\n' ' ')"
  if [ -n "$listeners" ]; then
    ok "puertos TCP en escucha inventariados: $listeners"
  else
    warn "no pude inventariar puertos TCP en escucha"
  fi

  if ! sudo_check true; then
    fail "no puedo verificar SMART $(sudo_check_label)"
    return
  fi

  root_source="$(findmnt -no SOURCE / 2>/dev/null || true)"
  root_disk="$(lsblk -ndo PKNAME "$root_source" 2>/dev/null | head -n1)"
  [ -n "$root_disk" ] || root_disk="$(basename "$root_source")"
  smart_output="$(sudo_check smartctl -H "/dev/$root_disk" || true)"
  if printf '%s\n' "$smart_output" | grep -Eq 'PASSED|OK'; then
    ok "SMART saludable: /dev/$root_disk"
  else
    fail "SMART no confirmó estado saludable: /dev/$root_disk"
  fi
}

check_core_commands() {
  local cmd
  for cmd in sway waybar foot fuzzel mako yazi ya wl-copy rg fd mpv playerctl udisksctl brightnessctl wpctl notify-send python lsblk impala iwctl btop ncspot pyradio; do
    check_cmd "$cmd"
  done
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --system) STRICT_SYSTEM=1 ;;
    --sudo) ALLOW_SUDO_PROMPT=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Opción desconocida: %s\n\n' "$1"; usage; exit 2 ;;
  esac
  shift
done

prepare_sudo

check_packages pacman "$ROOT_DIR/docs/pkglist-pacman.txt"
check_packages AUR "$ROOT_DIR/docs/pkglist-aur.txt"
check_core_commands
check_user_files
check_bash_scripts
check_session_config
check_session_processes
check_package_hygiene
check_managed_bin_extras
check_project_tests
check_system_health
check_xdg_dirs
check_trash
check_yazi
check_mpd_ncmpcpp
check_polkit
check_bootloader
check_sshd
check_nftables
check_iwd
check_sysctl
check_zram
check_repo_state

printf '\nResumen: %d fallos, %d advertencias\n' "$FAILS" "$WARNS"

if [ "$FAILS" -gt 0 ]; then
  exit 1
fi

exit 0
