#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
CALL_FILE="$TEST_ROOT/audio-call"
export CALL_FILE

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

lsblk() {
  printf '%s\n' '{"blockdevices":[{"name":"/dev/sdz","type":"disk","tran":"usb","rm":true,"model":"USB modelo","children":[{"name":"/dev/sdz1","type":"part","fstype":"vfat","label":"Etiqueta \"rara\" | prueba","mountpoint":"/run/media/prueba"}]}]}'
}
export -f lsblk

disk_json="$(bash "$ROOT_DIR/home/.local/bin/disk-status")"
python -c 'import json,sys; data=json.loads(sys.argv[1]); assert data["class"] == "mounted"; assert "Etiqueta" in data["tooltip"]' "$disk_json" || \
  fail "disk-status no escapó correctamente la etiqueta simulada"
ok "disk-status con etiqueta externa adversa"

(
  export DISK_OPEN_PATH="$TEST_ROOT/disk-open-path"
  export DISK_MOUNT_CALL="$TEST_ROOT/disk-mount-call"
  export DISK_FSTAB="$TEST_ROOT/disk-fstab"
  disk_path="$TEST_ROOT/Mi USB\\respaldo"
  python - "$DISK_FSTAB" "$disk_path" <<'PY'
import sys
target = sys.argv[2].replace("\\", r"\134").replace(" ", r"\040")
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write(f"/dev/sdz1 {target} vfat defaults 0 0\n")
PY
  lsblk() {
    printf '%s\n' '{"blockdevices":[{"name":"/dev/sdz","type":"disk","tran":"usb","rm":true,"children":[{"name":"/dev/sdz1","type":"part","fstype":"vfat","label":"Mi USB","pkname":"/dev/sdz"}]}]}'
  }
  findmnt() {
    [ "${MOCK_DISK_MOUNTED:-1}" = 1 ] || return 1
    command findmnt --fstab --tab-file "$DISK_FSTAB" "$@"
  }
  fuzzel() { cat >/dev/null; printf '%s\n' "${DISK_CHOICE:-1) Abrir}"; }
  foot() { printf '%s' "${!#}" > "$DISK_OPEN_PATH"; }
  yazi() { :; }
  notify-send() { :; }
  udisksctl() {
    [ "$*" = 'mount -b /dev/sdz1 --options ro' ] || return 1
    printf '%s\n' "$*" > "$DISK_MOUNT_CALL"
    MOCK_DISK_MOUNTED=1
  }
  export -f lsblk findmnt fuzzel foot yazi notify-send udisksctl
  export WAYLAND_DISPLAY=audit-test SWAYSOCK=/tmp/audit-test-sway.sock
  MOCK_DISK_MOUNTED=1 bash "$ROOT_DIR/home/.local/bin/disk-manager"
  [ "$(cat "$DISK_OPEN_PATH")" = "$disk_path" ] || fail "disk-manager alteró la ruta al abrir un disco montado"
  rm "$DISK_OPEN_PATH"
  MOCK_DISK_MOUNTED=0 DISK_CHOICE='2) Montar solo lectura' bash "$ROOT_DIR/home/.local/bin/disk-manager"
  [ "$(cat "$DISK_OPEN_PATH")" = "$disk_path" ] || fail "disk-manager alteró la ruta al montar solo lectura"
  [ -s "$DISK_MOUNT_CALL" ] || fail "disk-manager no solicitó montaje de solo lectura"
)
ok "disk-manager abre rutas reales con espacios y barras invertidas, también tras montar"

python -c '
import json
import sys

config = json.load(open(sys.argv[1], encoding="utf-8"))
assert config["custom/music"]["escape"] is True
assert config["custom/capslock"]["interval"] == "once"
assert config["custom/capslock"]["signal"] == 8
assert config["custom/disk"]["interval"] == 60
assert "signal" not in config["custom/disk"]
' "$ROOT_DIR/home/.config/waybar/config.jsonc" || \
  fail "la configuración de módulos personalizados de Waybar es inválida"
