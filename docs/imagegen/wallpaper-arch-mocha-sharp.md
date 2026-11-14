# Ajuste de claridad

Herramienta: image_gen integrada. Referencia: wallpaper-arch-mocha-minimal.png.
Salida: home/Imágenes/wallpaper-arch-mocha-sharp.png, 1366×768.

Prompt: conservar composición, tamaño pequeño y silueta de Arch y la marca
inferior. Sustituir el degradado del logo por azul Catppuccin #89b4fa uniforme,
con bordes limpios para mejorar legibilidad en un panel mate. Fondo oscuro
#181825, sin adornos, sombras, resplandores ni desenfoque. Mantener el texto
«conectar igualdad». No añadir elementos ni agrandar el logo.

Aplicación con `center` a resolución nativa para evitar escalado adicional.
Re-renderizado en vector puro (`resvg` a 1366×768 desde `/usr/share/pixmaps/archlinux-logo.svg` y tipografía `Lexend` SemiBold) para eliminar manchas de difusión y halos en bordes.
