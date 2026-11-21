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

(
  lsblk() {
    printf '%s\n' '{"blockdevices":[{"name":"/dev/sdz","type":"disk","tran":"usb","rm":true,"fstype":"vfat","label":"USB sin particiones","mountpoint":"/media/direct"}]}'
  }
  findmnt() { printf '%s\n' '{"filesystems":[{"target":"/media/direct"}]}'; }
  export -f lsblk findmnt
  disk_json="$(bash "$ROOT_DIR/home/.local/bin/disk-status")"
  python -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["class"] == "mounted"; assert "/media/direct" in d["tooltip"]' "$disk_json" ||
    fail "disk-status omitió un USB sin particiones"
  menu="$(DISK_MANAGER_DRY_RUN=1 bash "$ROOT_DIR/home/.local/bin/disk-manager")"
  grep -Fq 'Abrir en yazi | USB sin particiones' <<< "$menu" ||
    fail "disk-manager omitió un USB sin particiones"
)
ok "disk-status y disk-manager admiten discos USB sin particiones"

# H4 (2026-11-20): un pendrive cifrado desbloqueado se monta en su nodo crypt
# (/dev/mapper/...); disk-status tiene que verlo montado, como disk-manager.
disk_class() {  # JSON de lsblk -> class y tooltip de disk-status
  (
    export LSBLK_JSON="$1"
    lsblk() { printf '%s\n' "$LSBLK_JSON"; }
    export -f lsblk
    bash "$ROOT_DIR/home/.local/bin/disk-status"
  )
}
luks='{"blockdevices":[{"name":"/dev/sdy","type":"disk","tran":"usb","rm":true,"model":"USB cifrado","children":[{"name":"/dev/sdy1","type":"part","fstype":"crypto_LUKS","label":null,"mountpoint":null,"tran":null,"rm":true,"children":[{"name":"/dev/mapper/luks-prueba","type":"crypt","fstype":"ext4","label":"Seguro","mountpoint":"/run/media/prueba/Seguro","tran":null,"rm":false}]}]}]}'
disk_json="$(disk_class "$luks")"
python -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["class"] == "mounted", d; assert "/run/media/prueba/Seguro" in d["tooltip"], d' "$disk_json" ||
  fail "disk-status no ve montado un disco cifrado desbloqueado"
luks_locked="${luks//\"mountpoint\":\"\/run\/media\/prueba\/Seguro\"/\"mountpoint\":null}"
disk_json="$(disk_class "$luks_locked")"
python -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["class"] == "connected", d' "$disk_json" ||
  fail "disk-status no distingue un disco cifrado desbloqueado sin montar"
internal='{"blockdevices":[{"name":"/dev/sda","type":"disk","tran":"sata","rm":false,"children":[{"name":"/dev/sda1","type":"part","fstype":"vfat","mountpoint":"/boot"},{"name":"/dev/sda2","type":"part","fstype":"crypto_LUKS","children":[{"name":"/dev/mapper/root","type":"crypt","fstype":"ext4","mountpoint":"/"}]}]}]}'
disk_json="$(disk_class "$internal")"
python -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["class"] == "idle", d' "$disk_json" ||
  fail "disk-status tomó como externo un disco interno cifrado"
usb_system='{"blockdevices":[{"name":"/dev/sdx","type":"disk","tran":"usb","rm":true,"children":[{"name":"/dev/sdx1","type":"part","fstype":"vfat","mountpoint":"/boot"},{"name":"/dev/sdx2","type":"part","fstype":"ext4","mountpoint":"/"},{"name":"/dev/sdx3","type":"part","fstype":"swap","mountpoint":"[SWAP]"}]}]}'
disk_json="$(disk_class "$usb_system")"
python -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["class"] != "mounted", d' "$disk_json" ||
  fail "disk-status mostró como montado un disco del sistema"
ok "disk-status ve los discos cifrados montados e ignora los montajes del sistema"

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