grep -Fq 'WAYBAR_MUSIC_INTERVAL:-5' "$ROOT_DIR/home/.local/bin/waybar-music" || \
  fail "el watcher musical no usa el intervalo esperado"
ok "módulo musical con markup seguro y polling reducido"

pactl() {
  case "$*" in
    'list short sinks')
      printf '10\tsink.one\n20\tsink.two\n'
      ;;
    'get-default-sink')
      printf 'sink.one\n'
      ;;
    'list sinks')
      printf 'Sink #10\n\tDescription: Dispositivo repetido\nSink #20\n\tDescription: Dispositivo repetido\n'
      ;;
    'set-default-sink sink.two')
      printf '%s\n' "$*" > "$CALL_FILE"
      ;;
    *) return 1 ;;
  esac
}

fuzzel() {
  printf '[20] Dispositivo repetido\n'
}

wpctl() {
  # Un índice de pactl no debe usarse como ID de nodo de PipeWire.
  return 1
}

notify-send() {
  return 0
}

export -f pactl fuzzel wpctl notify-send
bash "$ROOT_DIR/home/.local/bin/audio-output-menu"
grep -Fxq 'set-default-sink sink.two' "$CALL_FILE" || fail "audio-output-menu eligió una salida incorrecta"
ok "audio-output-menu distingue descripciones duplicadas sin mezclar APIs"

WALLPAPER_TEST_HOME="$TEST_ROOT/wallpaper-home"
WALLPAPER_CALL_FILE="$TEST_ROOT/swaymsg-call"
mkdir -p "$WALLPAPER_TEST_HOME/Imágenes" "$WALLPAPER_TEST_HOME/.config/sway/config.d"
printf 'primero' > "$WALLPAPER_TEST_HOME/Imágenes/first.png"
printf 'segundo' > "$WALLPAPER_TEST_HOME/Imágenes/second.png"
printf '%s\n' \
  '# Apariencia' \
  'output * bg ~/Imágenes/wallpaper-1qowj1.png fill' \
  > "$WALLPAPER_TEST_HOME/.config/sway/config.d/20-appearance.conf"

fuzzel() {
  printf '%s\n' "${WALLPAPER_CHOICE:-002  second.png}"
}

swaymsg() {
  printf '%s\n' "$*" > "$WALLPAPER_CALL_FILE"
  [ "${MOCK_SWAY_FAILURE:-0}" = 0 ]
}

export WALLPAPER_CALL_FILE
export -f fuzzel swaymsg
HOME="$WALLPAPER_TEST_HOME" XDG_PICTURES_DIR="$WALLPAPER_TEST_HOME/Imágenes" \
  bash "$ROOT_DIR/home/.local/bin/wallpaper-menu"
grep -Fxq 'output * bg ~/.local/share/sway/wallpaper fill' \
  "$WALLPAPER_TEST_HOME/.config/sway/config.d/25-fondo.conf" || \
  fail "wallpaper-menu no persistió el fondo elegido en 25-fondo.conf"
grep -Fq 'output * bg ~/Imágenes/wallpaper-1qowj1.png fill' \
  "$WALLPAPER_TEST_HOME/.config/sway/config.d/20-appearance.conf" || \
  fail "wallpaper-menu modificó 20-appearance.conf (versionado)"
[ "$(stat -c '%a' "$WALLPAPER_TEST_HOME/.config/sway/config.d/25-fondo.conf")" = 644 ] || \
  fail "wallpaper-menu dejó 25-fondo.conf sin permisos 644"
grep -Fxq 'output * bg ~/.local/share/sway/wallpaper fill' "$WALLPAPER_CALL_FILE" || \
  fail "wallpaper-menu no aplicó el fondo elegido"
