#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"
export PATH="$TEST_ROOT/bin:$PATH"
export HOME="$TEST_ROOT/home" XDG_CACHE_HOME="$TEST_ROOT/cache"
export TEST_LOG="$TEST_ROOT/log"
export XDG_STATE_HOME="$TEST_ROOT/state"
export WAYLAND_DISPLAY=wayland-test SWAYSOCK="$TEST_ROOT/sway.sock"
export DBUS_SESSION_BUS_ADDRESS=unix:path=/test
export XDG_RUNTIME_DIR="$TEST_ROOT/run"
mkdir -p "$XDG_RUNTIME_DIR"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

cat > "$TEST_ROOT/bin/pactl" <<'EOF'
#!/usr/bin/env bash
[ -z "${AUDIO_CASE_FILE:-}" ] || AUDIO_CASE="$(cat "$AUDIO_CASE_FILE")"
case "$AUDIO_CASE" in
  active) printf '    Corked: no\n' ;;
  inactive) printf '    Corked: yes\n' ;;
  failed) exit 1 ;;
esac
EOF
cat > "$TEST_ROOT/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_LOG"
case "$*" in
  *is-active*) exit "${SYSTEMCTL_ACTIVE:-0}" ;;
esac
exit "${SYSTEMCTL_STATUS:-0}"
EOF
cat > "$TEST_ROOT/bin/dbus-update-activation-environment" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TEST_ROOT/bin/swaymsg" <<'EOF'
#!/usr/bin/env bash
exit "${SWAY_STATUS:-0}"
EOF
cat > "$TEST_ROOT/bin/logger" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TEST_ROOT/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify: %s\n' "$*" >> "$TEST_LOG"
EOF
cat > "$TEST_ROOT/bin/cliphist" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list)
    [ "${CLIP_CASE:-}" != empty ] || { echo 'opening db: please store something first' >&2; exit 1; }
    printf '1\ttexto\n' ;;
  decode) exit 1 ;;
esac
EOF
cat > "$TEST_ROOT/bin/fuzzel" <<'EOF'
#!/usr/bin/env bash
cat
EOF
cat > "$TEST_ROOT/bin/wl-copy" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
EOF
cat > "$TEST_ROOT/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat > "$TEST_ROOT/bin/systemd-run" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TEST_ROOT/bin/"*

for audio_case in active inactive failed; do
  : > "$TEST_LOG"
  status=0
  AUDIO_CASE="$audio_case" SUSPEND_AUDIO_INTERVAL=3600 bash "$ROOT_DIR/home/.local/bin/suspend-if-no-audio" || status=$?
  bash "$ROOT_DIR/home/.local/bin/suspend-if-no-audio" --cancel
  case "$audio_case" in
    active) [ ! -s "$TEST_LOG" ] || fail "suspendió con audio activo" ;;
    inactive) grep -qx 'suspend' "$TEST_LOG" || fail "no suspendió sin audio" ;;
    failed)
      [ "$status" -ne 0 ] || fail "no informó el fallo de pactl"
      [ ! -s "$TEST_LOG" ] || fail "suspendió sin poder consultar el audio"
      ;;
  esac
done
printf 'OK suspensión distingue audio activo, inactivo y consulta fallida\n'