# B1 (2026-11-20): Esc en el menú no es un error, y la lista de salidas se
# pide una sola vez.
(
  export PACTL_LIST_COUNT="$TEST_ROOT/pactl-list-count"
  : > "$PACTL_LIST_COUNT"
  eval "real_$(declare -f pactl)"
  pactl() { [ "$*" != 'list sinks' ] || printf 'x\n' >> "$PACTL_LIST_COUNT"; real_pactl "$@"; }
  export -f pactl real_pactl
  bash "$ROOT_DIR/home/.local/bin/audio-output-menu"
  [ "$(wc -l < "$PACTL_LIST_COUNT")" -eq 1 ] || fail "audio-output-menu pidió la lista de salidas más de una vez"
  fuzzel() { cat >/dev/null; return 1; }
  export -f fuzzel
  bash "$ROOT_DIR/home/.local/bin/audio-output-menu" || fail "audio-output-menu da error al cancelar con Esc"
)
ok "audio-output-menu: Esc no es error y consulta las salidas una vez"

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

# H5 (2026-11-20): la barra muestra el mismo reproductor que controlan el
# click y las teclas multimedia, y mpv suelto no cuenta.
(
  export HOME="$MUSIC_TEST_HOME" MUSIC_CALLS="$TEST_ROOT/music-calls"
  ps() { :; }
  mpc() {
    case "$*" in
      status|'')
        case "${MOCK_MPD:-stopped}" in
          playing) printf 'Spinetta - Bajan\n[playing] #1/5   0:42/3:25 (20%%)\nvolume: 100%%\n' ;;
          paused)  printf 'Charly - Nos siguen pegando abajo\n[paused]  #2/5   1:10/3:15 (35%%)\nvolume: 100%%\n' ;;
          *)       printf 'volume: 100%%   repeat: off   random: off\n' ;;
        esac
        ;;
      *) printf 'mpc %s\n' "$*" >> "$MUSIC_CALLS" ;;
    esac
  }
  playerctl() {
    case "$*" in
      -l) printf '%s\n' $MOCK_MPRIS ;;
      "-p "*" status") printf '%s\n' "$MOCK_PLAYER_STATUS" ;;
      "-p "*" metadata artist") printf 'Artista\n' ;;
      "-p "*" metadata title") printf 'Tema de %s\n' "$2" ;;
      "-p "*) printf 'playerctl %s %s\n' "$2" "$3" >> "$MUSIC_CALLS" ;;
    esac
  }
  export -f ps mpc playerctl
  music() {  # estado MPD, reproductores, estado de los reproductores
    : > "$MUSIC_CALLS"
    shown="$(MOCK_MPD="$1" MOCK_MPRIS="$2" MOCK_PLAYER_STATUS="$3" bash "$ROOT_DIR/home/.local/bin/waybar-music")"
    MOCK_MPD="$1" MOCK_MPRIS="$2" MOCK_PLAYER_STATUS="$3" bash "$ROOT_DIR/home/.local/bin/waybar-music" --toggle
    controlled="$(cat "$MUSIC_CALLS")"
  }

  music paused ncspot Paused
  [ "$shown" = "󰏤  Charly - Nos siguen pegando abajo" ] ||
    fail "con MPD y ncspot en pausa, la barra no muestra MPD ($shown)"
  [ "$controlled" = "mpc toggle" ] ||
    fail "con MPD y ncspot en pausa, las teclas no controlan MPD ($controlled)"

  music paused firefox.i1 Playing
  [ "$shown" = "󰓇  Artista - Tema de firefox.i1" ] ||
    fail "Firefox sonando no le gana a MPD en pausa en la barra ($shown)"
  [ "$controlled" = "playerctl firefox.i1 play-pause" ] ||
    fail "Firefox sonando no le gana a MPD en pausa en las teclas ($controlled)"

  music stopped ncspot Paused
  [ "$shown" = "󰏤  Artista - Tema de ncspot" ] || fail "no muestra ncspot en pausa ($shown)"
  [ "$controlled" = "playerctl ncspot play-pause" ] || fail "no controla ncspot en pausa ($controlled)"

  music stopped mpv Playing
  [ -z "$shown" ] || fail "la barra muestra mpv suelto ($shown)"
  [ "$controlled" = "mpc toggle" ] || fail "las teclas controlan mpv suelto ($controlled)"
)
ok "waybar-music muestra y controla el mismo reproductor, e ignora mpv suelto"