[ "$(readlink "$WALLPAPER_TEST_HOME/.local/share/sway/wallpaper")" = "$WALLPAPER_TEST_HOME/Imágenes/second.png" ] || \
  fail "wallpaper-menu no referenció el archivo elegido"
ok "selector de fondos aplica y persiste la selección"

special_pictures="$TEST_ROOT/fondos especiales"
special_name='fondo "doble", con\barra; exec touch marca.png'
mkdir -p "$special_pictures"
printf 'imagen de prueba' > "$special_pictures/$special_name"
HOME="$WALLPAPER_TEST_HOME" XDG_PICTURES_DIR="$special_pictures" WALLPAPER_CHOICE='001  fondo' \
  bash "$ROOT_DIR/home/.local/bin/wallpaper-menu"
[ "$(readlink "$WALLPAPER_TEST_HOME/.local/share/sway/wallpaper")" = "$special_pictures/$special_name" ] || \
  fail "wallpaper-menu alteró el nombre del fondo con caracteres especiales"
grep -Fxq 'output * bg ~/.local/share/sway/wallpaper fill' "$WALLPAPER_CALL_FILE" || \
  fail "wallpaper-menu incluyó el nombre del archivo en el comando IPC"
cp "$WALLPAPER_TEST_HOME/.config/sway/config.d/25-fondo.conf" "$TEST_ROOT/previous-wallpaper.conf"
if HOME="$WALLPAPER_TEST_HOME" XDG_PICTURES_DIR="$WALLPAPER_TEST_HOME/Imágenes" MOCK_SWAY_FAILURE=1 \
  bash "$ROOT_DIR/home/.local/bin/wallpaper-menu"; then
  fail "wallpaper-menu ignoró un fallo de Sway"
fi
cmp -s "$TEST_ROOT/previous-wallpaper.conf" "$WALLPAPER_TEST_HOME/.config/sway/config.d/25-fondo.conf" || \
  fail "wallpaper-menu persistió una selección que Sway rechazó"
[ "$(readlink "$WALLPAPER_TEST_HOME/.local/share/sway/wallpaper")" = "$special_pictures/$special_name" ] || \
  fail "wallpaper-menu no recuperó el fondo anterior tras un fallo de Sway"
ok "fondos con separadores y comillas no entran al comando IPC; un fallo conserva el fondo anterior"

if rg --hidden -q -- 'override=colors\.alpha' "$ROOT_DIR/home/.local/bin"; then
  fail "persisten overrides obsoletos de Foot"
fi
ok "overrides de Foot actualizados"

if rg -q -- 'yazi --debug' "$ROOT_DIR/check.sh"; then
  fail "check.sh depende de yazi --debug, que requiere una TTY"
fi
grep -Eq 'dark.*catppuccin-mocha' "$ROOT_DIR/check.sh" || \
  fail "check.sh no valida el tema de Yazi desde theme.toml"
ok "verificación de Yazi apta para ejecuciones no interactivas"

grep -Fq 'enabled_output="$(systemctl is-enabled nftables.service 2>&1 || true)"' "$ROOT_DIR/check.sh" || \
  fail "check.sh no conserva la salida de systemctl para nftables"
grep -Fq "Operation not permitted|Failed to connect to system scope bus" "$ROOT_DIR/check.sh" || \
  fail "check.sh no distingue restricciones del entorno al verificar nftables"
ok "verificación de nftables tolera restricciones del entorno"

if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop_out="$(desktop-file-validate "$ROOT_DIR"/home/.local/share/applications/*.desktop 2>&1)" || \
    fail "desktop-file-validate rechazó archivos .desktop: $desktop_out"
  [ -z "$desktop_out" ] || fail "desktop-file-validate emitió advertencias: $desktop_out"
  ok "archivos .desktop válidos y sin advertencias"
fi

grep -Fq 'MESA_GLSL_CACHE_DISABLE=true' "$ROOT_DIR/check.sh" || \
  fail "check.sh no deshabilita la caché de shaders de Mesa al validar Sway"
