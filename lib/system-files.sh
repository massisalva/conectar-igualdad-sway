#!/usr/bin/env bash
# Inventario único: grupo|tipo|origen|destino|modo.
# Los orígenes de archivos son relativos al repositorio; los de enlaces, absolutos.
# Modo "-": los permisos los fija el montaje (vfat de /boot, fmask=0177 da 600
# a todo) y no se verifican; se instala con 644, que vfat ignora.
# Mantener destinos exactos: nunca usar patrones para autorizar un rollback.
system_files() {
  local selected="${1:-}" group kind source target mode
  while IFS='|' read -r group kind source target mode; do
    [ -z "$selected" ] || [ "$group" = "$selected" ] || continue
    printf '%s|%s|%s|%s|%s\n' "$group" "$kind" "$source" "$target" "$mode"
  done <<'INVENTORY'
polkit|file|polkit/49-udisks2-storage.rules|/etc/polkit-1/rules.d/49-udisks2-storage.rules|644
polkit|file|polkit/50-local-power.rules|/etc/polkit-1/rules.d/50-local-power.rules|644
bootloader|file|bootloader/loader.conf|/boot/loader/loader.conf|-
bootloader|file|bootloader/arch.conf|/boot/loader/entries/arch.conf|-
sshd|file|sshd/10-hardening.conf|/etc/ssh/sshd_config.d/10-hardening.conf|644
nftables|file|nftables/nftables.conf|/etc/nftables.conf|644
iwd|file|iwd/main.conf|/etc/iwd/main.conf|644
regdom|file|iwd/wireless-regdom.conf|/etc/conf.d/wireless-regdom|644
resolved|link|/run/systemd/resolve/stub-resolv.conf|/etc/resolv.conf|-
sysctl|file|sysctl/99-local-hardening.conf|/etc/sysctl.d/99-local-hardening.conf|644
sysctl|file|sysctl/99-zram.conf|/etc/sysctl.d/99-zram.conf|644
zram|file|zram/zram-generator.conf|/etc/systemd/zram-generator.conf|644
samba|file|samba/home-massisalva-Compartido.mount|/etc/systemd/system/home-massisalva-Compartido.mount|644
samba|file|samba/home-massisalva-Compartido.automount|/etc/systemd/system/home-massisalva-Compartido.automount|644
INVENTORY
}

system_target_registered() {
  local expected="$1" group kind source target mode result=1
  while IFS='|' read -r group kind source target mode; do
    [ "$target" != "$expected" ] || result=0
  done < <(system_files)
  return "$result"
}

# Fuente para validaciones particulares (UUID de arranque, sintaxis de nftables).
system_source_for() {
  local expected="$1" group kind source target mode result=1
  while IFS='|' read -r group kind source target mode; do
    if [ "$target" = "$expected" ] && [ "$kind" = file ]; then
      printf '%s\n' "$source"
      result=0
    fi
  done < <(system_files)
  return "$result"
}