# H5 (2026-11-20): si el árbol de Sway no alcanza, se enfoca por PID la
# terminal que contiene al reproductor, no el padre de esa terminal.
(
  # shellcheck source=/dev/null
  source <(sed -n '/^pid_for_child_process() {$/,/^}$/p' "$ROOT_DIR/home/.local/bin/waybar-music")
  ps() {
    printf '%s\n' \
      '    1     0 /sbin/init' \
      '  500     1 sway' \
      '  600   500 foot --app-id foot-music-ncmpcpp -e ncmpcpp' \
      '  601   600 ncmpcpp' \
      '  700   500 foot --app-id foot-music-pyradio -e pyradio' \
      '  701   700 pyradio' \
      '  702   701 mpv --no-video http://radio'
  }
  [ "$(pid_for_child_process ncmpcpp)" = 600 ] ||
    fail "waybar-music enfoca el padre de la terminal y no la terminal (ncmpcpp)"
  [ "$(pid_for_child_process 'mpv --no-video')" = 700 ] ||
    fail "waybar-music no sube por varios niveles hasta la terminal (mpv de pyradio)"
  ! pid_for_child_process no-existe >/dev/null ||
    fail "waybar-music inventó una terminal para un proceso que no existe"
)
ok "waybar-music enfoca la terminal que contiene al reproductor"

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

# M2: expulsar un disco con varias particiones montadas desmonta todas.
(
  export MOUNTED_FILE="$TEST_ROOT/mounted" UDISKS_LOG="$TEST_ROOT/udisks.log" NOTIFY_LOG="$TEST_ROOT/notify.log"
  lsblk() {
    case "$*" in
      *-J*) printf '%s\n' '{"blockdevices":[{"name":"/dev/sdy","type":"disk","tran":"usb","rm":true,"children":[{"name":"/dev/sdy1","type":"part","fstype":"vfat","label":"Uno","pkname":"/dev/sdy"},{"name":"/dev/sdy2","type":"part","fstype":"ext4","label":"Dos","pkname":"/dev/sdy"}]}]}' ;;
      *-nrpo*) printf '/dev/sdy\n/dev/sdy1\n/dev/sdy2\n' ;;
    esac
  }
  findmnt() {
    local dev="${*: -1}"
    case "$*" in *--json*) dev="$3" ;; esac
    grep -qx -- "$dev" "$MOUNTED_FILE" || return 1
    case "$*" in
      *--json*) printf '{"filesystems":[{"target":"/run/media/%s"}]}\n' "${dev##*/}" ;;
      *) printf '%s\n' "/run/media/${dev##*/}" ;;
    esac
  }
  udisksctl() {
    printf '%s\n' "$*" >> "$UDISKS_LOG"
    case "$1" in
      unmount)
        [ "$3" != "${BUSY_DEV:-}" ] || { printf 'target is busy\n' >&2; return 1; }
        grep -vx -- "$3" "$MOUNTED_FILE" > "$MOUNTED_FILE.new" || true
        mv "$MOUNTED_FILE.new" "$MOUNTED_FILE" ;;
      power-off)
        # Como udisks: no apaga un disco con particiones montadas.
        [ ! -s "$MOUNTED_FILE" ] || { printf 'Device is in use\n' >&2; return 1; } ;;
    esac
  }
  fuzzel() { cat >/dev/null; printf '%s\n' "$DISK_CHOICE"; }
  notify-send() { printf '%s\n' "$*" >> "$NOTIFY_LOG"; }
  export -f lsblk findmnt udisksctl fuzzel notify-send
  export WAYLAND_DISPLAY=audit-test SWAYSOCK=/tmp/audit-test-sway.sock

  printf '/dev/sdy1\n/dev/sdy2\n' > "$MOUNTED_FILE"; : > "$UDISKS_LOG"; : > "$NOTIFY_LOG"
  DISK_CHOICE='3) Expulsar' bash "$ROOT_DIR/home/.local/bin/disk-manager" ||
    fail "disk-manager no pudo expulsar un disco con dos particiones montadas"
  grep -qx 'unmount -b /dev/sdy2' "$UDISKS_LOG" || fail "expulsar no desmontó la otra partición"
  grep -qx 'power-off -b /dev/sdy' "$UDISKS_LOG" || fail "expulsar no apagó el disco"
  grep -q 'Disco expulsado' "$NOTIFY_LOG" || fail "expulsar no avisó el éxito"

  printf '/dev/sdy1\n/dev/sdy2\n' > "$MOUNTED_FILE"; : > "$UDISKS_LOG"; : > "$NOTIFY_LOG"
  if BUSY_DEV=/dev/sdy2 DISK_CHOICE='3) Expulsar' bash "$ROOT_DIR/home/.local/bin/disk-manager"; then
    fail "disk-manager informó éxito con una partición ocupada"
  fi
  ! grep -q '^power-off' "$UDISKS_LOG" || fail "intentó apagar el disco con una partición ocupada"
  grep -q '/dev/sdy2.*target is busy' "$NOTIFY_LOG" || fail "no dijo qué partición impidió expulsar ni por qué"
)
ok "expulsar desmonta todas las particiones y dice cuál lo impide"

