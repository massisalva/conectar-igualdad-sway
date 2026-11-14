# Auditoría integral del sistema y proyecto - 2026-11-14

## Resultado

La auditoría confirmó que el sistema Arch Linux + Sway de la netbook Conectar
Igualdad SF20GM7 (kernel `7.3.4-zen2-1-zen`, `intel-ucode 20261110-1`) se
mantiene saludable, sin paquetes huérfanos ni unidades fallidas de `systemd`
(tanto a nivel sistema como de usuario), con ZRAM activo (`3.8 GiB`, `zstd`,
prioridad `100`, `vm.swappiness=100`) y el automount CIFS/SMB3 de
`~/Compartido` operativo.

## Correcciones aplicadas en el repositorio

- **Compatibilidad con `desktop-file-utils 0.29-1` y reparación de `mpv.desktop`**:
  - Se incorporó la clave `Exec=` correspondiente en los overrides locales con
    `NoDisplay=true` de `home/.local/share/applications/`, resolviendo los 19
    fallos de validación introducidos por `desktop-file-validate 0.29-1` y
    restaurando `Exec=mpv --player-operation-mode=pseudo-gui -- %U` en
    `mpv.desktop` para que `xdg-open` y las asociaciones MIME de audio/video
    funcionen correctamente.
  - Se retiraron 4 overrides `.desktop` huérfanos de paquetes ausentes en
    `/usr/share/applications/` (`avahi-discover.desktop`, `bssh.desktop`,
    `bvnc.desktop`, `vim.desktop`) y 3 overrides redundantes que ya traen
    `NoDisplay=true` en el paquete de sistema (`org.gnupg.pinentry-qt.desktop`,
    `polkit-gnome-authentication-agent-1.desktop`,
    `xdg-desktop-portal-gtk.desktop`).
  - Se reemplazó la ruta absoluta de usuario en `pyradio.desktop` por
    `Icon=pyradio` y se depuraron las listas `Keywords=` en `ncmpcpp.desktop`,
    `ncspot.desktop` y `pyradio.desktop` para eliminar advertencias de
    `desktop-file-validate`.
- **Aislamiento de `home/.cache` en `check.sh` y `restore.sh`**:
  - Se eliminó `home/.cache/mesa_shader_cache/` infiltrado en el árbol del
    repositorio al ejecutar `HOME="$ROOT_DIR/home" sway -C`.
  - `check.sh` ahora ejecuta `sway -C` con `MESA_GLSL_CACHE_DISABLE=true` y un
    `XDG_CACHE_HOME` temporal, además de contemplar el mensaje localizado
    `Operación no permitida`.
  - `restore.sh` excluye explícitamente `home/.cache` al respaldar y restaurar.
- **Inicio de sesión y atajos**:
  - En `home/.config/fish/config.fish` se adelantó `fish_add_path "$HOME/.local/bin"`
    antes de `exec sway` en TTY1 para garantizar que `~/.local/bin` esté en el
    `PATH` de Sway y Fuzzel incluso en una restauración limpia.
  - En `home/.config/sway/config.d/40-keybindings.conf` se unificaron las teclas
    multimedia (`XF86AudioPlay/Pause/Next/Prev`) con `~/.local/bin/waybar-music`
    (permitiendo controlar MPD, PyRadio, ncspot, Spotify y Firefox) y se
    corrigió la notificación de `XF86AudioMute` para distinguir entre silenciado
    y volumen activo.
- **Higiene de `check.sh`, Waybar y documentación**:
  - `check.sh` solo intenta `sudo -n true` cuando se invoca con `--system` (o
    `--sudo`), evitando generar entradas de error de `sudo` en el journal
    durante comprobaciones normales de usuario.
  - Se limpiaron definiciones no utilizadas (`cpu`, `memory`) en
    `home/.config/waybar/config.jsonc`, directorios vacíos residuales y
    referencias desactualizadas en `docs/decisiones.md` y
    `docs/inventario-local.md`.

## Limpieza y mantenimiento del sistema

- Se eliminó el binario de respaldo `~/.local/bin/agy.1794656973099035559.old`
  (**218 MiB**) y los 7 `.desktop` obsoletos en `~/.local/share/applications/`.
- Se ejecutaron y verificaron las acciones administrativas de sistema:
  - Fusión de `/etc/bluetooth/main.conf.pacnew` (`bluez 5.88-1`) conservando
    `AutoEnable=true` (`0` archivos `.pacnew`/`.pacsave` pendientes en `/etc`).
  - Ajuste de permisos de `/etc/ssl/private` a `700`.
  - Verificación de `paccache -rk2`, coincidencia de reglas `polkit` y entradas
    de `systemd-boot` (`/boot/loader/`), y validación de sintaxis efectiva de
    `sshd` (`sshd -t`).

## Ajuste posterior (revisión desde la ThinkPad)

- `restore.sh`: el `rm -rf "$source/.cache"` agregado en esta auditoría ahora pasa
  por `run`, así que con `DRY_RUN=1` solo se muestra y no borra nada. El
  `.gitignore` ya ignoraba `.cache/`, así que `home/.cache` no puede entrar al
  repo. Para deshacer: `git revert` de este commit.
