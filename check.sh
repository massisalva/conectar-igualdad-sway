#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FAILS=0
WARNS=0
STRICT_SYSTEM=0

usage() {
  cat <<'EOF'
Uso: ./check.sh [opciones]

Por defecto verifica el estado de usuario, paquetes, Yazi, XDG y repo.
Los archivos de sistema en polkit/ y bootloader/ se reportan como advertencia.

Opciones:
  --system    Trata polkit/ y bootloader/ como checks obligatorios.
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
}

check_polkit() {
  local file
  local severity="warn"
  [ "$STRICT_SYSTEM" -eq 1 ] && severity="fail"

  for file in "$ROOT_DIR"/polkit/*.rules; do
    [ -f "$file" ] || continue
    check_same_file "$file" "/etc/polkit-1/rules.d/$(basename "$file")" "$severity"
  done
}

check_bootloader() {
  local severity="warn"
  [ "$STRICT_SYSTEM" -eq 1 ] && severity="fail"

  check_same_file "$ROOT_DIR/bootloader/loader.conf" /boot/loader/loader.conf "$severity"
  check_same_file "$ROOT_DIR/bootloader/arch.conf" /boot/loader/entries/arch.conf "$severity"
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
  for cmd in sway waybar foot fuzzel mako yazi ya fuzzel wl-copy rg fd mpv udisksctl brightnessctl wpctl notify-send; do
    check_cmd "$cmd"
  done
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --system) STRICT_SYSTEM=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Opción desconocida: %s\n\n' "$1"; usage; exit 2 ;;
  esac
  shift
done

check_packages pacman "$ROOT_DIR/docs/pkglist-pacman.txt"
check_packages AUR "$ROOT_DIR/docs/pkglist-aur.txt"
check_core_commands
check_user_files
check_bash_scripts
check_xdg_dirs
check_yazi
check_polkit
check_bootloader
check_repo_state

printf '\nResumen: %d fallos, %d advertencias\n' "$FAILS" "$WARNS"

if [ "$FAILS" -gt 0 ]; then
  exit 1
fi

exit 0
