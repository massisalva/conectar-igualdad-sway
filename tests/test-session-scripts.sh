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

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

cat > "$TEST_ROOT/bin/pactl" <<'EOF'
#!/usr/bin/env bash
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
  AUDIO_CASE="$audio_case" bash "$ROOT_DIR/home/.local/bin/suspend-if-no-audio" || status=$?
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
