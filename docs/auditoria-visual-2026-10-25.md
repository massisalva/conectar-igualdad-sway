# Pulido visual del entorno - 2026-10-25

## Objetivo

Se aplicó un ajuste de coherencia visual sobre Sway, Waybar, Fuzzel, Mako,
Qt y los menús de la sesión. Se conserva la paleta Catppuccin Mocha, Lexend
para interfaz y JetBrainsMono Nerd Font para contenido monoespaciado e iconos.

## Cambios aplicados

- **Waybar**: se eliminó el espacio global entre módulos para sellar la cápsula
  de audio y brillo; se incorporaron estados teal para carga y sky para batería
  completa, hover para el reloj y se retiraron selectores obsoletos de CPU/RAM.
- **Sway**: el contenedor enfocado ahora usa `surface0`, las pestañas inactivas
  `crust` y el indicador de división `lavender`. El aviso de salida conserva
  confirmación explícita y adopta colores y tipografía Catppuccin.
- **Menús y avisos**: los prompts de energía, capturas, audio, discos y atajos
  incluyen iconos coherentes. Notificaciones de portapapeles, capturas, audio,
  energía, discos y no molestar usan aplicación e identificador sincrónico;
  el atajo de micrófono muestra su estado real e icono correspondiente.
- **Qt y cursor**: Qt5/Qt6 usan Lexend como fuente general y JetBrainsMono Nerd
  Font como fija. `xsettingsd` adopta el cursor `Breeze_Light`.
- **Reproducibilidad**: se añadieron al árbol `home/` Starship, Fastfetch,
  xsettingsd y el wallpaper PNG activo de 1366×768.

## Aplicación y validación

Los archivos se restauraron sobre `$HOME` mediante `restore.sh --no-yazi`, con
backup previo en `backups/restore-20261025-194808-544170605-14`.

- JSON de Waybar y Fastfetch válido.
- Scripts modificados pasan `bash -n` y `tests/test-ui-scripts.sh`.
- `./check.sh` confirmó la coincidencia de los archivos de usuario nuevos y
  modificados, sin fallos.

La sesión aislada de validación no puede conectarse al socket de Sway ni al bus
de systemd del usuario. Para cargar al instante los colores de Sway/Waybar,
usar `Mod+Shift+C` desde la sesión gráfica; las aplicaciones Qt tomarán la
fuente nueva al reiniciarse.
