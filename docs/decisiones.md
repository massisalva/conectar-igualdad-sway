# Decisiones de configuración

Este repositorio guarda la parte reproducible del entorno personal de la
Conectar Igualdad SF20GM7. No intenta ser una copia completa de `$HOME`.

## Qué se versiona

- Configuración de Sway, Waybar, fuzzel, mako, MPD/ncmpcpp, mpv, PyRadio,
  OneDrive, Yazi y carpetas XDG.
- Scripts locales en `~/.local/bin` que forman parte de la sesión.
- Launchers locales en `~/.local/share/applications` cuando corrigen
  comportamiento, asignan workspaces o limpian fuzzel.
- Reglas de polkit, systemd-boot, sshd y nftables que requieren instalación explícita.
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

`sway-session.target` representa la sesión gráfica y activa Waybar, Mako,
swayidle, el agente polkit, udiskie y disk-notify como units de `systemd --user`.
Cada proceso obtiene reinicio y logs independientes. `sway-autostart` importa el
entorno gráfico, inicia el target y lo detiene al recibir el evento de cierre de
Sway.

## Inactividad, pantalla y audio

`start-idle` mantiene separados el ahorro de pantalla y la suspensión del
equipo: bloquea la sesión a los 10 minutos, apaga las salidas mediante DPMS a
los 11 minutos y evalúa la suspensión a los 30 minutos de inactividad.

La suspensión automática se delega a `suspend-if-no-audio`. El script consulta
con `pactl` las entradas de audio de PipeWire-Pulse y solo ejecuta
`systemctl suspend` cuando ninguna está reproduciéndose (`Corked: no`). De este
modo la pantalla puede permanecer apagada sin cortar una radio, música o video.
Una reproducción pausada no impide la suspensión.

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
explícitos: `--polkit`, `--bootloader`, `--sshd` y `--nftables`.

`check.sh` valida que lo versionado y lo instalado coincidan. Para archivos de
sistema protegidos, usar `./check.sh --system --sudo`.

## Firewall

El firewall local se versiona como `/etc/nftables.conf` y se instala de forma
explícita. La política base bloquea entrada y forwarding, permite salida,
loopback, conexiones establecidas, ICMP/ICMPv6 básico y DHCP cliente.

SSH queda permitido solo desde `192.168.1.0/24`, porque la auditoría de red
mostró `sshd` escuchando en todas las interfaces y sin firewall activo.

LocalSend queda permitido en TCP/UDP 53317 solo desde `192.168.1.0/24`. La
salida continúa abierta y ningún puerto de LocalSend se expone fuera de la LAN
confiable.

## Wi-Fi

Impala reemplaza a nmtui como interfaz de gestión y se abre desde el módulo de
red de Waybar. Como Impala se comunica directamente con iwd, iwd administra la
interfaz Wi-Fi sin una segunda pila de gestión de red.

iwd usa su configuración de red integrada para DHCP y entrega el DNS a
systemd-resolved. Los perfiles de `/var/lib/iwd` contienen secretos y no se
versionan. NetworkManager y `tlp-rdw` se retiran: el complemento RDW no tenía
reglas configuradas y depende de NetworkManager. TLP permanece instalado para
la gestión general de energía.

El dominio regulatorio se fija en `AR` para evitar el estado global genérico
`00` y el fallo del helper `set-wireless-regdom` cuando la variable queda vacía.

## Endurecimiento local

`kernel.kptr_restrict=1` oculta direcciones del kernel a usuarios sin
privilegios. El ajuste se versiona en `sysctl/99-local-hardening.conf` y se
instala explícitamente mediante `./restore.sh --sysctl`.
