# Inventario Sway / Waybar - Conectar Igualdad SF20GM7

## Equipo

- Hostname: conectar-igualdad
- Usuario: massisalva
- Sistema: Arch Linux
- Entorno: Sway + Waybar + foot + fuzzel + mako
- Estilo visual: Catppuccin

## Sway

Archivo principal:

- ~/.config/sway/config

Configuración modular:

- ~/.config/sway/config.d/00-palette.conf
- ~/.config/sway/config.d/10-vars.conf
- ~/.config/sway/config.d/20-appearance.conf
- ~/.config/sway/config.d/30-input.conf
- ~/.config/sway/config.d/40-keybindings.conf
- ~/.config/sway/config.d/50-rules.conf
- ~/.config/sway/config.d/60-autostart.conf

El archivo principal solo incluye:

- include ~/.config/sway/config.d/*.conf
- include /etc/sway/config.d/*

## Escritorios

Categorías:

- 1:term: terminales generales (`foot`, `foot-term`).
- 2:web: navegador (`firefox`).
- 3:music: reproductores (`foot-music`, `foot-music-ncmpcpp`, `foot-music-ncspot`, `foot-music-pyradio`).
- 4:files: archivos (`foot-files` con Yazi).
- 5:system: monitoreo y sistema (`foot-system` con btop).
- 6-10: reserva para chat, media, trabajo, laboratorio o uso temporal.

## Waybar

Archivos:

- ~/.config/waybar/config.jsonc
- ~/.config/waybar/style.css

Módulos activos:

- workspaces
- música
- reloj
- mayúsculas activadas
- discos
- CPU
- memoria
- Bluetooth
- red
- audio
- brillo
- batería
- power

## Música

Script:

- ~/.local/bin/pyradio-music
- ~/.local/bin/waybar-music

Fuentes detectadas:

- PyRadio / mpv
- MPD / ncmpcpp
- ncspot / Spotify vía playerctl
- Firefox vía playerctl/MPRIS

Interacciones de Waybar:

- Click izquierdo: abre el reproductor activo.
- Click derecho: reproduce o pausa el reproductor activo.
- Scroll arriba/abajo: siguiente/anterior en el reproductor activo.

Estado:

- MPD/ncmpcpp, ncspot, PyRadio y Firefox intentan enfocar la instancia activa antes de abrir otra.
- ncmpcpp, ncspot y PyRadio abren foot con app_id propio si no hay una sesión activa.
- Firefox abre/reutiliza el navegador si no hay una ventana enfocable.
- PyRadio se lanza con `pyradio-music`, que fuerza Catppuccin Macchiato y `mpv`.
- PyRadio usa un perfil de mpv con volumen normalizado.
- PyRadio usa modo XDG explícito: config en `~/.config/pyradio`, datos en `~/.local/share/pyradio` y estado en `~/.local/state/pyradio`.
- PyRadio mantiene creado `~/pyradio-recordings` para evitar fallos al preparar logs/grabaciones.
- Las ventanas de música se asignan al workspace `3:music`.
- ncmpcpp, ncspot, PyRadio y el gestor de discos abren foot con `app_id` de música/archivos para caer directo en `3:music` o `4:files`.
- La entrada local de PyRadio usa el mismo tema y reproductor que `pyradio-music`.

## Autostart

Script:

- ~/.local/bin/sway-autostart

Estado importante:

- Las apps gráficas se lanzan vía swaymsg exec.
- Esto evita que Waybar nazca desde una sesión SSH.
- Waybar debe quedar en session-1.scope o en la sesión local activa de Sway.

Procesos lanzados:

- mako
- waybar
- polkit-gnome-authentication-agent-1
- udiskie --no-automount --no-notify
- disk-notify

## Power menu

Script:

- ~/.local/bin/power-menu

Acciones:

- Bloquear
- Suspender
- Reiniciar
- Apagar
- Salir de Sway
- Cancelar

Suspender, reiniciar, apagar y salir de Sway piden confirmación en fuzzel.

Estado post-auditoría:

- power-menu notifica fallos de bloqueo, suspensión, reinicio, apagado o salida de Sway.
- start-idle valida entorno Wayland/Sway antes de lanzar swayidle.
- start-idle limita el reinicio de swayidle al perfil gestionado por este script.

## Polkit energía

Regla:

- /etc/polkit-1/rules.d/50-local-power.rules

Permite a massisalva, desde sesión local activa, ejecutar sin contraseña:

- org.freedesktop.login1.power-off
- org.freedesktop.login1.power-off-multiple-sessions
- org.freedesktop.login1.reboot
- org.freedesktop.login1.reboot-multiple-sessions
- org.freedesktop.login1.suspend
- org.freedesktop.login1.suspend-multiple-sessions

No se tocó sudoers.

## Polkit discos

Regla:

- /etc/polkit-1/rules.d/49-udisks2-storage.rules

Permite montar, desmontar, expulsar y apagar discos para usuarios activos del grupo storage.

## Discos

Scripts:

- ~/.local/bin/disk-manager
- ~/.local/bin/disk-status
- ~/.local/bin/disk-notify

Estado:

- Waybar cambia color según estado de disco.
- disk-manager usa lsblk -J + Python.
- disk-manager valida dependencias críticas antes de mostrar el menú.
- Soporta etiquetas con espacios.
- disk-manager no usa sudo; monta, desmonta y expulsa con udisksctl.
- disk-manager lista USB, MMC y dispositivos removibles; excluye /, /boot, /boot/*, [SWAP], zram y loop.
- disk-status usa el mismo criterio de USB/MMC/removible que disk-manager.
- disk-notify tolera fallos de notify-send sin cortar el monitor.
- udiskie corre sin automount y sin notificaciones propias.

## Teclado

Script:

- ~/.local/bin/waybar-capslock

Estado:

- Waybar muestra un indicador solo cuando Caps Lock está activo.
- El script lee `/sys/class/leds/input*::capslock/brightness`, sin depender de X11.
- El módulo se actualiza cada 1 segundo.

## Audio

Scripts:

- ~/.local/bin/audio-menu
- ~/.local/bin/audio-output-menu

Estado:

- PipeWire / PipeWire-Pulse / WirePlumber funcionando.
- Click izquierdo: pulsemixer flotante.
- Click derecho: selector de salida con fuzzel.
- audio-menu y audio-output-menu validan dependencias antes de ejecutar.
- WirePlumber conserva preferencia persistente por salidas Bluetooth conocidas cuando están disponibles.

## Bluetooth

Script:

- ~/.local/bin/bluetooth-menu

Usa bluetui dentro de foot flotante.

Estado:

- bluetooth-menu valida foot y bluetui antes de ejecutar.
- bluetooth.service activo.
- Controlador hci0 encendido y sin rfkill.

## Red

Scripts:

- ~/.local/bin/network-menu
- ~/.local/bin/nmtui-catppuccin

Usa nmtui dentro de foot flotante.

Estado:

- network-menu valida foot y nmtui-catppuccin antes de ejecutar.
- nmtui-catppuccin valida nmtui antes de ejecutar.
- NetworkManager activo.

## Capturas

Script:

- ~/.local/bin/screenshot-menu

Atajos:

- Print: pantalla completa
- Mod+Print: región
- Shift+Print: ventana enfocada
- Ctrl+Print: copiar pantalla completa
- Mod+Shift+Print: copiar región
- Mod+Shift+s: menú interactivo

Usa:

- grim
- slurp
- wl-copy
- fuzzel
- notify-send

Estado:

- screenshot-menu valida dependencias según el modo usado.
- screenshot-menu valida WAYLAND_DISPLAY y SWAYSOCK antes de capturar.
- screenshot-menu acepta una ruta de salida como segundo argumento para generar capturas versionables.
- Las notificaciones no cortan el script si DBus o notify-send fallan.

## Batería

Script:

- ~/.local/bin/battery-menu

Estado:

- Batería detectada: BAT1
- Equipo: SF20GM7
- Salud aproximada informada durante auditoría: 92,5 %
- battery-menu valida foot antes de ejecutar.
- UPower activo y sin warnings durante auditoría.

## Brillo

Estado:

- Waybar solo informa brillo.
- El brillo real se controla con teclas físicas.
- Dispositivo: intel_backlight.

## Mako

Archivo:

- ~/.config/mako/config

Estado:

- Tema Catppuccin.
- Notificaciones de volumen y brillo usan x-canonical-private-synchronous para evitar apilado.

## Fuzzel

Archivo:

- ~/.config/fuzzel/fuzzel.ini

Estado:

- Tema Catppuccin.
- Centrado.
- Fuente Lexend.
- Bordes redondeados.
- Iconos habilitados con tema `Papirus-Dark`.
- Las entradas locales de MPD (`ncmpcpp` y `Actualizar música`) usan el icono `mpd`.
- Hay overrides locales `NoDisplay=true` para utilidades, duplicados y helpers que no conviene mostrar en el lanzador.
- Los overrides locales de `.desktop` se versionan porque definen el resultado visible de fuzzel.

## Bootloader

Bootloader:

- systemd-boot

Archivos:

- /boot/loader/loader.conf
- /boot/loader/entries/arch.conf

Cambio aplicado:

- console-mode auto -> console-mode max

Resultado:

- Menú de arranque se ve correctamente, con mejor resolución visual.

## Kernel cmdline

Entrada principal:

- /boot/loader/entries/arch.conf

Opciones relevantes:

- quiet
- loglevel=3

Estado post-reinicio:

- Cmdline efectiva: `root=UUID=f0a05552-b72c-4acb-b5f5-385c81612743 rw quiet loglevel=3`.
- GPU: Intel GeminiLake UHD Graphics 600 `[8086:3185]`, driver en uso: `i915`.
- Kernel: `7.0.11-zen1-1-zen`.
- i915 inicializa correctamente, carga `i915/glk_dmc_ver1_04.bin`, registra framebuffer `i915drmfb` y queda activo.
- Persisten estos mensajes de firmware/BIOS: `Unknown revision 0x06`, `Unknown revid 0x06`, `conflict detected with stolen region: [mem 0x7c000000-0x7fffffff]`, `couldn't get memory information`, `RC6 and powersaving disabled by BIOS`.
- `modinfo i915` no lista `stolen_reserved_size` como parámetro disponible en este kernel; no se deja `i915.stolen_reserved_size=0` en la cmdline.
- Se considera warning conocido de firmware/BIOS en este equipo mientras no haya síntomas: la computadora funciona correctamente y no vale la pena insistir con más parámetros de kernel.

Verificación gráfica post-reinicio:

- Sway, Waybar, Mako, swayidle, PipeWire, WirePlumber y PipeWire-Pulse quedan corriendo en la sesión local.
- DRM expone `card1` y `renderD128` sobre `0000:00:02.0`.
- Panel interno `eDP-1`: `connected`, `enabled`, modo `1366x768`.
- HDMI `HDMI-A-1`: `disconnected`, `disabled`.
- No aparecen mensajes de `flip`, `atomic`, `hang`, `reset`, `stuck`, `timeout`, `vblank` ni errores wlroots/Sway asociados a i915 en el journal del boot.

## Pendientes menores para pulido final

- Agregar captura del escritorio en `docs/media/escritorio.png` y activarla en el README.
- Probar preferencia Bluetooth de audio conectando JBL/LG.
- Revisar warnings menores: Bluetooth default system config hci0, NetworkManager p2p-dev-wlo2.

## Verificación y restauración

Scripts:

- ./restore.sh
- ./check.sh

Estado:

- restore.sh soporta `--dry-run` para revisar acciones sin copiar ni instalar.
- En dry-run, los permisos de ~/.local/bin se simulan desde los scripts versionados en el repo.
- check.sh verifica paquetes, comandos, archivos de usuario, scripts, XDG, Yazi, polkit, bootloader y estado Git.
- check.sh usa sudo no interactivo por defecto para archivos protegidos.
- check.sh permite `--system --sudo` para pedir contraseña y comparar polkit/bootloader con archivos reales del sistema.

## Ajuste final disk-notify

Se detectó que ~/.local/bin/disk-notify había quedado vacío.

Se recreó el script para:

- escuchar eventos de udev sobre dispositivos block;
- notificar solo discos externos/removibles;
- evitar notificaciones duplicadas durante la misma sesión;
- no duplicar avisos al montar desde disk-manager;
- usar x-canonical-private-synchronous:disk-notify para no apilar notificaciones.

Estado final: probado y funcionando correctamente.
