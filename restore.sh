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
INSTALL_NFTABLES=0
INSTALL_IWD=0
INSTALL_SYSCTL=0
INSTALL_YAZI=1
PRUNE=0
BACKUP_ENABLED=1
BACKUP_DIR=""
BACKUP_ROOT="${RESTORE_BACKUP_ROOT:-$ROOT_DIR/backups}"
ROLLBACK_DIR=""
declare -A BACKED_UP

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
  --nftables    Copia firewall nftables y habilita nftables.service.
  --iwd         Configura iwd y systemd-resolved.
  --sysctl      Instala ajustes locales de endurecimiento del kernel.
  --all         Ejecuta packages, aur, user, yazi y todas las piezas de sistema.
  --no-user     No copia home/ sobre $HOME.
  --no-yazi     No ejecuta ya pkg install.
  --prune       Elimina scripts residuales de ~/.local/bin después de respaldarlos.
  --no-backup   No crea backup previo de los archivos reemplazados.
  --rollback DIR  Restaura los archivos registrados en un backup anterior.
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

ensure_backup_dir() {
  [ "$BACKUP_ENABLED" -eq 1 ] || return 0
  [ -z "$BACKUP_DIR" ] || return 0

  BACKUP_DIR="$BACKUP_ROOT/restore-$(date +%Y%m%d-%H%M%S)-$$"
  log "Backup previo: $BACKUP_DIR"
  run mkdir -p "$BACKUP_DIR/files"
}

