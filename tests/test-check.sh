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

# H7b: sin acceso a systemd, --system no certifica nftables.
nft_case() (
  local strict="$1"
  source "$ROOT_DIR/check.sh"
  STRICT_SYSTEM="$strict"
  check_same_system_file() { :; }
  has_cmd() { return 0; }
  systemctl() {
    case "$1" in
      show) return 0 ;;
      is-enabled) printf 'Failed to connect to system scope bus\n'; return 1 ;;
    esac
  }
  check_nftables
)
out="$(nft_case 1)"
grep -Fq '[FAIL] no puedo verificar nftables por permisos del entorno' <<< "$out" || \
  fail_test "--system certificó nftables sin poder verificarlo"
out="$(nft_case 0)"
grep -Fq '[WARN] no puedo verificar nftables por permisos del entorno' <<< "$out" || \
  fail_test "en modo normal, nftables sin verificar no quedó como aviso"
printf '[OK] --system no certifica lo que no pudo verificar\n'

# H7a: la comparación con upstream dice que es contra la copia local.
(
  source "$ROOT_DIR/check.sh"
  repo_tmp="$(mktemp -d)"
  trap 'rm -rf "$repo_tmp"' EXIT
  git init -q --bare "$repo_tmp/remoto.git"
  git clone -q "$repo_tmp/remoto.git" "$repo_tmp/clon" 2>/dev/null
  git -C "$repo_tmp/clon" -c user.name=t -c user.email=t@t commit -q --allow-empty -m inicial
  git -C "$repo_tmp/clon" push -q origin HEAD 2>/dev/null
  git -C "$repo_tmp/clon" branch -q --set-upstream-to=origin/HEAD 2>/dev/null ||
    git -C "$repo_tmp/clon" branch -q --set-upstream-to="origin/$(git -C "$repo_tmp/clon" branch --show-current)"
  ROOT_DIR="$repo_tmp/clon"
  out="$(check_repo_state)"
  grep -Fq 'copia local de la referencia' <<< "$out" || fail_test "check afirmó sincronización sin aclarar que no consultó el servidor"
  ! grep -Fq 'sincronizado' <<< "$out" || fail_test "check sigue diciendo sincronizado"
)
printf '[OK] el estado del repo aclara que compara con la copia local\n'

# A1: UPower tiene que estar habilitado y activo.
power_case() (
  local case_enabled="$1" case_active="$2" strict="$3"
  source "$ROOT_DIR/check.sh"
  STRICT_SYSTEM="$strict"
  systemctl() {
    case "$1" in
      is-enabled) printf '%s\n' "$case_enabled"; [ "$case_enabled" = enabled ] ;;
      is-active) printf '%s\n' "$case_active"; [ "$case_active" = active ] ;;
    esac
  }
  check_power
)
grep -Fq '[OK] UPower habilitado y activo' <<< "$(power_case enabled active 0)" || fail_test "check no reconoció UPower activo"
grep -Fq '[WARN] UPower disabled/inactive' <<< "$(power_case disabled inactive 0)" || fail_test "check no avisó UPower deshabilitado"
grep -Fq '[FAIL] UPower disabled/inactive' <<< "$(power_case disabled inactive 1)" || fail_test "--system aceptó UPower deshabilitado"
grep -Fq '[WARN] no puedo verificar upower.service por permisos del entorno' <<< "$(power_case enabled 'Failed to connect to system scope bus' 0)" || fail_test "check confundió falta de bus en is-active con UPower caído"
grep -Fq '[FAIL] no puedo verificar upower.service por permisos del entorno' <<< "$(power_case enabled 'Failed to connect to system scope bus' 1)" || fail_test "--system aceptó upower sin acceso al bus"
grep -Fq '[FAIL] no puedo verificar upower.service por permisos del entorno' <<< "$(power_case 'Operation not permitted' inactive 1)" || fail_test "--system aceptó upower sin permisos en is-enabled"
printf '[OK] check controla que UPower actúe con batería crítica\n'

printf 'Pruebas de check: OK\n'