grep -Fq 'WLR_BACKENDS=headless' "$ROOT_DIR/check.sh" || \
  fail "check.sh no reintenta validar Sway con backend virtual (SSH sin seat)"
grep -Fq -- '-path "$source/.cache" -prune' "$ROOT_DIR/restore.sh" || \
  fail "restore.sh no excluye home/.cache durante la restauración"
ok "protección contra contaminación de home/.cache"

RIP_CALL_FILE="$TEST_ROOT/rip-calls"
MPC_CALL_FILE="$TEST_ROOT/mpc-calls"
rip() {
  printf '%s\n' "$*" >> "$RIP_CALL_FILE"
}
mpc() {
  printf '%s\n' "$*" >> "$MPC_CALL_FILE"
}
# Simula las redirecciones de los enlaces cortos de Deezer.
curl() {
  case "${!#}" in
    https://link.deezer.com/s/okLINK) printf '%s' 'https://www.deezer.com/es/album/789?host=1&utm_source=x' ;;
    *) printf '%s' 'https://www.deezer.com/deezer-links-404' ;;
  esac
}
export RIP_CALL_FILE MPC_CALL_FILE
export -f rip mpc curl

printf '%s\n' \
  '1' \
  'https://example.com/album/123' \
  '' \
  '1' \
  '  https://www.deezer.com/album/456  ' \
  '' \
  '1' \
  'https://deezer.page.link/abc123XYZ' \
  '' \
  '1' \
  'https://link.deezer.com/s/okLINK' \
  '' \
  '1' \
  'https://link.deezer.com/s/roto' \
  '' \
  '8' \
  '2' \
  ' Gustavo Cerati ' \
  '' \
  '0' | bash "$ROOT_DIR/home/.local/bin/streamrip-menu" >/dev/null

! grep -Fq 'example.com' "$RIP_CALL_FILE" || \
  fail "streamrip-menu permitió un enlace ajeno a Deezer"
grep -Fxq 'url https://www.deezer.com/album/456' "$RIP_CALL_FILE" || \
  fail "streamrip-menu no recortó espacios ni descargó enlace de deezer.com"
grep -Fxq 'url https://deezer.page.link/abc123XYZ' "$RIP_CALL_FILE" || \
  fail "streamrip-menu no aceptó enlace corto deezer.page.link"
grep -Fxq 'url https://www.deezer.com/es/album/789' "$RIP_CALL_FILE" || \
  fail "streamrip-menu no resolvió el enlace corto link.deezer.com"
! grep -Fq 'link.deezer.com' "$RIP_CALL_FILE" && ! grep -Fq 'links-404' "$RIP_CALL_FILE" || \
  fail "streamrip-menu pasó a rip un enlace corto sin resolver o roto"
grep -Fxq -- '--no-db search deezer track -- Gustavo Cerati' "$RIP_CALL_FILE" || \
  fail "streamrip-menu no pasó --no-db al activar la opción 8"
[ "$(grep -Fxc 'update --wait' "$MPC_CALL_FILE")" -eq 4 ] || \
  fail "streamrip-menu no actualizó MPD tras cada operación de descarga"
ok "streamrip-menu valida y resuelve enlaces, recorta espacios, soporta --no-db y actualiza MPD"

