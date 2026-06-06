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

## Waybar

Archivos:

- ~/.config/waybar/config.jsonc
- ~/.config/waybar/style.css

Módulos activos:

- workspaces
- música
- reloj
- discos
- CPU
- memoria
- Bluetooth
- red
- audio
- brillo
- batería
- power

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

Reiniciar, apagar y salir de Sway piden confirmación en fuzzel.

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
- Soporta etiquetas con espacios.
- udiskie corre sin automount y sin notificaciones propias.

## Audio

Scripts:

- ~/.local/bin/audio-menu
- ~/.local/bin/audio-output-menu

Estado:

- PipeWire / PipeWire-Pulse / WirePlumber funcionando.
- Click izquierdo: pulsemixer flotante.
- Click derecho: selector de salida con fuzzel.

## Bluetooth

Script:

- ~/.local/bin/bluetooth-menu

Usa bluetui dentro de foot flotante.

## Red

Scripts:

- ~/.local/bin/network-menu
- ~/.local/bin/nmtui-catppuccin

Usa nmtui dentro de foot flotante.

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

## Batería

Script:

- ~/.local/bin/battery-menu

Estado:

- Batería detectada: BAT1
- Equipo: SF20GM7
- Salud aproximada informada durante auditoría: 92,5 %

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
- i915.stolen_reserved_size=0

## Pendientes menores para pulido final

- Verificar que disk-notify quede corriendo después del autostart.
- Revisar backups temporales sueltos si se desea una limpieza final.

## Ajuste final disk-notify

Se detectó que ~/.local/bin/disk-notify había quedado vacío.

Se recreó el script para:

- escuchar eventos de udev sobre dispositivos block;
- notificar solo discos externos/removibles;
- evitar notificaciones duplicadas durante la misma sesión;
- no duplicar avisos al montar desde disk-manager;
- usar x-canonical-private-synchronous:disk-notify para no apilar notificaciones.

Estado final: probado y funcionando correctamente.