# B1: un pendrive cifrado se desbloquea (no "Montar") y se bloquea antes de expulsar.
(
  export LUKS_STATE="$TEST_ROOT/luks-state" MOUNTED_FILE="$TEST_ROOT/luks-mounted" UDISKS_LOG="$TEST_ROOT/luks-udisks.log"
  export NOTIFY_LOG="$TEST_ROOT/luks-notify.log"
  lsblk() {
    local child=''
    if [ "$(cat "$LUKS_STATE")" = open ]; then
      child=',"children":[{"name":"/dev/mapper/luks-1","type":"crypt","fstype":"ext4","label":"Datos"}]'
    fi
    case "$*" in
      *-J*) printf '{"blockdevices":[{"name":"/dev/sdx","type":"disk","tran":"usb","rm":true,"children":[{"name":"/dev/sdx1","type":"part","fstype":"crypto_LUKS","label":"Cifrado","pkname":"/dev/sdx"%s}]}]}\n' "$child" ;;
      *NAME,TYPE*) [ "$(cat "$LUKS_STATE")" = open ] && printf '/dev/sdx1 part\n/dev/mapper/luks-1 crypt\n' || printf '/dev/sdx1 part\n' ;;
      *NAME,FSTYPE*/dev/sdx)
        printf '/dev/sdx \n/dev/sdx1 crypto_LUKS\n'
        [ "$(cat "$LUKS_STATE")" = closed ] || printf '/dev/mapper/luks-1 ext4\n' ;;
      *-nrpo\ NAME\ /dev/sdx1)
        printf '/dev/sdx1\n'; [ "$(cat "$LUKS_STATE")" = closed ] || printf '/dev/mapper/luks-1\n' ;;
      *-nrpo\ NAME\ /dev/sdx)
        printf '/dev/sdx\n/dev/sdx1\n'; [ "$(cat "$LUKS_STATE")" = closed ] || printf '/dev/mapper/luks-1\n' ;;
    esac
  }
  findmnt() {
    local dev="${*: -1}"
    case "$*" in *--json*) dev="$3" ;; esac
    grep -qx -- "$dev" "$MOUNTED_FILE" || return 1
    case "$*" in *--json*) printf '{"filesystems":[{"target":"/run/media/datos"}]}\n' ;; *) printf '/run/media/datos\n' ;; esac
  }
  udisksctl() {
    printf '%s\n' "$*" >> "$UDISKS_LOG"
    case "$1" in
      mount) printf '%s\n' "$3" >> "$MOUNTED_FILE" ;;
      unmount) grep -vx -- "$3" "$MOUNTED_FILE" > "$MOUNTED_FILE.new" || true; mv "$MOUNTED_FILE.new" "$MOUNTED_FILE" ;;
      lock) [ ! -s "$MOUNTED_FILE" ] || return 1; printf 'closed\n' > "$LUKS_STATE" ;;
      power-off) [ "$(cat "$LUKS_STATE")" = closed ] || { printf 'Device is in use\n' >&2; return 1; } ;;
    esac
  }
  # La terminal de desbloqueo: simula que el usuario escribió bien la frase.
  foot() {
    case "$*" in *"udisksctl unlock -b /dev/sdx1"*) printf 'open\n' > "$LUKS_STATE" ;; esac
  }
  yazi() { :; }
  fuzzel() { cat >/dev/null; printf '%s\n' "$DISK_CHOICE"; }
  notify-send() { printf '%s\n' "$*" >> "$NOTIFY_LOG"; }
  export -f lsblk findmnt udisksctl foot yazi fuzzel notify-send
  export WAYLAND_DISPLAY=audit-test SWAYSOCK=/tmp/audit-test-sway.sock

  printf 'closed\n' > "$LUKS_STATE"; : > "$MOUNTED_FILE"; : > "$UDISKS_LOG"; : > "$NOTIFY_LOG"
  menu="$(DISK_MANAGER_DRY_RUN=1 bash "$ROOT_DIR/home/.local/bin/disk-manager")"
  grep -Fq 'Desbloquear y montar | Cifrado' <<< "$menu" || fail "un disco cifrado no ofrece desbloquear"
  ! grep -Fq 'Montar | Cifrado' <<< "$menu" || fail "un disco cifrado ofrece Montar, que siempre falla"

  DISK_CHOICE='1) Desbloquear' bash "$ROOT_DIR/home/.local/bin/disk-manager" || fail "no pudo desbloquear y montar"
  grep -qx 'mount -b /dev/mapper/luks-1' "$UDISKS_LOG" || fail "no montó el contenido desbloqueado"

  menu="$(DISK_MANAGER_DRY_RUN=1 bash "$ROOT_DIR/home/.local/bin/disk-manager")"
  grep -Fq 'Bloquear | Cifrado' <<< "$menu" || fail "un disco desbloqueado no ofrece bloquear"
  grep -Fq 'Abrir en yazi | Datos' <<< "$menu" || fail "el contenido desbloqueado no aparece montado"

  : > "$UDISKS_LOG"
  DISK_CHOICE='2) Expulsar' bash "$ROOT_DIR/home/.local/bin/disk-manager" || fail "no pudo expulsar un disco cifrado abierto"
  [ "$(cat "$UDISKS_LOG")" = "$(printf 'unmount -b /dev/mapper/luks-1\nlock -b /dev/sdx1\npower-off -b /dev/sdx')" ] ||
    fail "expulsar no desmontó, bloqueó y apagó en ese orden: $(tr '\n' ';' < "$UDISKS_LOG")"
)
ok "discos cifrados: desbloquear y montar, bloquear, y expulsar bloqueando antes"