(
  export MUSIC_UPDATE_CALLS="$TEST_ROOT/music-update-calls"
  export MUSIC_UPDATE_NOTIFICATIONS="$TEST_ROOT/music-update-notifications"
  mpc() {
    printf '%s\n' "$*" >> "$MUSIC_UPDATE_CALLS"
    case "$*" in
      status) return 0 ;;
      'update --wait') return "${MOCK_UPDATE_RESULT:-0}" ;;
      *) return 1 ;;
    esac
  }
  notify-send() { printf '%s\n' "$*" >> "$MUSIC_UPDATE_NOTIFICATIONS"; }
  export -f mpc notify-send
  bash "$ROOT_DIR/home/.local/bin/music-update"
  grep -Fxq 'update --wait' "$MUSIC_UPDATE_CALLS" || fail "music-update no esperó la actualización en la misma operación"
  [ "$(wc -l < "$MUSIC_UPDATE_CALLS")" -eq 2 ] || fail "music-update inició otra espera después de la actualización"
  grep -Fq 'Biblioteca actualizada' "$MUSIC_UPDATE_NOTIFICATIONS" || fail "music-update no notificó el éxito"
  : > "$MUSIC_UPDATE_NOTIFICATIONS"
  if MOCK_UPDATE_RESULT=1 bash "$ROOT_DIR/home/.local/bin/music-update"; then
    fail "music-update informó éxito ante una actualización fallida"
  fi
  ! grep -Fq 'Biblioteca actualizada' "$MUSIC_UPDATE_NOTIFICATIONS" || fail "music-update notificó éxito ante un fallo"
  grep -Fq 'No pude actualizar' "$MUSIC_UPDATE_NOTIFICATIONS" || fail "music-update no notificó el fallo"
)
ok "music-update espera sin carrera y propaga los errores de MPD"

MUSIC_TEST_HOME="$TEST_ROOT/music-home"
mkdir -p "$MUSIC_TEST_HOME/.config/pyradio/playlists"
printf 'Radio Nacional,https://radio.example/vivo?token=1\n' \
  > "$MUSIC_TEST_HOME/.config/pyradio/playlists/argentina.csv"

(
  export HOME="$MUSIC_TEST_HOME"
  ps() {
    if [ "${MOCK_RADIO:-0}" = "1" ]; then
      printf '/usr/bin/mpv --profile=pyradio https://radio.example/vivo?utm=2\n'
    fi
  }
  mpc() {
    case "${MOCK_MPD:-stopped}" in
      playing) printf 'Spinetta - Bajan\n[playing] #1/5   0:42/3:25 (20%%)\nvolume: 100%%\n' ;;
      paused)  printf 'Charly - Nos siguen pegando abajo\n[paused]  #2/5   1:10/3:15 (35%%)\nvolume: 100%%\n' ;;
      *)       printf 'volume: 100%%   repeat: off   random: off\n' ;;
    esac
  }
  playerctl() {
    case "$*" in
      -l)
        [ -n "${MOCK_MPRIS:-}" ] && printf '%s\n' "$MOCK_MPRIS"
        ;;
      "-p ncspot status")
        printf 'Playing\n'
        ;;
      "-p ncspot metadata artist")
        printf 'Soda Stereo\n'
        ;;
      "-p ncspot metadata title")
        printf 'Zoom\n'
        ;;
    esac
  }
  export -f ps mpc playerctl

  out_radio="$(MOCK_RADIO=1 bash "$ROOT_DIR/home/.local/bin/waybar-music")"
  [ "$out_radio" = "󰠃  Radio Nacional" ] || fail "waybar-music no detectó radio activa ($out_radio)"

  out_mpd="$(MOCK_MPD=playing bash "$ROOT_DIR/home/.local/bin/waybar-music")"
  [ "$out_mpd" = "󰎈  Spinetta - Bajan" ] || fail "waybar-music no detectó MPD reproduciendo ($out_mpd)"

  out_mpris="$(MOCK_MPRIS=ncspot bash "$ROOT_DIR/home/.local/bin/waybar-music")"
  [ "$out_mpris" = "󰓇  Soda Stereo - Zoom" ] || fail "waybar-music no detectó reproductor MPRIS ($out_mpris)"

  out_paused="$(MOCK_MPD=paused bash "$ROOT_DIR/home/.local/bin/waybar-music")"
  [ "$out_paused" = "󰏤  Charly - Nos siguen pegando abajo" ] || fail "waybar-music no detectó MPD en pausa ($out_paused)"
)
ok "waybar-music detecta radio, MPD (playing/paused) y MPRIS"