# A2: con audio, la espera queda aparte (swayidle -w no se bloquea) y suspende
# cuando termina el audio; el resume de swayidle la cancela.
wait_for() {  # condición, hasta 5 s
  for _ in $(seq 50); do eval "$1" && return 0; sleep 0.1; done
  return 1
}
SUSPEND="$ROOT_DIR/home/.local/bin/suspend-if-no-audio"
export AUDIO_CASE_FILE="$TEST_ROOT/audio" SUSPEND_AUDIO_INTERVAL=0.2
printf 'active\n' > "$AUDIO_CASE_FILE"
: > "$TEST_LOG"
started=$SECONDS
timeout 5 bash "$SUSPEND" || fail "la espera de audio bloqueó a swayidle o falló"
[ $((SECONDS - started)) -lt 3 ] || fail "suspend-if-no-audio no volvió enseguida con audio activo"
wait_for '[ -s "$XDG_RUNTIME_DIR/suspend-if-no-audio.pid" ]' || fail "no quedó una espera en segundo plano"
! grep -qx suspend "$TEST_LOG" || fail "suspendió con audio activo"
printf 'inactive\n' > "$AUDIO_CASE_FILE"
wait_for 'grep -qx suspend "$TEST_LOG"' || fail "no suspendió cuando terminó el audio"
wait_for '[ ! -e "$XDG_RUNTIME_DIR/suspend-if-no-audio.pid" ]' || fail "la espera no se limpió al suspender"
printf 'OK suspensión espera a que termine el audio sin bloquear a swayidle\n'

printf 'active\n' > "$AUDIO_CASE_FILE"
: > "$TEST_LOG"
bash "$SUSPEND"
wait_for '[ -s "$XDG_RUNTIME_DIR/suspend-if-no-audio.pid" ]' || fail "no quedó una espera en segundo plano"
waiter="$(cat "$XDG_RUNTIME_DIR/suspend-if-no-audio.pid")"
bash "$SUSPEND" --cancel
wait_for "! kill -0 $waiter 2>/dev/null" || fail "--cancel no terminó la espera"
printf 'inactive\n' > "$AUDIO_CASE_FILE"
sleep 0.6
! grep -qx suspend "$TEST_LOG" || fail "suspendió después de que el usuario volvió"
grep -Fq 'suspend-if-no-audio --cancel' "$ROOT_DIR/home/.local/bin/start-idle" || fail "start-idle no cancela la espera al volver"
unset AUDIO_CASE_FILE SUSPEND_AUDIO_INTERVAL
printf 'OK volver a usar el equipo cancela la suspensión pendiente\n'

# A1: avisos de batería baja, una vez por nivel y de nuevo tras cargar.
battery_at() {  # capacidad estado
  mkdir -p "$TEST_ROOT/power/BAT0"
  printf '%s\n' "$1" > "$TEST_ROOT/power/BAT0/capacity"
  printf '%s\n' "$2" > "$TEST_ROOT/power/BAT0/status"
  BATTERY_SYSFS_DIR="$TEST_ROOT/power" bash "$ROOT_DIR/home/.local/bin/waybar-battery" >/dev/null
}
: > "$TEST_LOG"
battery_at 50 Discharging
! grep -q '^notify:' "$TEST_LOG" || fail "avisó con batería suficiente"
battery_at 9 Discharging
battery_at 8 Discharging
[ "$(grep -c 'Batería baja' "$TEST_LOG")" = 1 ] || fail "el aviso del 10 % no salió una sola vez"
battery_at 4 Discharging
battery_at 3 Discharging
[ "$(grep -c 'Batería crítica' "$TEST_LOG")" = 1 ] || fail "el aviso del 5 % no salió una sola vez"
grep 'Batería crítica' "$TEST_LOG" | grep -q -- '-u critical' || fail "el aviso del 5 % no es crítico"
battery_at 9 Discharging
[ "$(grep -c 'Batería baja' "$TEST_LOG")" = 1 ] || fail "volvió a avisar el 10 % después del 5 %"
battery_at 20 Charging
battery_at 9 Discharging
[ "$(grep -c 'Batería baja' "$TEST_LOG")" = 2 ] || fail "no volvió a avisar después de cargar"
printf 'OK batería: un aviso al 10 %%, uno crítico al 5 %% y de nuevo tras cargar\n'

for sway_status in 0 1; do
  : > "$TEST_LOG"
  status=0
  SWAY_STATUS="$sway_status" bash "$ROOT_DIR/home/.local/bin/sway-autostart" || status=$?
  [ "$status" -eq "$sway_status" ] || fail "se perdió el resultado de la suscripción IPC"
  grep -qx -- '--user --no-block stop sway-session.target' "$TEST_LOG" ||
    fail "quedaron servicios activos después del cierre del socket"