# B2: si grim falla, la captura avisa en vez de cerrarse en silencio.
(
  export NOTIFY_LOG="$TEST_ROOT/shot-notify.log"
  grim() { return 1; }
  wl-copy() { cat >/dev/null; }
  notify-send() { printf '%s\n' "$*" >> "$NOTIFY_LOG"; }
  export -f grim wl-copy notify-send
  export WAYLAND_DISPLAY=audit-test SWAYSOCK=/tmp/audit-test-sway.sock HOME="$TEST_ROOT/shot-home"
  for mode in full full-copy; do
    : > "$NOTIFY_LOG"
    if bash "$ROOT_DIR/home/.local/bin/screenshot-menu" "$mode"; then
      fail "la captura $mode informó éxito con grim fallando"
    fi
    grep -q 'No pude capturar' "$NOTIFY_LOG" || fail "la captura $mode falló sin avisar"
    ! grep -q 'Guardada\|Copiada' "$NOTIFY_LOG" || fail "la captura $mode avisó éxito después de fallar"
  done
)
ok "capturas: si grim falla, avisan"

# B1 (2026-11-20): cancelar el menú de capturas con Esc no es un error.
(
  fuzzel() { cat >/dev/null; return 1; }
  grim() { fail "capturó aunque se canceló el menú"; }
  notify-send() { :; }
  export -f fuzzel grim notify-send fail
  export WAYLAND_DISPLAY=audit-test SWAYSOCK=/tmp/audit-test-sway.sock HOME="$TEST_ROOT/shot-home"
  bash "$ROOT_DIR/home/.local/bin/screenshot-menu" || fail "screenshot-menu da error al cancelar con Esc"
)
ok "capturas: Esc no es error"

