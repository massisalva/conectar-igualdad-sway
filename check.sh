#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FAILS=0
WARNS=0
STRICT_SYSTEM=0
ALLOW_SUDO_PROMPT=0
SUDO_READY=0

usage() {
  cat <<'EOF'
Uso: ./check.sh [opciones]

Por defecto verifica el estado de usuario, paquetes, Yazi, XDG y repo.
Los archivos de sistema en polkit/, bootloader/, sshd/, nftables/ e iwd/ se reportan como advertencia.

Opciones:
  --system    Trata polkit/, bootloader/, sshd/, nftables/ e iwd/ como checks obligatorios.
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
}

check_iwd() {
  local severity="warn"
  [ "$STRICT_SYSTEM" -eq 1 ] && severity="fail"
  local service output resolv_target

  check_same_system_file "$ROOT_DIR/iwd/main.conf" /etc/iwd/main.conf "$severity"

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

  local debug
  debug="$(yazi --debug 2>&1)"
  if printf '%s\n' "$debug" | grep -q 'Dark/light flavor: ArcSwapAny("catppuccin-mocha")'; then
    ok "Yazi usa Catppuccin Mocha"
  else
    fail "Yazi no reporta Catppuccin Mocha"
  fi

  local dep
  for dep in "ueberzugpp" "pdftoppm" "magick" "fzf" "chafa" "zoxide"; do
    if printf '%s\n' "$debug" | grep -Eq "^[[:space:]]+$dep[[:space:]]+:[[:space:]]+[0-9]"; then
      ok "Yazi detecta dependencia: $dep"
    else
      warn "Yazi no detecta dependencia: $dep"
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
check_xdg_dirs
check_trash
check_yazi
check_mpd_ncmpcpp
check_polkit
check_bootloader
check_sshd
check_nftables
check_iwd
check_repo_state

printf '\nResumen: %d fallos, %d advertencias\n' "$FAILS" "$WARNS"

if [ "$FAILS" -gt 0 ]; then
  exit 1
fi

exit 0
