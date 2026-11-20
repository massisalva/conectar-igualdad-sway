#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
# shellcheck source=lib/system-files.sh
source "$ROOT_DIR/lib/system-files.sh"
system_files > "$TEST_ROOT/inventory"
python3 - "$ROOT_DIR" "$TEST_ROOT/inventory" <<'PY'
from pathlib import Path, PurePosixPath
import re, sys
root = Path(sys.argv[1])
rows = [line.split('|') for line in Path(sys.argv[2]).read_text().splitlines()]
assert rows, 'inventario vacío'
targets = set()
sources = set()
for row in rows:
    assert len(row) == 5, row
    group, kind, source, target, mode = row
    assert re.fullmatch(r'[a-z]+', group), row
    assert target.startswith(('/etc/', '/boot/')), row
    assert str(PurePosixPath(target)) == target and '..' not in PurePosixPath(target).parts, row
    assert not any(c in target for c in '*?[]\t\n'), row
    assert target not in targets, f'destino duplicado: {target}'
    targets.add(target)
    if kind == 'file':
        assert not source.startswith('/') and '..' not in PurePosixPath(source).parts, row
        assert (root / source).is_file(), f'origen ausente: {source}'
        assert re.fullmatch(r'[0-7]{3,4}', mode), row
        sources.add(source)
    else:
        assert kind == 'link' and source.startswith('/') and mode == '-', row
# Un archivo de sistema nuevo no debe quedar fuera del inventario por olvido.
expected = set()
for folder, patterns in {
    'polkit': ['*.rules'], 'sshd': ['*.conf'], 'sysctl': ['*.conf'],
    'samba': ['*.mount', '*.automount'], 'bootloader': ['*.conf'],
    'iwd': ['*.conf'], 'nftables': ['*.conf'], 'zram': ['*.conf'],
}.items():
    for pattern in patterns:
        expected.update(str(p.relative_to(root)) for p in (root / folder).glob(pattern))
assert sources == expected, f'archivos fuera del inventario: {sources ^ expected}'
print('[OK] inventario válido, sin patrones ni duplicados, y completo')
PY

# Una sola entrada nueva debe alimentar instalación, rollback y verificación.
mini="$TEST_ROOT/repo"
mkdir -p "$mini"
cp "$ROOT_DIR/restore.sh" "$ROOT_DIR/check.sh" "$mini/"
cp -a "$ROOT_DIR/lib" "$ROOT_DIR/polkit" "$ROOT_DIR/iwd" "$mini/"
printf 'regla de prueba\n' > "$mini/polkit/48-inventory-test.rules"
python3 - "$mini/lib/system-files.sh" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace('\nINVENTORY\n', '\npolkit|file|polkit/48-inventory-test.rules|/etc/polkit-1/rules.d/48-inventory-test.rules|640\nINVENTORY\n', 1)
p.write_text(s)
PY
HOME="$TEST_ROOT/home" bash "$mini/restore.sh" --no-user --no-yazi --polkit --dry-run -y > "$TEST_ROOT/install"
grep -Fq "sudo install -Dm640 $mini/polkit/48-inventory-test.rules /etc/polkit-1/rules.d/48-inventory-test.rules" "$TEST_ROOT/install" ||
  fail "la instalación no tomó origen, destino y modo del inventario"
mkdir -p "$TEST_ROOT/backup"
printf 'missing\t/etc/polkit-1/rules.d/48-inventory-test.rules\n' > "$TEST_ROOT/backup/manifest.tsv"
HOME="$TEST_ROOT/home" bash "$mini/restore.sh" --rollback "$TEST_ROOT/backup" --dry-run -y > "$TEST_ROOT/rollback"
grep -Fq 'sudo rm -f /etc/polkit-1/rules.d/48-inventory-test.rules' "$TEST_ROOT/rollback" ||
  fail "rollback no reconoció la entrada nueva"
(
  # shellcheck source=check.sh
  source "$mini/check.sh"
  check_same_system_file() { printf 'compare:%s|%s\n' "$1" "$2"; }
  stat() {
    case "${!#}" in
      */48-inventory-test.rules) printf '%s\n' "${TEST_INVENTORY_MODE:-640}" ;;
      *) printf '644\n' ;;
    esac
  }
  STRICT_SYSTEM=1
  check_polkit
  [ "$FAILS" -eq 0 ] || fail "check no usó los permisos del inventario"
  TEST_INVENTORY_MODE=666
  check_polkit
  [ "$FAILS" -eq 1 ] || fail "check no detectó permisos distintos a los del inventario"
) > "$TEST_ROOT/check"
grep -Fq "compare:$mini/polkit/48-inventory-test.rules|/etc/polkit-1/rules.d/48-inventory-test.rules" "$TEST_ROOT/check" ||
  fail "check no comparó la entrada nueva"
grep -Fq 'permisos de /etc/polkit-1/rules.d/48-inventory-test.rules: 640' "$TEST_ROOT/check" ||
  fail "check no verificó el modo de la entrada nueva"
printf '[OK] una entrada alimenta instalación, rollback y check sin listas paralelas\n'

# El enlace DNS también se instala desde el inventario sin copiar su destino.
HOME="$TEST_ROOT/home" bash "$mini/restore.sh" --no-user --no-yazi --iwd --dry-run -y > "$TEST_ROOT/dns"
grep -Fq 'sudo ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf' "$TEST_ROOT/dns" ||
  fail "el enlace DNS no se instaló desde el inventario"
printf '[OK] instalación del enlace DNS desde el inventario\n' 

# Todos los instaladores deben emitir exactamente las operaciones inventariadas.
TEST_BOOT_UUID="$(sed -n 's/.*root=UUID=\([^[:space:]]*\).*/\1/p' "$ROOT_DIR/$(system_source_for /boot/loader/entries/arch.conf)")"
export TEST_BOOT_UUID
findmnt() { printf '%s\n' "$TEST_BOOT_UUID"; }
pacman() { return 0; }
export -f findmnt pacman
HOME="$TEST_ROOT/home" bash "$ROOT_DIR/restore.sh" --no-user --no-yazi \
  --polkit --bootloader --sshd --nftables --iwd --sysctl --zram --samba \
  --dry-run -y > "$TEST_ROOT/all-installs"
python3 - "$ROOT_DIR" "$TEST_ROOT/inventory" "$TEST_ROOT/all-installs" <<'PYTEST'
from pathlib import Path
import shlex, sys
root = Path(sys.argv[1])
expected = set()
for line in Path(sys.argv[2]).read_text().splitlines():
    group, kind, source, target, mode = line.split('|')
    if kind == 'file':
        expected.add(('install', '-Dm' + mode, str(root / source), target))
    else:
        expected.add(('ln', '-sfn', source, target))
actual = []
for line in Path(sys.argv[3]).read_text().splitlines():
    if line.startswith(('+ sudo install ', '+ sudo ln ')):
        actual.append(tuple(shlex.split(line)[2:]))
assert len(actual) == len(expected) and set(actual) == expected, (expected ^ set(actual), actual)
print('[OK] todos los instaladores respetan origen, destino, tipo y modo del inventario')
PYTEST

printf 'Pruebas del inventario: OK\n'
