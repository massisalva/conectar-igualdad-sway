#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/system-files.sh
source "$ROOT_DIR/lib/system-files.sh" || exit 1
DRY_RUN=0
YES=0
INSTALL_PACKAGES=0
INSTALL_AUR=0
# Vacíos = se deciden después de leer las opciones (ver PIECES_REQUESTED).
RESTORE_USER=
INSTALL_POLKIT=0
INSTALL_BOOTLOADER=0
INSTALL_SSHD=0
INSTALL_NFTABLES=0
INSTALL_IWD=0
INSTALL_SYSCTL=0
INSTALL_ZRAM=0
INSTALL_SAMBA=0
INSTALL_POWER=0
INSTALL_YAZI=
PRUNE=0
BACKUP_ENABLED=1
BACKUP_DIR=""
BACKUP_ROOT="${RESTORE_BACKUP_ROOT:-$ROOT_DIR/backups}"
ROLLBACK_DIR=""
LOCAL_BIN_KEEP_FILE="$ROOT_DIR/docs/local-bin-keep.txt"
LOCAL_BIN_RETIRED_FILE="$ROOT_DIR/docs/local-bin-retired.txt"
declare -A BACKED_UP

usage() {
  cat <<'EOF'
Uso: ./restore.sh [opciones]

Sin opciones de piezas:
  - Copia home/ sobre $HOME.
  - Ajusta permisos de ~/.local/bin.
  - Habilita e inicia MPD si está instalado y systemctl está disponible.
  - Instala paquetes/plugins de Yazi si ya está disponible `ya`.

Si pedís solo piezas (--packages, --aur o una de sistema como --power), se
hace solo eso: $HOME y Yazi quedan como están, salvo que sumes --user o --yazi.

Opciones:
  --packages    Instala paquetes pacman desde docs/pkglist-pacman.txt.
  --aur         Instala paquetes AUR desde docs/pkglist-aur.txt usando yay.
  --polkit      Copia reglas polkit a /etc/polkit-1/rules.d/.
  --bootloader  Copia loader.conf y arch.conf a /boot/loader/.
  --sshd        Copia hardening de sshd a /etc/ssh/sshd_config.d/.
  --nftables    Copia firewall nftables y habilita nftables.service.
  --iwd         Configura iwd y systemd-resolved.
  --sysctl      Instala ajustes locales de sysctl en /etc/sysctl.d/.
  --zram        Instala configuración de zram-generator en /etc/systemd/.
  --samba       Monta sola la carpeta compartida de la Mac mini en ~/Compartido
                (automount de systemd). La contraseña no está en el repo: si falta
                /etc/samba/credenciales-mini, la pide.
  --power       Habilita UPower: con batería crítica (2 %) actúa en vez de
                dejar que la Conectar se apague de golpe.
  --all         Ejecuta packages, aur, user, yazi y todas las piezas de sistema.
  --user        Copia home/ sobre $HOME también al pedir piezas sueltas.
  --yazi        Ejecuta ya pkg install también al pedir piezas sueltas.
  --no-user     No copia home/ sobre $HOME.
  --no-yazi     No ejecuta ya pkg install.
  --prune       Quita de ~/.local/bin, con backup, los scripts que el proyecto
                retiró (docs/local-bin-retired.txt). Lo desconocido se conserva.
  --no-backup   No crea backup previo de los archivos reemplazados.
  --rollback DIR  Restaura los archivos (y permisos) registrados en un backup
                anterior. No desinstala paquetes ni deshace servicios
                habilitados, preferencias de gsettings o carpetas creadas.
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

  BACKUP_DIR="$BACKUP_ROOT/restore-$(date +%Y%m%d-%H%M%S-%N)-$$"
  log "Backup previo: $BACKUP_DIR"
  run install -d -m700 "$BACKUP_DIR"
  run mkdir -p "$BACKUP_DIR/files"
}

