# Decisiones de configuración

Este repositorio guarda la parte reproducible del entorno personal de la
Conectar Igualdad SF20GM7. No intenta ser una copia completa de `$HOME`.

## Qué se versiona

- Configuración de Sway, Waybar, fuzzel, mako, MPD/ncmpcpp, mpv, PyRadio,
  OneDrive, Yazi y carpetas XDG.
- Scripts locales en `~/.local/bin` que forman parte de la sesión.
- Launchers locales en `~/.local/share/applications` cuando corrigen
  comportamiento, asignan workspaces o limpian fuzzel.
- Reglas de polkit, systemd-boot y sshd que requieren instalación explícita.
- Listas de paquetes necesarias o recomendadas para reconstruir el entorno.

## Qué no se versiona

- Tokens, bases SQLite, cookies, perfiles de navegador y estado de aplicaciones.
- Claves privadas o material sensible.
- Claves públicas personales en `authorized_keys`.
- Caches, logs y datos que cambian por uso normal.

## Sway y workspaces

Las terminales se diferencian por `app_id` de foot. Sway usa regex para
comparar `app_id`, por eso las reglas deben estar ancladas con `^...$`.

- `foot-term` y `foot` van a `1:term`.
- `firefox` va a `2:web`.
- `foot-music-*` va a `3:music`.
- `foot-files` va a `4:files`.
- `foot-system` va a `5:system`.

Los launchers de ncmpcpp, ncspot, PyRadio, Yazi y el gestor de discos abren
foot con el `app_id` correspondiente para que fuzzel no dependa del escritorio
actual. Evitar rutas absolutas al usuario en archivos `.desktop`; usar binarios
de `/usr/bin` cuando sea posible.

`waybar` y `mako` se levantan como units de `systemd --user` para aprovechar
sus reinicios y mantener el autostart de Sway centrado en la sesión gráfica.

## Waybar

Waybar prioriza estado útil sin ruido visual:

- música activa;
- reloj;
- Caps Lock solo cuando está activo;
- discos externos;
- CPU, memoria, Bluetooth, red, audio, brillo, batería y energía.

Los scripts de Waybar deben ser livianos y tolerar fallos de DBus o servicios
externos sin cortar la barra.

## Fuzzel

fuzzel se usa como lanzador principal. Los `.desktop` locales cumplen dos
funciones:

- ocultar utilidades que no conviene mostrar en el lanzador;
- reemplazar entradas de terminal para asignar `app_id` y workspaces.

## Restauración

`restore.sh` copia `home/` sobre `$HOME`, ajusta permisos de scripts y prepara
directorios esperados. Las piezas de sistema se instalan solo con flags
explícitos: `--polkit`, `--bootloader` y `--sshd`.

`check.sh` valida que lo versionado y lo instalado coincidan. Para archivos de
sistema protegidos, usar `./check.sh --system --sudo`.
