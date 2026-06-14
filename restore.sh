#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
YES=0
INSTALL_PACKAGES=0
INSTALL_AUR=0
RESTORE_USER=1
INSTALL_POLKIT=0
INSTALL_BOOTLOADER=0
INSTALL_SSHD=0
INSTALL_YAZI=1

usage() {
  cat <<'EOF'
Uso: ./restore.sh [opciones]

Por defecto:
  - Copia home/ sobre $HOME.
  - Ajusta permisos de ~/.local/bin.
  - Instala paquetes/plugins de Yazi si ya está disponible `ya`.

Opciones:
  --packages    Instala paquetes pacman desde docs/pkglist-pacman.txt.
  --aur         Instala paquetes AUR desde docs/pkglist-aur.txt usando yay.
  --polkit      Copia reglas polkit a /etc/polkit-1/rules.d/.
  --bootloader  Copia loader.conf y arch.conf a /boot/loader/.
  --sshd        Copia hardening de sshd a /etc/ssh/sshd_config.d/.
  --all         Ejecuta packages, aur, user, yazi, polkit, bootloader y sshd.
  --no-user     No copia home/ sobre $HOME.
  --no-yazi     No ejecuta ya pkg install.
  --dry-run     Muestra acciones sin ejecutarlas.
  -y, --yes     No pide confirmación.
  -h, --help    Muestra esta ayuda.
EOF
}

log() {
  printf '==> %s\n' "$*"
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+'
    local arg
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
  else
    "$@"
  fi
}

confirm() {
  [ "$YES" -eq 1 ] && return 0

  local answer
  printf '%s [y/N] ' "$1"
  read -r answer
  case "$answer" in
    y|Y|yes|YES|si|SI|sí|SÍ) ;;
    *) log "Cancelado"; exit 1 ;;
  esac
}

read_packages() {
  local file="$1"
  grep -Ev '^\s*($|#)' "$file"
}

install_pacman_packages() {
  local file="$ROOT_DIR/docs/pkglist-pacman.txt"
  [ -f "$file" ] || { log "No existe $file"; return 1; }

  mapfile -t packages < <(read_packages "$file")
  [ "${#packages[@]}" -gt 0 ] || { log "No hay paquetes pacman"; return 0; }

  log "Instalando paquetes pacman"
  run sudo pacman -S --needed "${packages[@]}"
}

install_aur_packages() {
  local file="$ROOT_DIR/docs/pkglist-aur.txt"
  [ -f "$file" ] || { log "No existe $file"; return 1; }

  if ! command -v yay >/dev/null 2>&1; then
    log "yay no está disponible; instalá yay manualmente y repetí con --aur"
    return 1
  fi

  mapfile -t packages < <(read_packages "$file")
  [ "${#packages[@]}" -gt 0 ] || { log "No hay paquetes AUR"; return 0; }

  log "Instalando paquetes AUR"
  run yay -S --needed "${packages[@]}"
}

restore_user_files() {
  local source="$ROOT_DIR/home"
  [ -d "$source" ] || { log "No existe $source"; return 1; }

  confirm "Esto copiará $source/ sobre $HOME. ¿Continuar?"
  log "Restaurando archivos de usuario"
  run mkdir -p "$HOME"
  run cp -a "$source/." "$HOME/"

  if [ "$DRY_RUN" -eq 1 ] && [ -d "$source/.local/bin" ]; then
    log "Ajustando permisos ejecutables en ~/.local/bin"
    while IFS= read -r file; do
      printf '+ chmod +x %q\n' "$HOME/.local/bin/$(basename "$file")"
    done < <(find "$source/.local/bin" -maxdepth 1 -type f | sort)
  elif [ -d "$HOME/.local/bin" ]; then
    log "Ajustando permisos ejecutables en ~/.local/bin"
    find "$HOME/.local/bin" -maxdepth 1 -type f -exec chmod +x {} +
  fi

  if [ -d "$HOME/.ssh" ]; then
    log "Ajustando permisos de ~/.ssh"
    run chmod 700 "$HOME/.ssh"
    if [ -f "$HOME/.ssh/authorized_keys" ]; then
      run chmod 600 "$HOME/.ssh/authorized_keys"
    fi
  fi

  if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    log "Actualizando carpetas XDG"
    run env LANG=es_AR.UTF-8 LC_ALL=es_AR.UTF-8 xdg-user-dirs-update
  fi

  log "Asegurando papelera XDG"
  run mkdir -p "$HOME/.local/share/Trash/files" "$HOME/.local/share/Trash/info"

  log "Asegurando directorios de MPD/ncmpcpp"
  run mkdir -p "$HOME/.local/share/mpd/playlists" "$HOME/.local/share/ncmpcpp/lyrics"
}

