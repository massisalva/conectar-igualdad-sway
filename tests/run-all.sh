#!/usr/bin/env bash
# Valida el repositorio sin tocar el equipo: sintaxis, TOML, ShellCheck (si está
# instalado; fallan errores y advertencias, las notas no) y todas las pruebas, en carpetas temporales, sin sudo ni sesión
# gráfica. Con --sway suma la prueba de integración con Sway sin pantalla.
# Sale con 1 si algo falla.

set -uo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1
SWAY=0
case "${1:-}" in
  --sway) SWAY=1 ;;
  '') ;;
  -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) printf 'Opción desconocida: %s\n' "$1" >&2; exit 2 ;;
esac

FAILED=0
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

step() {
  local name="$1"
  shift
  if "$@" >"$LOG" 2>&1; then
    printf '[OK]   %s\n' "$name"
  else
    printf '[FAIL] %s\n' "$name"
    sed 's/^/       /' "$LOG" | tail -n 20
    FAILED=1
  fi
}

bash_scripts() {
  local file
  for file in restore.sh check.sh lib/*.sh tests/*.sh home/.local/bin/*; do
    [ -f "$file" ] && head -n1 "$file" | grep -q bash && printf '%s\n' "$file"
  done
}

syntax() {
  local file status=0
  while IFS= read -r file; do
    bash -n "$file" || { printf 'sintaxis: %s\n' "$file"; status=1; }
  done < <(bash_scripts)
  return "$status"
}

toml() {
  find home -name '*.toml' -print0 | xargs -0 -r python3 -c '
import sys, tomllib
for path in sys.argv[1:]:
    with open(path, "rb") as f:
        tomllib.load(f)
'
}

shellcheck_all() {
  local -a files
  mapfile -t files < <(bash_scripts)
  # Política: errores y advertencias se corrigen. Las notas no cortan: casi todas
  # son SC2317/SC2329 sobre funciones simuladas en los tests, que se llaman de
  # forma indirecta. Una excepción puntual va con "# shellcheck disable=SCxxxx"
  # y un comentario que explique el porqué.
  shellcheck -x -S warning "${files[@]}"
}

step "sintaxis de bash" syntax
step "TOML de home/" toml
if command -v shellcheck >/dev/null 2>&1; then
  step "ShellCheck" shellcheck_all
else
  printf '[SKIP] ShellCheck no está instalado (sudo pacman -S shellcheck)\n'
fi
for test_file in tests/test-*.sh; do
  step "$test_file" bash "$test_file"
done
if [ "$SWAY" -eq 1 ]; then
  step "tests/test-wallpaper-sway.py (Sway sin pantalla)" python3 tests/test-wallpaper-sway.py
else
  printf '[SKIP] prueba con Sway (agregar --sway)\n'
fi

[ "$FAILED" -eq 0 ] && printf 'Todo OK\n' || printf 'Hay fallas\n'
exit "$FAILED"