(
  FOOT_CALLS="$TEST_ROOT/foot-calls"
  FLOAT_BIN="$TEST_ROOT/float-bin"
  mkdir -p "$FLOAT_BIN"
  cat > "$FLOAT_BIN/foot" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$1" "$2" >> "$FOOT_CALLS"
EOF
  for tool in pulsemixer bluetui impala; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$FLOAT_BIN/$tool"
  done
  chmod +x "$FLOAT_BIN"/*

  # Aplicar la expresión real a las líneas generadas por foot: un patrón
  # incorrecto debe fallar aunque la rama de cierre esté implementada.
  pkill() {
    [ "$#" -eq 4 ] && [ "$1" = "-u" ] &&
      [ "$2" = "$(id -u)" ] && [ "$3" = "-f" ] || return 2
    local line matched=1
    while IFS= read -r line; do
      if [[ "$line" =~ $4 ]]; then
        printf '%s\n' "$line" >> "$FLOAT_MATCHES"
        matched=0
      fi
    done < "$FLOAT_PROCESSES"
    return "$matched"
  }
  export PATH="$FLOAT_BIN:$PATH"
  export FOOT_CALLS
  export -f pkill

  export FLOAT_PROCESSES="$TEST_ROOT/float-processes"
  export FLOAT_MATCHES="$TEST_ROOT/float-matches"
  : > "$FLOAT_PROCESSES"

  # Primer clic: registrar el comando real con el que cada menú abre foot.
  for script in audio-menu bluetooth-menu network-menu battery-menu; do
    bash "$ROOT_DIR/home/.local/bin/$script"
  done
  [ "$(wc -l < "$FOOT_CALLS")" -eq 4 ] || fail "los menús flotantes no abrieron foot cuando estaban cerrados"
  sed 's/^/foot /; s/$/ --title Test/' "$FOOT_CALLS" > "$FLOAT_PROCESSES"
  cp "$FLOAT_PROCESSES" "$TEST_ROOT/expected-float-matches"

  # Segundo clic: cada menú debe seleccionar únicamente su propia ventana.
  while IFS= read -r script && IFS= read -r expected <&3; do
    : > "$FLOAT_MATCHES"
    bash "$ROOT_DIR/home/.local/bin/$script"
    [ "$(cat "$FLOAT_MATCHES")" = "$expected" ] ||
      fail "$script no seleccionó únicamente su ventana"
  done < <(printf '%s\n' audio-menu bluetooth-menu network-menu battery-menu) \
    3< "$TEST_ROOT/expected-float-matches"
  [ "$(wc -l < "$FOOT_CALLS")" -eq 4 ] || fail "los menús flotantes duplicaron ventanas abiertas"

  # No cerrar otra app ni una ventana cuyo app_id solo comparta el prefijo.
  sed 's/-floating /-floating-extra /' "$TEST_ROOT/expected-float-matches" > "$FLOAT_PROCESSES"
  printf '%s\n' 'foot --app-id foot-term --title Terminal' \
    'bash -c foot --app-id audio-floating --title Audio' >> "$FLOAT_PROCESSES"
  : > "$FLOAT_MATCHES"
  for script in audio-menu bluetooth-menu network-menu battery-menu; do
    bash "$ROOT_DIR/home/.local/bin/$script"
  done
  [ ! -s "$FLOAT_MATCHES" ] || fail "los menús flotantes seleccionaron procesos ajenos"
  [ "$(wc -l < "$FOOT_CALLS")" -eq 8 ] || fail "los menús flotantes no abrieron ante procesos ajenos"
)
ok "menús flotantes (audio, bluetooth, red, batería) alternan apertura y cierre"

printf 'Pruebas de scripts UI: OK\n'
