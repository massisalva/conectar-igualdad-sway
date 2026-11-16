# Streamrip y Deezer

Ajustes registrados el 2026-11-15. Streamrip 2.1.0 fue instalado con Python 3.12 mediante uv; usa FFmpeg del sistema.

## Instalación y recuperación

Con `uv` y `ffmpeg` disponibles:

```sh
uv tool install --python 3.12 streamrip
rip config --help
```

El segundo comando crea la configuración predeterminada si no existe. Restaurar los archivos de `home/` del proyecto instala el menú, el acceso de aplicaciones, el icono y las reglas de Sway. No instala streamrip ni copia la cuenta de Deezer.

En `~/.config/streamrip/config.toml`, ajustar las claves existentes de estas secciones (conservar las demás):

```toml
[downloads]
folder = "/home/TU_USUARIO/Música/streamrip"
source_subdirectories = true

[deezer]
quality = 1
use_deezloader = false
arl = ""
```

Reemplazar `TU_USUARIO` por el usuario local. Crear la carpeta y proteger el archivo:

```sh
mkdir -p "$HOME/Música/streamrip"
chmod 600 "$HOME/.config/streamrip/config.toml"
```

Agregar la cookie `arl` de la propia cuenta directamente en el archivo local siguiendo la [guía de streamrip](https://github.com/nathom/streamrip/wiki/Finding-Your-Deezer-ARL-Cookie). Es una credencial de sesión y queda fuera de Git.

`quality = 1` solicita MP3 de 320 kbps según el acceso de la cuenta. El cambio solo afecta nuevas descargas. Las pistas ya registradas en la base de streamrip pueden omitirse si se vuelven a solicitar.

## Uso

Abrir **Super + D → Streamrip**, o ejecutar `streamrip-menu` desde una terminal. El menú conserva la salida de streamrip para revisar errores y actualiza MPD al terminar las descargas.

La ventana abierta desde el lanzador va a `3:music`. En ncmpcpp, presionar **2** para explorar la carpeta `streamrip`; **u** actualiza la biblioteca manualmente. MPD y ncmpcpp deben apuntar a `~/Música`.

También se puede usar la terminal:

```sh
rip search deezer track 'artista y canción'
rip search deezer album 'nombre del álbum'
rip url 'https://www.deezer.com/album/NUMERO'
mpc update
```

## Verificación realizada

- Inicio de sesión con la cuenta de Deezer correcto, sin imprimir la cookie.
- MPD indexó la descarga inicial y quedó disponible para ncmpcpp.
- Configuración de MP3 a 320 kbps guardada y comprobada.
- Menú probado por el usuario; sintaxis Bash y archivos desktop validados.
- Configuración de Sway validada y recargada con las reglas de Streamrip.