# B3 (2026-11-20): No molestar le avisa a Waybar con una señal. Discos no:
# se probó y se sacó en 7e4b566 (2026-09-21), ver el assert de custom/disk.
(
  export PKILL_LOG="$TEST_ROOT/pkill.log"
  : > "$PKILL_LOG"
  pkill() { printf '%s\n' "$*" >> "$PKILL_LOG"; }
  makoctl() { [ "${1:-} ${2:-}" != 'mode -a' ] || return 0; [ "${1:-}" != mode ] || printf 'default\n'; }
  notify-send() { :; }
  export -f pkill makoctl notify-send
  bash "$ROOT_DIR/home/.local/bin/notification-mode" --toggle
  grep -Fxq -- '-RTMIN+9 -x waybar' "$PKILL_LOG" || fail "notification-mode no le avisa a Waybar"
)
WAYBAR_CONFIG="$ROOT_DIR/home/.config/waybar/config.jsonc"
grep -A8 '"custom/dnd": {' "$WAYBAR_CONFIG" | grep -q '"signal": 9,' || fail "Waybar no escucha la señal de No molestar"
[ "$(grep -o '"signal": [0-9]*' "$WAYBAR_CONFIG" | sort | uniq -d)" = "" ] || fail "Waybar: dos módulos con la misma señal"
ok "Waybar muestra No molestar al instante"

# H7 (2026-11-20): en Yazi, una tecla asignada sola se ejecuta al instante, así
# que un atajo de varias teclas que empiece con ella nunca se alcanza (pasó con
# "l s" y "l m"; las vistas de tamaño y fecha son "m s" y "m m" de fábrica).
python -c '
import sys, tomllib
keymap = tomllib.load(open(sys.argv[1], "rb"))
for layer, sections in keymap.items():
    binds = sections.get("prepend_keymap", [])
    keys = [[b["on"]] if isinstance(b["on"], str) else b["on"] for b in binds]
    singles = {k[0] for k in keys if len(k) == 1}
    bad = [k for k in keys if len(k) > 1 and k[0] in singles]
    if bad:
        sys.exit(f"{layer}: {bad} empiezan con una tecla asignada sola")
' "$ROOT_DIR/home/.config/yazi/keymap.toml" || fail "Yazi: hay atajos de varias teclas inalcanzables"
ok "Yazi: ningún atajo de varias teclas queda tapado por uno de una tecla"

# H2 (2026-11-20): "No molestar" no oculta lo urgente (batería al 5 %).
MAKO="$ROOT_DIR/home/.config/mako/config"
dnd_line="$(grep -nx '\[mode=do-not-disturb\]' "$MAKO" | cut -d: -f1 || true)"
urgent_line="$(grep -nx '\[mode=do-not-disturb urgency=high\]' "$MAKO" | cut -d: -f1 || true)"
[ -n "$dnd_line" ] && [ -n "$urgent_line" ] || fail "mako: faltan las secciones de No molestar"
[ "$urgent_line" -gt "$dnd_line" ] || fail "mako: la excepción urgente tiene que ir después de No molestar"
sed -n "$((urgent_line + 1))p" "$MAKO" | grep -qx 'invisible=0' || fail "mako: lo urgente sigue invisible con No molestar"
ok "mako: No molestar deja ver las notificaciones urgentes"

# B2 (2026-11-20): toda ventana con app-id propio tiene su regla en Sway.
RULES="$ROOT_DIR/home/.config/sway/config.d/50-rules.conf"
while IFS= read -r app_id; do
  grep -Fq "app_id=\"$app_id\"" "$RULES" || grep -Fq "app_id=\"^$app_id\$\"" "$RULES" ||
    fail "sway: la ventana $app_id no tiene regla en 50-rules.conf"
done < <(grep -rhoE 'app-id[ =]+"?[A-Za-z0-9_-]+' "$ROOT_DIR/home/.local/bin" "$ROOT_DIR/home/.config" |
  sed -E 's/app-id[ =]+"?//' | sort -u)
ok "sway: todas las ventanas con app-id propio tienen regla"

printf 'Pruebas de scripts UI: OK\n'