is_system_path() {
  case "$1" in
    /etc/*|/boot/*) return 0 ;;
    *) return 1 ;;
  esac
}

backup_target() {
  local target="$1"
  local backup_file
  local exists=0

  [ "$BACKUP_ENABLED" -eq 1 ] || return 0
  [ -z "${BACKED_UP[$target]:-}" ] || return 0
  BACKED_UP[$target]=1
  ensure_backup_dir
  backup_file="$BACKUP_DIR/files$target"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ backup-if-present %q -> %q\n' "$target" "$backup_file"
    return 0
  fi

  if is_system_path "$target"; then
    sudo -v
    if sudo test -e "$target" || sudo test -L "$target"; then
      exists=1
    fi
  elif [ -e "$target" ] || [ -L "$target" ]; then
    exists=1
  fi

  if [ "$exists" -eq 1 ]; then
    mkdir -p "$(dirname "$backup_file")"
    if is_system_path "$target"; then
      sudo cp -a "$target" "$backup_file"
    else
      cp -a "$target" "$backup_file"
    fi
    printf 'present\t%s\n' "$target" >> "$BACKUP_DIR/manifest.tsv"
  else
    printf 'missing\t%s\n' "$target" >> "$BACKUP_DIR/manifest.tsv"
  fi
}

rollback_backup() {
  local dir="$1"
  local manifest="$dir/manifest.tsv"
  local state target backup_file

  [ -f "$manifest" ] || { log "No existe un manifiesto válido en $dir"; return 1; }
  confirm "Esto restaurará los archivos registrados en $dir. ¿Continuar?"

  while IFS=$'\t' read -r state target; do
    [ -n "$target" ] || continue
    backup_file="$dir/files$target"

    case "$state" in
      present)
        [ -e "$backup_file" ] || [ -L "$backup_file" ] || {
          log "Falta el archivo respaldado: $backup_file"
          return 1
        }
        log "Restaurando $target"
        if is_system_path "$target"; then
          run sudo mkdir -p "$(dirname "$target")"
          run sudo cp -a --remove-destination "$backup_file" "$target"
        else
          run mkdir -p "$(dirname "$target")"
          run cp -a --remove-destination "$backup_file" "$target"
        fi
        ;;
      missing)
        log "Quitando archivo que no existía antes: $target"
        if is_system_path "$target"; then
          run sudo rm -f "$target"
        else
          run rm -f "$target"
        fi
        ;;
      *)
        log "Estado desconocido en manifiesto: $state"
        return 1
        ;;
    esac
  done < "$manifest"

  log "Rollback finalizado"
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
  local source_file rel target
  [ -d "$source" ] || { log "No existe $source"; return 1; }

  confirm "Esto copiará $source/ sobre $HOME. ¿Continuar?"
  while IFS= read -r source_file; do
    rel="${source_file#"$source/"}"
    target="$HOME/$rel"
    backup_target "$target"
  done < <(find "$source" \( -type f -o -type l \) | sort)

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

  if [ -d "$source/.config/systemd/user" ] && command -v systemctl >/dev/null 2>&1; then
    log "Recargando units de systemd de usuario"
    run systemctl --user daemon-reload
  fi

  if [ "$PRUNE" -eq 1 ]; then
    prune_user_bin
  fi
}

prune_user_bin() {
  local file name found=0

  for file in "$HOME"/.local/bin/*; do
    [ -f "$file" ] || [ -L "$file" ] || continue
    name="$(basename "$file")"
    [ -e "$ROOT_DIR/home/.local/bin/$name" ] && continue

    if [ "$found" -eq 0 ]; then
      confirm "Se quitarán scripts de ~/.local/bin que no están en el repo, con backup previo. ¿Continuar?"
    fi
    found=1
    backup_target "$file"
    log "Quitando script residual: $file"
    run rm -f "$file"
  done

  [ "$found" -eq 1 ] || log "No hay scripts residuales para quitar"
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
    backup_target "/etc/polkit-1/rules.d/$(basename "$file")"
    run sudo install -Dm644 "$file" "/etc/polkit-1/rules.d/$(basename "$file")"
  done
}

install_bootloader_files() {
  local entry="$ROOT_DIR/bootloader/arch.conf"
  local configured_uuid actual_uuid

  [ -f "$entry" ] || { log "No existe $entry"; return 1; }

  configured_uuid="$(sed -n 's/.*root=UUID=\([^[:space:]]*\).*/\1/p' "$entry" | head -n1)"
  actual_uuid="$(findmnt -no UUID / 2>/dev/null || true)"

  if [ -z "$configured_uuid" ]; then
    log "No pude encontrar root=UUID en $entry"
    return 1
  fi

  if [ -z "$actual_uuid" ]; then
    log "No pude determinar el UUID de la raíz activa"
    return 1
  fi

  if [ "$configured_uuid" != "$actual_uuid" ]; then
    log "El UUID de arch.conf ($configured_uuid) no coincide con la raíz activa ($actual_uuid)"
    log "No instalo el bootloader para evitar una entrada que no pueda arrancar"
    return 1
  fi

  log "UUID del bootloader verificado: $actual_uuid"
  confirm "Esto copiará archivos a /boot/loader/. Revisá antes si el disco/entrada coincide. ¿Continuar?"
  log "Instalando configuración de systemd-boot"
  backup_target /boot/loader/loader.conf
  backup_target /boot/loader/entries/arch.conf
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
    backup_target "/etc/ssh/sshd_config.d/$(basename "$file")"
    run sudo install -Dm644 "$file" "/etc/ssh/sshd_config.d/$(basename "$file")"
  done
  run sudo sshd -t
  run sudo systemctl reload sshd.service
}

install_nftables_config() {
  local file="$ROOT_DIR/nftables/nftables.conf"
  [ -f "$file" ] || { log "No existe $file"; return 1; }

  confirm "Esto instalará nftables.conf, reemplazará reglas activas y habilitará nftables.service. ¿Continuar?"
  log "Validando configuración de nftables"
  run sudo nft -c -f "$file"

  log "Instalando configuración de nftables"
  backup_target /etc/nftables.conf
  run sudo install -Dm644 "$file" /etc/nftables.conf
  run sudo systemctl enable --now nftables.service
}