done
printf 'OK sesión limpia sus servicios tanto al cerrar como al fallar el IPC\n'

: > "$TEST_LOG"
if bash "$ROOT_DIR/home/.local/bin/clipboard-menu" >/dev/null 2>&1; then
  fail "portapapeles informó éxito al fallar decode"
fi
[ ! -s "$TEST_LOG" ] || fail "portapapeles notificó éxito después de un error"
printf 'OK portapapeles propaga errores al decodificar\n'

: > "$TEST_LOG"
if SYSTEMCTL_ACTIVE=3 SYSTEMCTL_STATUS=1 bash "$ROOT_DIR/home/.local/bin/nightlight-mode" --toggle >/dev/null 2>&1; then
  fail "luz nocturna informó éxito al fallar systemctl start"
fi
grep -q -- '--user start wlsunset.service' "$TEST_LOG" || fail "luz nocturna no intentó iniciar wlsunset"
! grep -q '^notify:' "$TEST_LOG" || fail "luz nocturna notificó éxito después de un error"
printf 'OK luz nocturna propaga errores al iniciar\n'

: > "$TEST_LOG"
CLIP_CASE=empty bash "$ROOT_DIR/home/.local/bin/clipboard-menu" >/dev/null 2>&1 ||
  fail "portapapeles falló con el historial recién creado"
grep -q 'vacío' "$TEST_LOG" || fail "portapapeles no avisó que el historial está vacío"
printf 'OK portapapeles avisa con el historial recién creado\n'

# M1: si el monitor de udev se corta, disk-notify termina con error para que
# systemd lo relance (Restart=on-failure).
printf '%s\n' '#!/usr/bin/env bash' "printf 'ACTION=add\\nDEVNAME=/dev/no-existe\\n\\n'" > "$TEST_ROOT/bin/udevadm"
chmod +x "$TEST_ROOT/bin/udevadm"
status=0
timeout 10 bash "$ROOT_DIR/home/.local/bin/disk-notify" 2>/dev/null || status=$?
[ "$status" -ne 124 ] || fail "disk-notify no terminó cuando se cortó el monitor"
[ "$status" -ne 0 ] || fail "disk-notify terminó sin error: systemd no lo relanzaría"
grep -qx 'Restart=on-failure' "$ROOT_DIR/home/.config/systemd/user/disk-notify.service" ||
  fail "disk-notify.service no se relanza ante fallas"
printf 'OK disk-notify termina con error si se corta el monitor, y systemd lo relanza\n'

# M3: el historial del portapapeles no se acumula en el disco entre sesiones.
unit="$ROOT_DIR/home/.config/systemd/user/sway-cliphist.service"
grep -qx 'ExecStartPre=/usr/bin/cliphist wipe' "$unit" || fail "el portapapeles no se vacía al iniciar la sesión"
grep -Eq '^ExecStart=.*cliphist -max-items [0-9]+ store$' "$unit" || fail "el historial del portapapeles no tiene límite"
printf 'OK portapapeles: se vacía al iniciar sesión y tiene límite\n'

# B4: al arrancar, disk-notify olvida las marcas de discos que ya no están.
mkdir -p "$XDG_RUNTIME_DIR/disk-notify"
touch "$XDG_RUNTIME_DIR/disk-notify/no-existe-sdq.added"
timeout 10 bash "$ROOT_DIR/home/.local/bin/disk-notify" 2>/dev/null || true
[ ! -e "$XDG_RUNTIME_DIR/disk-notify/no-existe-sdq.added" ] || fail "disk-notify conservó la marca de un disco que ya no está"
printf 'OK disk-notify olvida avisos de discos desconectados mientras estaba caído\n'
