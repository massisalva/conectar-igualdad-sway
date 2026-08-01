#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
CALL_FILE="$TEST_ROOT/wpctl-call"
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
    *) return 1 ;;
  esac
}

fuzzel() {
  printf '[20] Dispositivo repetido\n'
}

wpctl() {
  printf '%s\n' "$*" > "$CALL_FILE"
}

notify-send() {
  return 0
}

export -f pactl fuzzel wpctl notify-send
bash "$ROOT_DIR/home/.local/bin/audio-output-menu"
grep -Fxq 'set-default 20' "$CALL_FILE" || fail "audio-output-menu eligió un ID incorrecto"
ok "audio-output-menu distingue descripciones duplicadas"

printf 'Pruebas de scripts UI: OK\n'