install_yazi_packages() {
  local yazi_dir="$HOME/.config/yazi"
  [ -f "$yazi_dir/package.toml" ] || { log "No existe $yazi_dir/package.toml"; return 0; }

  if ! command -v ya >/dev/null 2>&1; then
    log "ya no está disponible; instalá yazi y repetí este paso"
    return 0
  fi

  log "Instalando plugins/flavors de Yazi"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ cd %q && ya pkg install\n' "$yazi_dir"
  else
    (cd "$yazi_dir" && ya pkg install)
  fi
}

install_polkit_rules() {
  local dir="$ROOT_DIR/polkit"
  [ -d "$dir" ] || { log "No existe $dir"; return 1; }

  confirm "Esto copiará reglas polkit a /etc/polkit-1/rules.d/. ¿Continuar?"
  log "Instalando reglas polkit"
  for file in "$dir"/*.rules; do
    [ -f "$file" ] || continue
    run sudo install -Dm644 "$file" "/etc/polkit-1/rules.d/$(basename "$file")"
  done
}

install_bootloader_files() {
  confirm "Esto copiará archivos a /boot/loader/. Revisá antes si el disco/entrada coincide. ¿Continuar?"
  log "Instalando configuración de systemd-boot"
  run sudo install -Dm644 "$ROOT_DIR/bootloader/loader.conf" /boot/loader/loader.conf
  run sudo install -Dm644 "$ROOT_DIR/bootloader/arch.conf" /boot/loader/entries/arch.conf
}

install_sshd_config() {
  local dir="$ROOT_DIR/sshd"
  [ -d "$dir" ] || { log "No existe $dir"; return 1; }

  confirm "Esto copiará hardening de sshd y recargará sshd. ¿Continuar?"
  log "Instalando configuración de sshd"
  for file in "$dir"/*.conf; do
    [ -f "$file" ] || continue
    run sudo install -Dm644 "$file" "/etc/ssh/sshd_config.d/$(basename "$file")"
  done
  run sudo sshd -t
  run sudo systemctl reload sshd.service
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --packages) INSTALL_PACKAGES=1 ;;
    --aur) INSTALL_AUR=1 ;;
    --polkit) INSTALL_POLKIT=1 ;;
    --bootloader) INSTALL_BOOTLOADER=1 ;;
    --sshd) INSTALL_SSHD=1 ;;
    --all)
      INSTALL_PACKAGES=1
      INSTALL_AUR=1
      RESTORE_USER=1
      INSTALL_YAZI=1
      INSTALL_POLKIT=1
      INSTALL_BOOTLOADER=1
      INSTALL_SSHD=1
      ;;
    --no-user) RESTORE_USER=0 ;;
    --no-yazi) INSTALL_YAZI=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -y|--yes) YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Opción desconocida: %s\n\n' "$1"; usage; exit 2 ;;
  esac
  shift
done

[ "$INSTALL_PACKAGES" -eq 1 ] && install_pacman_packages
[ "$INSTALL_AUR" -eq 1 ] && install_aur_packages
[ "$RESTORE_USER" -eq 1 ] && restore_user_files
[ "$INSTALL_YAZI" -eq 1 ] && install_yazi_packages
[ "$INSTALL_POLKIT" -eq 1 ] && install_polkit_rules
[ "$INSTALL_BOOTLOADER" -eq 1 ] && install_bootloader_files
[ "$INSTALL_SSHD" -eq 1 ] && install_sshd_config

log "Restauración finalizada"
