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

[filepaths]
add_singles_to_folder = true
folder_format = "{albumartist} - {title} ({year})"
```

Reemplazar `TU_USUARIO` por el usuario local. Crear la carpeta y proteger el archivo:

```sh
mkdir -p "$HOME/Música/streamrip"
chmod 600 "$HOME/.config/streamrip/config.toml"
```

Agregar la cookie `arl` de la propia cuenta directamente en el archivo local siguiendo la [guía de streamrip](https://github.com/nathom/streamrip/wiki/Finding-Your-Deezer-ARL-Cookie). Es una credencial de sesión y queda fuera de Git.

`quality = 1` solicita MP3 de 320 kbps según el acceso de la cuenta. El cambio solo afecta nuevas descargas. Las pistas ya registradas en la base de streamrip pueden omitirse si se vuelven a solicitar; para forzar su re-descarga se puede activar la opción **8** (`--no-db`) en `streamrip-menu` o pasar `rip --no-db ...` por terminal.

`restore.sh` asegura la carpeta `~/Música/streamrip`, endurece `~/.config/streamrip/config.toml` a permisos `600` si existe y preserva `~/.local/bin/rip` durante `--prune` (`docs/local-bin-keep.txt`).

## Uso

Abrir **Super + D → Streamrip**, o ejecutar `streamrip-menu` desde una terminal. El menú recorta espacios al pegar, acepta enlaces de `deezer.com` y `deezer.page.link`, resuelve con `curl` los enlaces cortos de "Compartir" (`link.deezer.com/s/...`) que streamrip no reconoce, limpia la vista entre operaciones (conservando el scrollback de la terminal), actualiza MPD al terminar las descargas y envía una notificación de escritorio vía Mako.

La ventana abierta desde el lanzador va a `3:music`. En ncmpcpp, presionar **2** para explorar la carpeta `streamrip`; **u** actualiza la biblioteca manualmente. MPD y ncmpcpp deben apuntar a `~/Música`.

También se puede usar la terminal:

```sh
rip search deezer track 'artista y canción'
rip search deezer album 'nombre del álbum'
rip url 'https://www.deezer.com/album/NUMERO'
rip --no-db url 'https://www.deezer.com/album/NUMERO'
mpc update
```

## Verificación realizada

- Inicio de sesión con la cuenta de Deezer correcto, sin imprimir la cookie.
- MPD indexó la descarga inicial y quedó disponible para ncmpcpp.
- Configuración de MP3 a 320 kbps guardada y comprobada.
- Menú probado por el usuario; sintaxis Bash y archivos desktop validados.
- Configuración de Sway validada y recargada con las reglas de Streamrip.

## Cambios

### 2026-11-16: enlaces cortos y carpetas por álbum

- **Enlaces `link.deezer.com`:** streamrip 2.1.0 solo reconoce `www|open|play|listen.deezer.com` y `deezer.page.link`. El menú aceptaba cualquier `*.deezer.com` y `rip` fallaba con los enlaces de "Compartir". Ahora `streamrip-menu` sigue la redirección con `curl`, quita los parámetros de seguimiento (`?utm_...`) y solo llama a `rip` si el destino es una canción, álbum, artista o playlist. Si el enlace está roto (Deezer redirige a `/deezer-links-404`), avisa y no descarga.
- **Carpetas:** `add_singles_to_folder = true` y `folder_format = "{albumartist} - {title} ({year})"`. Las canciones sueltas van a la carpeta de su álbum en lugar de quedar mezcladas, y el nombre ya no lleva `[MP3] [16B-44.1kHz]`. Solo afecta a las descargas nuevas; los archivos anteriores quedan donde estaban.
- **Copia previa:** `backups/manual-20261116-streamrip/` (no se versiona): `streamrip-menu`, `config.toml` (permisos 600, contiene la cookie) y el commit anterior.
- **Deshacer:**

  ```sh
  cd ~/Proyectos/conectar-igualdad-sway
  git revert "$(git log --format=%h -1 --grep='resolver enlaces cortos de Deezer')"
  install -m 755 home/.local/bin/streamrip-menu ~/.local/bin/streamrip-menu
  cp -p backups/manual-20261116-streamrip/config.toml ~/.config/streamrip/config.toml
  ```
