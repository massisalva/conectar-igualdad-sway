#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail_test() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

health_case() (
  local scenario="$1"
  # Cargar funciones no debe ejecutar ninguna comprobación del equipo real.
  source "$ROOT_DIR/check.sh"
  STRICT_SYSTEM=1
  systemctl() {
    case "$scenario" in
      failed-queries) return 1 ;;
      unhealthy) printf 'broken.service loaded failed failed Test\n' ;;
      *) return 0 ;;
    esac
  }
  sudo_check() {
    [ "$scenario" != no-privileges ] || return 1
    case "$1" in
      true) return 0 ;;
      journalctl)
        case "$scenario" in
          failed-queries) return 1 ;;
          unhealthy) printf '%s\n' '{"MESSAGE":"Error con stack\\nsegunda línea"}' '{"MESSAGE":"Otro error"}' ;;
          *) return 0 ;;
        esac
        ;;
      smartctl) printf 'SMART overall-health self-assessment test result: PASSED\n' ;;
      *) return 1 ;;
    esac
  }
  ss() { printf 'LISTEN 0 128 127.0.0.1:22 0.0.0.0:*\n'; }
  findmnt() { printf '/dev/test1\n'; }
  lsblk() { printf 'test\n'; }
  check_system_health
  printf 'TOTAL_FAILS=%s TOTAL_WARNS=%s\n' "$FAILS" "$WARNS"
)

out="$(health_case failed-queries)"
grep -Fq '[FAIL] no pude consultar las unidades' <<< "$out" || fail_test "check no detectó el fallo de systemctl"
grep -Fq '[FAIL] no pude consultar el journal' <<< "$out" || fail_test "check no detectó el fallo de journalctl"
if grep -Eq '\[OK\] (sin unidades|journal)' <<< "$out"; then
  fail_test "check dio un resultado saludable con consultas fallidas"
fi
grep -Fq 'TOTAL_FAILS=2 TOTAL_WARNS=0' <<< "$out" || fail_test "check no contó las consultas fallidas"
printf '[OK] consultas fallidas no se confunden con resultados vacíos\n'

out="$(health_case healthy)"
grep -Fq '[OK] sin unidades de sistema fallidas' <<< "$out" || fail_test "check rechazó una lista vacía válida de unidades"
grep -Fq '[OK] journal del arranque sin errores' <<< "$out" || fail_test "check rechazó un journal vacío válido"
grep -Fq 'TOTAL_FAILS=0 TOTAL_WARNS=0' <<< "$out" || fail_test "check reportó errores en el caso saludable"
printf '[OK] consultas correctas y vacías conservan el resultado saludable\n'

out="$(health_case unhealthy)"
grep -Fq '[FAIL] 1 unidades de sistema fallidas' <<< "$out" || fail_test "check no contó la unidad fallida"
grep -Fq '[WARN] 2 entradas de error en el journal' <<< "$out" || fail_test "check no contó eventos JSON individuales"
grep -Fq 'TOTAL_FAILS=1 TOTAL_WARNS=1' <<< "$out" || fail_test "check no contabilizó los problemas reales"
printf '[OK] unidades fallidas y errores JSON se contabilizan correctamente\n'

out="$(health_case no-privileges)"
grep -Fq '[FAIL] no puedo verificar el journal completo sin sudo' <<< "$out" || fail_test "check aceptó una vista parcial del journal"
! grep -Fq '[OK] journal' <<< "$out" || fail_test "check certificó el journal sin acceso completo"
printf '[OK] journal sin privilegios no se certifica como completo\n'

# Sin swapon, set -u debe permitir que el diagnóstico continúe.
(
  source "$ROOT_DIR/check.sh"
  has_cmd() { [ "$1" != swapon ] && command -v "$1" >/dev/null 2>&1; }
  check_zram >/dev/null
  printf '[OK] diagnóstico de zram tolera que falte swapon\n'
)

# Luz nocturna: encendida, apagada a mano, fallida y sin instalar se distinguen.
nightlight_case() (
  local case_load="$1" case_state="$2"
  source "$ROOT_DIR/check.sh"
  systemctl() {
    case "$*" in
      *LoadState*) printf '%s\n' "$case_load" ;;
      *is-active*) printf '%s\n' "$case_state"; [ "$case_state" = active ] ;;
    esac
  }
  check_nightlight
  printf 'TOTAL_FAILS=%s TOTAL_WARNS=%s\n' "$FAILS" "$WARNS"
)
out="$(nightlight_case loaded active)"
grep -Fq '[OK] luz nocturna encendida' <<< "$out" || fail_test "check no reconoció la luz nocturna encendida"
out="$(nightlight_case loaded inactive)"
grep -Fq '[OK] luz nocturna apagada a mano' <<< "$out" || fail_test "check marcó como problema la luz nocturna apagada a propósito"
grep -Fq 'TOTAL_FAILS=0 TOTAL_WARNS=0' <<< "$out" || fail_test "check contó la luz nocturna apagada como problema"
out="$(nightlight_case loaded failed)"
grep -Fq '[FAIL] wlsunset.service falló' <<< "$out" || fail_test "check no detectó wlsunset fallido"
out="$(nightlight_case not-found inactive)"
grep -Fq '[FAIL] wlsunset.service no está instalado' <<< "$out" || fail_test "check confundió una unidad ausente con la luz apagada"
printf '[OK] luz nocturna: encendida, apagada a mano, fallida y ausente se distinguen\n'

printf 'Pruebas de check: OK\n'