install_iwd_config() {
  local file="$ROOT_DIR/iwd/main.conf"
  local regdom_file="$ROOT_DIR/iwd/wireless-regdom.conf"
  [ -f "$file" ] || { log "No existe $file"; return 1; }
  [ -f "$regdom_file" ] || { log "No existe $regdom_file"; return 1; }

  confirm "Esto instalará la configuración de iwd y systemd-resolved. ¿Continuar?"
  log "Instalando configuración de iwd"
  backup_target /etc/iwd/main.conf
  run sudo install -Dm644 "$file" /etc/iwd/main.conf

  log "Configurando dominio regulatorio Wi-Fi de Argentina"
  backup_target /etc/conf.d/wireless-regdom
  run sudo install -Dm644 "$regdom_file" /etc/conf.d/wireless-regdom
  run sudo /usr/bin/set-wireless-regdom

  log "Configurando resolución DNS con systemd-resolved"
  run sudo systemctl enable --now systemd-resolved.service
  backup_target /etc/resolv.conf
  run sudo ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

  log "Habilitando el gestor Wi-Fi iwd"
  run sudo systemctl enable --now iwd.service
}

install_sysctl_config() {
  local file="$ROOT_DIR/sysctl/99-local-hardening.conf"
  [ -f "$file" ] || { log "No existe $file"; return 1; }

  confirm "Esto instalará ajustes locales de endurecimiento del kernel. ¿Continuar?"
  log "Instalando ajustes sysctl locales"
  backup_target /etc/sysctl.d/99-local-hardening.conf
  run sudo install -Dm644 "$file" /etc/sysctl.d/99-local-hardening.conf
  run sudo sysctl --system
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --packages) INSTALL_PACKAGES=1 ;;
    --aur) INSTALL_AUR=1 ;;
    --polkit) INSTALL_POLKIT=1 ;;
    --bootloader) INSTALL_BOOTLOADER=1 ;;
    --sshd) INSTALL_SSHD=1 ;;
    --nftables) INSTALL_NFTABLES=1 ;;
    --iwd) INSTALL_IWD=1 ;;
    --sysctl) INSTALL_SYSCTL=1 ;;
    --all)
      INSTALL_PACKAGES=1
      INSTALL_AUR=1
      RESTORE_USER=1
      INSTALL_YAZI=1
      INSTALL_POLKIT=1
      INSTALL_BOOTLOADER=1
      INSTALL_SSHD=1
      INSTALL_NFTABLES=1
      INSTALL_IWD=1
      INSTALL_SYSCTL=1
      ;;
    --no-user) RESTORE_USER=0 ;;
    --no-yazi) INSTALL_YAZI=0 ;;
    --prune) PRUNE=1 ;;
    --no-backup) BACKUP_ENABLED=0 ;;
    --rollback)
      [ "$#" -ge 2 ] || { log "--rollback requiere un directorio"; exit 2; }
      ROLLBACK_DIR="$2"
      shift
      ;;
    --dry-run) DRY_RUN=1 ;;
    -y|--yes) YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Opción desconocida: %s\n\n' "$1"; usage; exit 2 ;;
  esac
  shift
done

if [ "$PRUNE" -eq 1 ] && [ "$BACKUP_ENABLED" -ne 1 ]; then
  log "--prune requiere backups; quitá --no-backup"
  exit 2
fi

if [ -n "$ROLLBACK_DIR" ]; then
  rollback_backup "$ROLLBACK_DIR"
  exit 0
fi

[ "$INSTALL_PACKAGES" -eq 1 ] && install_pacman_packages
[ "$INSTALL_AUR" -eq 1 ] && install_aur_packages
[ "$RESTORE_USER" -eq 1 ] && restore_user_files
[ "$INSTALL_YAZI" -eq 1 ] && install_yazi_packages
[ "$INSTALL_POLKIT" -eq 1 ] && install_polkit_rules
[ "$INSTALL_BOOTLOADER" -eq 1 ] && install_bootloader_files
[ "$INSTALL_SSHD" -eq 1 ] && install_sshd_config
[ "$INSTALL_NFTABLES" -eq 1 ] && install_nftables_config
[ "$INSTALL_IWD" -eq 1 ] && install_iwd_config
[ "$INSTALL_SYSCTL" -eq 1 ] && install_sysctl_config

if [ -n "$BACKUP_DIR" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    log "El backup se crearía en: $BACKUP_DIR"
  else
    log "Backup disponible en: $BACKUP_DIR"
  fi
fi
log "Restauración finalizada"
