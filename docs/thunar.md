# Thunar junto a Yazi

Instalado el 2026-11-14 a pedido del usuario:

- thunar 4.20.10-1
- tumbler 4.20.2-2 (miniaturas)
- thunar-archive-plugin 0.6.0-1 (integración con File Roller, ya instalado)
- gvfs 1.62.0-3 (papelera, unidades y ubicaciones remotas)

Se abrió `~/Imágenes` y se verificaron visualmente miniaturas, tema oscuro,
iconos Papirus y tipografía Lexend. Usa Adwaita-dark, cuyo gris neutro difiere
del fondo azulado Catppuccin Mocha de Waybar y Foot.

Después se añadió `home/.config/gtk-3.0/gtk.css` con reglas limitadas a la
clase `.thunar`: fondo Mocha #1e1e2e, lateral y barras #181825, texto #cdd6f4,
selección y foco #89b4fa, y controles suavemente redondeados. Se comprobó en
una captura del escritorio y no hubo advertencias de CSS al abrirlo.
Se conservan Lexend y Papirus. El tema global sigue siendo Adwaita-dark y
Mod+E sigue abriendo Yazi. Para revertir el estilo basta quitar ese archivo
CSS (o sus reglas `.thunar`) y reiniciar Thunar.

Abrir desde el lanzador como «Thunar» o ejecutar `thunar`.

## Prueba anterior: tema GTK Qogir Dark

Se reemplazó el ajuste Mocha por Qogir-Dark original, variante azul, instalado
con el instalador oficial sin tweaks ni enlaces forzados de libadwaita.
Fuente: https://github.com/vinceliuice/Qogir-theme
Revisión: e7b3146860e5e981a075b4b56facf8e1c2ae5abb.
Se instaló sassc como dependencia del instalador. El tema y sus licencias
están en `home/.local/share/themes/Qogir-Dark/`.

GTK 3/4 y xsettingsd indican Qogir-Dark. También se aplicó la preferencia
persistente de Wayland mediante:

```sh
gsettings set org.gnome.desktop.interface gtk-theme Qogir-Dark
```

Al restaurar en otra sesión se debe ejecutar también ese comando. El CSS
local ya no altera Thunar. Se conservaron Lexend, Papirus y Yazi como gestor
predeterminado. Se comprobó Qogir y los menús en español en una captura.
La configuración previa y el CSS Mocha se guardaron en
`backups/pre-qogir-2026-11-14/` (no versionado).
Para volver a Adwaita-dark, restaurar esos ajustes y ejecutar el comando
gsettings anterior con `Adwaita-dark`.

## Configuración actual: paleta Mocha e iconos Qogir

El usuario aclaró que quería cambiar los iconos, no la paleta. Se restauró
Adwaita-dark y el CSS de Thunar Mocha desde el backup anterior. Qogir como
tema GTK quedó inactivo y se retiró `home/.local/share/themes/Qogir-Dark/`.
GTK 3/4, xsettingsd, qt6ct, Fuzzel y Mako usan iconos `Qogir-Dark` (con
`Papirus-Dark` como respaldo en Mako); Lexend y el cursor `Breeze_Light` se
mantienen.

El tema de iconos se gestiona mediante el paquete `qogir-icon-theme` en AUR
(`docs/pkglist-aur.txt`), y los paquetes de Thunar (`thunar`, `tumbler`,
`thunar-archive-plugin`, `gvfs`) quedan registrados en
`docs/pkglist-pacman.txt`.

Integración con Sway y Fuzzel:
- En `home/.config/sway/config.d/50-rules.conf`, `thunar` se asigna y enfoca en
  el escritorio `4:files` (igual que Yazi).
- En `home/.local/share/applications/` se ocultan `thunar-settings.desktop` y
  `thunar-bulk-rename.desktop` con `NoDisplay=true` para que en Fuzzel solo
  aparezca la entrada principal de Thunar.

Preferencias persistentes de la sesión (aplicadas automáticamente por
`./restore.sh`):

```sh
gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark
gsettings set org.gnome.desktop.interface icon-theme Qogir-Dark
```
