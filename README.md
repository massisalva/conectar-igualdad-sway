# Conectar Igualdad SF20GM7 - Sway + Waybar

Configuración personal de Arch Linux en una netbook Conectar Igualdad SF20GM7.

## Entorno

- Arch Linux
- Sway
- Waybar
- foot
- fuzzel
- mako
- Catppuccin
- Yazi
- systemd-boot

## Estructura

- config/sway
- config/waybar
- config/mako
- config/fuzzel
- scripts
- polkit
- bootloader
- docs

## Características principales

- Configuración modular de Sway.
- Waybar con módulos de música, discos, CPU, memoria, Bluetooth, red, audio, brillo, batería y energía.
- Menús flotantes con foot y fuzzel.
- Notificaciones con mako.
- Manejo de dispositivos externos/removibles con disk-manager, disk-status y disk-notify.
- Power menu con bloqueo, suspensión, reinicio, apagado y salida de Sway.
- Reglas polkit para discos y energía local.
- systemd-boot ajustado con console-mode max.
- Scripts locales con validación básica de dependencias y fallos no fatales de notificación.
- Yazi con Catppuccin Mocha, plugins oficiales y previews completas.
- Carpetas XDG del usuario registradas en español.

## Restauración

- Paquetes explícitos actuales: `docs/pkglist-explicit.txt`
- Configuración de usuario versionada bajo `config/`, `home/`, `scripts/`, `polkit/` y `bootloader/`.

## Notas

Esta configuración está pensada para uso personal en la netbook conectar-igualdad.

No incluye backups, claves privadas, tokens ni archivos sensibles.

Los backups manuales de auditoría se guardan fuera del historial Git y están ignorados mediante `backups/`.