is_system_path() {
  case "$1" in
    /etc/*|/boot/*) return 0 ;;
    *) return 1 ;;
  esac
}

is_allowed_target() {
  local target="$1"

  case "$target" in
    *$'\t'*|*$'\n'*|*'//'*) return 1 ;;
  esac
  case "/$target/" in
    */../*|*/./*) return 1 ;;
  esac

  case "$target" in
    "$HOME"/*) return 0 ;;
    /etc/*|/boot/*) is_managed_system_target "$target" ;;
    *) return 1 ;;
  esac
}

# La autorización usa igualdad exacta contra el inventario compartido.
is_managed_system_target() {
  local target="$1"
  system_target_registered "$target" || return 1
  [ "$(realpath -m -- "$(dirname -- "$target")")" = "$(dirname -- "$target")" ]
}

# Solo instala registros del inventario; los efectos de servicios quedan en cada
# install_* para conservar su orden y sus validaciones particulares.
install_system_group() {
  local selected="$1" group kind source target mode
  while IFS='|' read -r group kind source target mode; do
    backup_target "$target"
    case "$kind" in
      file) run sudo install -Dm"${mode/#-/644}" "$ROOT_DIR/$source" "$target" ;;
      link) run sudo ln -sfn "$source" "$target" ;;
      *) log "Tipo de archivo de sistema desconocido: $kind"; return 1 ;;
    esac
  done < <(system_files "$selected")
}

# No seguir directorios enlazados fuera de HOME al copiar o recuperar archivos.
# El enlace final sí puede respaldarse y reemplazarse como archivo.
validate_user_parent() {
  local target="$1" parent home_root
  case "$target" in
    "$HOME"/*)
      home_root="$(realpath -m -- "$HOME")"
      parent="$(realpath -m -- "$(dirname -- "$target")")"
      case "$parent/" in
        "$home_root/"*) ;;
        *) log "Directorio de destino fuera de HOME: $target"; return 1 ;;
      esac
      ;;
  esac
}

# Archivos a los que restore_user_files les cierra los permisos (chmod 700/600).
# chmod sigue los enlaces y el backup guarda el enlace, no el modo del archivo
# real: un enlace cambiaría un archivo que el rollback no sabe recuperar.
# Si los permisos ya son los esperados no hay nada que respaldar ni cambiar.
# Antes cada restauración volvía a copiar a backups/ el config.toml de
# Streamrip, que tiene el token de Deezer (auditoría 2026-11-20, H6).
mode_is() {  # archivo modo
  [ "$(stat -c '%a' -- "$1" 2>/dev/null)" = "$2" ]
}

validate_hardened_targets() {
  local target
  for target in "$HOME/.ssh" "$HOME/.ssh/authorized_keys" \
      "$HOME/.config/streamrip/config.toml"; do
    validate_user_parent "$target" || return 1
    if [ -L "$target" ]; then
      log "Es un enlace simbólico y no le cambio los permisos: $target"
      log "Reemplazalo por el archivo o la carpeta real y volvé a correr."
      return 1
    fi
  done
}

validate_rollback() {
  local dir="$1" state target backup_file
  while IFS=$'\t' read -r state target || [ -n "$state$target" ]; do
    if [ -z "$target" ] || ! is_allowed_target "$target"; then
      log "Ruta no permitida en el manifiesto: $target"
      return 1
    fi
    validate_user_parent "$target" || return 1
    backup_file="$dir/files$target"
    case "$state" in
      present)
        if { [ ! -f "$backup_file" ] && [ ! -L "$backup_file" ]; } ||
            { [ -d "$target" ] && [ ! -L "$target" ]; }; then
          log "Archivo de rollback ausente o destino incompatible: $target"
          return 1
        fi
        ;;
      missing)
        if [ -d "$target" ] && [ ! -L "$target" ]; then
          log "El destino ahora es un directorio: $target"
          return 1
        fi
        ;;
      directory-mode:*)
        if [[ ! "${state#directory-mode:}" =~ ^[0-7]{3,4}$ ]] ||
            [ ! -d "$target" ] || [ -L "$target" ]; then
          log "Modo o directorio inválido en el manifiesto: $target"
          return 1
        fi
        ;;
      *) log "Estado desconocido en manifiesto: $state"; return 1 ;;
    esac
  done < "$dir/manifest.tsv"
}

is_kept_local_bin() {
  local name="$1"

  [ -f "$LOCAL_BIN_KEEP_FILE" ] || return 1
  grep -Fqx -- "$name" "$LOCAL_BIN_KEEP_FILE"
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

backup_directory_mode() {
  local target="$1" mode

  [ "$BACKUP_ENABLED" -eq 1 ] || return 0
  [ -z "${BACKED_UP[$target]:-}" ] || return 0
  BACKED_UP[$target]=1
  ensure_backup_dir
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ backup-directory-mode %q\n' "$target"
  else
    mode="$(stat -Lc '%a' -- "$target")"
    printf 'directory-mode:%s\t%s\n' "$mode" "$target" >> "$BACKUP_DIR/manifest.tsv"
  fi
}

rollback_backup() {
  local dir="$1"
  local manifest="$dir/manifest.tsv"
  local state target backup_file

  [ -f "$manifest" ] || { log "No existe un manifiesto válido en $dir"; return 1; }
  validate_rollback "$dir" || return 1
  confirm "Esto restaurará los archivos registrados en $dir. ¿Continuar?"

  while IFS=$'\t' read -r state target || [ -n "$state$target" ]; do
    [ -n "$target" ] || continue
    if ! is_allowed_target "$target"; then
      log "Ruta no permitida en el manifiesto: $target"
      return 1
    fi
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
          run sudo cp -aT --remove-destination -- "$backup_file" "$target"
        else
          run mkdir -p "$(dirname "$target")"
          run cp -aT --remove-destination -- "$backup_file" "$target"
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
      directory-mode:*)
        local mode="${state#directory-mode:}"
        if [[ ! "$mode" =~ ^[0-7]{3,4}$ ]] || [ ! -d "$target" ]; then
          log "Modo o directorio inválido en el manifiesto: $target"
          return 1
        fi
        log "Restaurando permisos de $target"
        if is_system_path "$target"; then
          run sudo chmod "$mode" -- "$target"
        else
          run chmod "$mode" -- "$target"
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
  # Validar todo antes de respaldar o copiar: no dejar una restauración parcial.
  while IFS= read -r -d '' source_file; do
    target="$HOME/${source_file#"$source/"}"
    is_allowed_target "$target" && validate_user_parent "$target" || return 1
    if [ -d "$target" ] && [ ! -L "$target" ]; then
      log "El destino es un directorio: $target"
      return 1
    fi
  done < <(find "$source" -path "$source/.cache" -prune -o \( -type f -o -type l \) -print0)
  validate_hardened_targets || return 1
  while IFS= read -r -d '' source_file; do
    rel="${source_file#"$source/"}"
    target="$HOME/$rel"
    backup_target "$target"
  done < <(find "$source" -path "$source/.cache" -prune -o \( -type f -o -type l \) -print0 | sort -z)

  log "Restaurando archivos de usuario"
  run mkdir -p "$HOME"
  # Copiar el árbol con cp -a también impondría los permisos de sus
  # directorios sobre HOME/.config/etc. Solo reemplazamos archivos y enlaces.
  while IFS= read -r -d '' source_file; do
    rel="${source_file#"$source/"}"
    target="$HOME/$rel"
    run mkdir -p "$(dirname "$target")"
    run cp -aT --remove-destination -- "$source_file" "$target"
  done < <(find "$source" -path "$source/.cache" -prune -o \( -type f -o -type l \) -print0 | sort -z)

  if [ "$DRY_RUN" -eq 1 ] && [ -d "$source/.local/bin" ]; then
    log "Ajustando permisos ejecutables en ~/.local/bin"
    while IFS= read -r file; do
      printf '+ chmod +x %q\n' "$HOME/.local/bin/$(basename "$file")"
    done < <(find "$source/.local/bin" -maxdepth 1 -type f | sort)
  elif [ -d "$HOME/.local/bin" ]; then
    log "Ajustando permisos ejecutables en ~/.local/bin"
    while IFS= read -r -d '' source_file; do
      run chmod +x "$HOME/.local/bin/$(basename "$source_file")"
    done < <(find "$source/.local/bin" -maxdepth 1 -type f -print0)
  fi

  if [ -d "$HOME/.ssh" ]; then
    log "Ajustando permisos de ~/.ssh"
    if ! mode_is "$HOME/.ssh" 700; then
      backup_directory_mode "$HOME/.ssh"
      run chmod 700 "$HOME/.ssh"
    fi
    if [ -f "$HOME/.ssh/authorized_keys" ] && ! mode_is "$HOME/.ssh/authorized_keys" 600; then
      backup_target "$HOME/.ssh/authorized_keys"
      run chmod 600 "$HOME/.ssh/authorized_keys"
    fi
  fi

  if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    log "Actualizando carpetas XDG"
    run env LANG=es_AR.UTF-8 LC_ALL=es_AR.UTF-8 xdg-user-dirs-update
  fi

  log "Asegurando papelera XDG"
  run mkdir -p "$HOME/.local/share/Trash/files" "$HOME/.local/share/Trash/info"

  log "Asegurando directorios de MPD/ncmpcpp y Streamrip"
  run mkdir -p "$HOME/.local/share/mpd/playlists" "$HOME/.local/share/ncmpcpp/lyrics" "$HOME/Música/streamrip"

  if [ -f "$HOME/.config/streamrip/config.toml" ] && ! mode_is "$HOME/.config/streamrip/config.toml" 600; then
    log "Ajustando permisos de ~/.config/streamrip/config.toml"
    backup_target "$HOME/.config/streamrip/config.toml"
    run chmod 600 "$HOME/.config/streamrip/config.toml"
  fi

  if [ -d "$source/.config/systemd/user" ] && command -v systemctl >/dev/null 2>&1; then
    log "Recargando units de systemd de usuario"
    run systemctl --user daemon-reload
    if command -v mpd >/dev/null 2>&1; then
      log "Habilitando e iniciando MPD"
      run systemctl --user enable --now mpd.service
    fi
  fi

  if command -v gsettings >/dev/null 2>&1; then
    log "Aplicando preferencias GTK/Wayland (gsettings)"
    run gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark
    run gsettings set org.gnome.desktop.interface icon-theme Qogir-Dark
  fi

  if [ "$PRUNE" -eq 1 ]; then
    prune_user_bin
  fi
}

is_retired_local_bin() {
  local name="$1"

  [ -f "$LOCAL_BIN_RETIRED_FILE" ] || return 1
  grep -Fqx -- "$name" "$LOCAL_BIN_RETIRED_FILE"
}

# Solo borra lo que el proyecto instaló y después retiró. Un archivo que no está
# en el repo ni en la lista de retirados puede ser una herramienta tuya: se
# conserva y se avisa.
prune_user_bin() {
  local file name found=0 unknown=0

  for file in "$HOME"/.local/bin/*; do
    [ -f "$file" ] || [ -L "$file" ] || continue
    name="$(basename "$file")"
    [ -e "$ROOT_DIR/home/.local/bin/$name" ] && continue
    is_kept_local_bin "$name" && continue
    if ! is_retired_local_bin "$name"; then
      log "Se conserva (no lo instaló el proyecto): $file"
      unknown=1
      continue
    fi

    if [ "$found" -eq 0 ]; then
      confirm "Se quitarán de ~/.local/bin los scripts que el proyecto retiró, con backup previo. ¿Continuar?"
    fi
    found=1
    backup_target "$file"
    log "Quitando script retirado del proyecto: $file"
    run rm -f "$file"
  done

  [ "$found" -eq 1 ] || log "No hay scripts retirados del proyecto para quitar"
  if [ "$unknown" -eq 1 ]; then
    log "Si alguno de los que se conservan es tuyo, sumalo a docs/local-bin-keep.txt para no ver el aviso."
  fi
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
  install_system_group polkit
}

install_bootloader_files() {
  local entry
  entry="$ROOT_DIR/$(system_source_for /boot/loader/entries/arch.conf)" || return 1
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
  install_system_group bootloader
}

install_sshd_config() {
  local dir="$ROOT_DIR/sshd"
  local dest="${RESTORE_SSHD_DIR:-/etc/ssh/sshd_config.d}"  # otro valor solo en tests
  local file target name group kind source mode saved=""
  local -a targets=()
  [ -d "$dir" ] || { log "No existe $dir"; return 1; }

  confirm "Esto copiará hardening de sshd y recargará sshd. ¿Continuar?"
  log "Instalando configuración de sshd"
  # Copia propia de lo que había, aparte del backup: tiene que funcionar también
  # con --no-backup. Un archivo inválido que queda instalado no se nota hasta el
  # próximo reinicio de sshd, y ahí se pierde el acceso por SSH.
  [ "$DRY_RUN" -eq 1 ] || saved="$(sudo mktemp -d)"
  while IFS='|' read -r group kind source target mode; do
    file="$ROOT_DIR/$source"
    name="$(basename "$target")"
    [ -z "${RESTORE_SSHD_DIR:-}" ] || target="$dest/$name"
    backup_target "$target"
    if [ -n "$saved" ] && { sudo test -e "$target" || sudo test -L "$target"; }; then
      sudo cp -a -- "$target" "$saved/$name"
    fi
    targets+=("$target")
    run sudo install -Dm"$mode" "$file" "$target"
  done < <(system_files sshd)
  if ! run sudo sshd -t; then
    log "sshd -t rechazó la configuración nueva; vuelvo a los archivos anteriores"
    for target in "${targets[@]}"; do
      name="$(basename "$target")"
      if sudo test -e "$saved/$name" || sudo test -L "$saved/$name"; then
        sudo cp -a --remove-destination -- "$saved/$name" "$target"
      else
        sudo rm -f -- "$target"
      fi
    done
    sudo rm -rf -- "$saved"
    log "No se recargó sshd. Revisá $dir antes de volver a intentar."
    return 1
  fi
  [ -z "$saved" ] || sudo rm -rf -- "$saved"
  run sudo systemctl reload sshd.service
}

install_nftables_config() {
  local file
  file="$ROOT_DIR/$(system_source_for /etc/nftables.conf)" || return 1
  [ -f "$file" ] || { log "No existe $file"; return 1; }

  confirm "Esto instalará nftables.conf, reemplazará reglas activas y habilitará nftables.service. ¿Continuar?"
  log "Validando configuración de nftables"
  run sudo nft -c -f "$file"

  log "Instalando configuración de nftables"
  install_system_group nftables
  run sudo systemctl enable nftables.service
  run sudo systemctl restart nftables.service
}

install_iwd_config() {
  local file regdom_file
  file="$ROOT_DIR/$(system_source_for /etc/iwd/main.conf)" || return 1
  regdom_file="$ROOT_DIR/$(system_source_for /etc/conf.d/wireless-regdom)" || return 1
  [ -f "$file" ] || { log "No existe $file"; return 1; }
  [ -f "$regdom_file" ] || { log "No existe $regdom_file"; return 1; }

  confirm "Esto instalará la configuración de iwd y systemd-resolved. ¿Continuar?"
  log "Instalando configuración de iwd"
  install_system_group iwd

  log "Configurando dominio regulatorio Wi-Fi de Argentina"
  install_system_group regdom
  run sudo /usr/bin/set-wireless-regdom

  log "Configurando resolución DNS con systemd-resolved"
  run sudo systemctl enable --now systemd-resolved.service
  install_system_group resolved

  log "Habilitando el gestor Wi-Fi iwd"
  run sudo systemctl enable --now iwd.service
}

install_sysctl_config() {
  local dir="$ROOT_DIR/sysctl"
  [ -d "$dir" ] || { log "No existe $dir"; return 1; }

  confirm "Esto instalará ajustes locales de sysctl en /etc/sysctl.d/. ¿Continuar?"
  log "Instalando ajustes sysctl locales"
  install_system_group sysctl
  run sudo sysctl --system
}

install_zram_config() {
  local file
  file="$ROOT_DIR/$(system_source_for /etc/systemd/zram-generator.conf)" || return 1
  [ -f "$file" ] || { log "No existe $file"; return 1; }

  confirm "Esto instalará la configuración de zram-generator en /etc/systemd/. ¿Continuar?"
  log "Instalando configuración de zram-generator"
  install_system_group zram
}

# UPower solo arranca si alguien lo pide por D-Bus, y en esta sesión nadie lo
# hace (Waybar lee /sys). Sin el servicio corriendo, su acción con batería
# crítica (/etc/UPower/UPower.conf) nunca se ejecuta.
install_power_management() {
  confirm "Esto habilitará e iniciará upower.service. ¿Continuar?"
  log "Habilitando UPower"
  run sudo systemctl enable --now upower.service
}

install_samba_mount() {
  local dir="$ROOT_DIR/samba"
  local cred=/etc/samba/credenciales-mini
  local clave
  [ -d "$dir" ] || { log "No existe $dir"; return 1; }

  confirm "Esto instalará el montaje de la carpeta compartida de la mini en ~/Compartido. ¿Continuar?"
  log "Instalando montaje de la carpeta compartida (Samba)"
  if ! pacman -Q cifs-utils >/dev/null 2>&1; then
    run sudo pacman -S --needed --noconfirm cifs-utils
  fi
  install_system_group samba

  if [ -e "$cred" ]; then   # /etc/samba es 755: se ve sin sudo
    log "Credenciales de Samba ya presentes en $cred (no se tocan)"
  elif [ "$DRY_RUN" -eq 1 ]; then
    printf '+ pedir contraseña de Samba y crear %q (root 600)\n' "$cred"
  elif [ -t 0 ]; then
    printf 'Contraseña de Samba de la mini (no se ve): '
    IFS= read -rs clave
    printf '\n'
    [ -n "$clave" ] || { log "Contraseña vacía: no se crean credenciales"; return 1; }
    printf 'username=%s\npassword=%s\n' "$USER" "$clave" | sudo install -Dm600 -o root -g root /dev/stdin "$cred"
    unset clave
  else
    log "AVISO: falta $cred y no hay terminal para pedir la contraseña."
    log "Crealo a mano (root 600, líneas username= y password=); el montaje fallará hasta entonces."
  fi

  run mkdir -p "$HOME/Compartido"
  run sudo systemctl daemon-reload
  run sudo systemctl enable --now home-massisalva-Compartido.automount
}

PIECES_REQUESTED=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --packages|--aur|--polkit|--bootloader|--sshd|--nftables|--iwd|--sysctl|--zram|--samba|--power)
      PIECES_REQUESTED=1
      ;;&
    --packages) INSTALL_PACKAGES=1 ;;
    --aur) INSTALL_AUR=1 ;;
    --polkit) INSTALL_POLKIT=1 ;;
    --bootloader) INSTALL_BOOTLOADER=1 ;;
    --sshd) INSTALL_SSHD=1 ;;
    --nftables) INSTALL_NFTABLES=1 ;;
    --iwd) INSTALL_IWD=1 ;;
    --sysctl) INSTALL_SYSCTL=1 ;;
    --zram) INSTALL_ZRAM=1 ;;
    --samba) INSTALL_SAMBA=1 ;;
    --power) INSTALL_POWER=1 ;;
    --user) RESTORE_USER=1 ;;
    --yazi) INSTALL_YAZI=1 ;;
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
      INSTALL_ZRAM=1
      INSTALL_SAMBA=1
      INSTALL_POWER=1
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

# Pedir solo piezas (p. ej. ./restore.sh --power) no restaura $HOME ni Yazi:
# antes lo hacía sin avisar (auditoría 2026-11-20, H6). Sin piezas, o con
# --all, sí. --user/--yazi y --no-user/--no-yazi siempre mandan.
if [ "$PIECES_REQUESTED" -eq 1 ]; then
  RESTORE_USER="${RESTORE_USER:-0}"
  INSTALL_YAZI="${INSTALL_YAZI:-0}"
else
  RESTORE_USER="${RESTORE_USER:-1}"
  INSTALL_YAZI="${INSTALL_YAZI:-1}"
fi

if [ "$PRUNE" -eq 1 ] && [ "$RESTORE_USER" -ne 1 ]; then
  log "--prune es parte de la restauración de usuario; sumá --user o quitá --no-user"
  exit 2
fi

if [ "$PRUNE" -eq 1 ] && [ "$BACKUP_ENABLED" -ne 1 ]; then
  log "--prune requiere backups; quitá --no-backup"
  exit 2
fi

if [ "$EUID" -eq 0 ] && { [ "$RESTORE_USER" -eq 1 ] || [ "$INSTALL_AUR" -eq 1 ] || [ "$INSTALL_YAZI" -eq 1 ]; }; then
  log "No ejecutes restore.sh como root: la restauración de usuario, Yazi y yay deben correr como tu usuario."
  log "Usá ./restore.sh --all -y; el script pedirá sudo solo para los pasos administrativos."
  exit 1
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
[ "$INSTALL_ZRAM" -eq 1 ] && install_zram_config
[ "$INSTALL_SAMBA" -eq 1 ] && install_samba_mount
[ "$INSTALL_POWER" -eq 1 ] && install_power_management

if [ -n "$BACKUP_DIR" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    log "El backup se crearía en: $BACKUP_DIR"
  else
    log "Backup disponible en: $BACKUP_DIR"
  fi
fi
log "Restauración finalizada"
if [ "$BACKUP_ENABLED" -eq 1 ] && [ -n "$BACKUP_DIR" ] && [ "$DRY_RUN" -eq 0 ]; then
  log "Para volver atrás los archivos: ./restore.sh --rollback $BACKUP_DIR"
  log "El rollback no deshace paquetes, servicios habilitados, gsettings ni carpetas creadas."
fi
