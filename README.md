# Conectar Igualdad SF20GM7 - Sway + Waybar

Configuración personal de Arch Linux en una netbook Conectar Igualdad SF20GM7.

## Vista

![Escritorio Sway + Waybar](docs/media/escritorio.png)

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

- `home/`: archivos que se restauran sobre `$HOME`.
- `home/.config/`: configuración de aplicaciones de usuario.
- `home/.local/bin/`: scripts locales ejecutables.
- `polkit/`: reglas de polkit para copiar con permisos de sistema.
- `bootloader/`: archivos de systemd-boot para revisar/restaurar manualmente.
- `sshd/`: hardening conservador de OpenSSH.
- `nftables/`: firewall local conservador.
- `iwd/`: configuración del gestor de Wi-Fi usado por Impala.
- `docs/`: inventario, decisiones y listas de paquetes.
- `docs/media/`: capturas o material visual para documentación.

## Características principales

- Configuración modular de Sway.
- Waybar con módulos de música, Caps Lock, discos, CPU, memoria, Bluetooth, red, audio, brillo, batería y energía.
- Menús flotantes con foot y fuzzel.
- Notificaciones con mako.
- Manejo de dispositivos externos/removibles con disk-manager, disk-status y disk-notify.
- Power menu con bloqueo, suspensión, reinicio, apagado y salida de Sway.
- Ahorro de energía que apaga la pantalla y evita suspender mientras hay audio activo.
- Reglas polkit para discos y energía local.
- SSH con hardening conservador; las claves autorizadas no se versionan.
- Firewall local con nftables para limitar entrada y SSH desde la LAN.
- Impala con iwd para gestionar Wi-Fi desde una interfaz de terminal.
- systemd-boot ajustado con console-mode max.
- Scripts locales con validación básica de dependencias y fallos no fatales de notificación.
- Verificador local para restauración, paquetes, scripts, Yazi, XDG, polkit y bootloader.
- Yazi con Catppuccin Mocha, plugins oficiales y previews de texto/metadata.
- Papelera XDG para Yazi con `d` para enviar a papelera y `D` para borrado permanente.
- Carpetas XDG del usuario registradas en español.
- OneDrive con cliente `onedrive-abraunegg` y configuración local segura.
- MPD/ncmpcpp local con PipeWire, visualizador FIFO y biblioteca en `~/Música`.

## Restauración

- Paquetes pacman actuales: `docs/pkglist-pacman.txt`
- Paquetes AUR actuales: `docs/pkglist-aur.txt`
- Configuración de usuario versionada bajo `home/`.
- Configuración de sistema versionada bajo `polkit/` y `bootloader/`.
- Hardening de SSH versionado bajo `sshd/`.
- Firewall nftables versionado bajo `nftables/`.

Ver criterios de alcance y qué se versiona en `docs/decisiones.md`.

Restauración de usuario:

```sh
./restore.sh
```

Restauración completa:

```sh
./restore.sh --all
```

Antes de aplicar cambios se puede revisar qué haría:

```sh
./restore.sh --all --dry-run
```

Verificación del estado restaurado:

```sh
./check.sh
```

Para exigir también polkit y bootloader como obligatorios:

```sh
./check.sh --system
```

Para permitir que la verificación pida contraseña de sudo y compare archivos protegidos:

```sh
./check.sh --system --sudo
```

Aplicar hardening de SSH:

```sh
./restore.sh --sshd
```

La configuración deja `PasswordAuthentication no`; el acceso por clave se gestiona en `~/.ssh/authorized_keys` fuera del repo.

Las claves autorizadas reales no se guardan en el repo. Hay un ejemplo en
`home/.ssh/authorized_keys.example`.

Aplicar firewall local:

```sh
./restore.sh --nftables
```

La configuración permite salida normal y SSH solo desde `192.168.1.0/24`.
Si cambia la red de confianza, ajustar `nftables/nftables.conf` antes de instalar.

Configurar Impala con iwd:

```sh
./restore.sh --iwd
```

El cambio deshabilita NetworkManager, habilita iwd y systemd-resolved, y puede
interrumpir brevemente la conexión Wi-Fi. Las redes se administran luego con
Impala desde Waybar o ejecutando `impala`. La aplicación, verificación y
recuperación con NetworkManager se detallan en `iwd/README.md`.

## Post-restauración

Después de restaurar una instalación nueva:

```sh
./restore.sh --all
./check.sh
```

Si se restauran reglas de sistema, verificar con:

```sh
./check.sh --system --sudo
```

Reiniciar Sway o ejecutar `Mod+Shift+c` para recargar la configuración de la
sesión gráfica.

## OneDrive

La configuración versionada en `home/.config/onedrive/config` solo ajusta opciones seguras del cliente. No se versionan tokens, bases SQLite ni credenciales.

La sincronización está limitada por `home/.config/onedrive/sync_list` a la carpeta remota:

```text
02 - Linux
```

Después de restaurar, vincular la cuenta:

```sh
onedrive
```

Habilitar sincronización automática:

```sh
systemctl --user enable --now onedrive.service
```

El repo incluye un override de usuario para quitar la espera fija de 15s del unit del paquete. Si se modifica esa configuración, recargar systemd:

```sh
systemctl --user daemon-reload
systemctl --user restart onedrive.service
```

Consultar el estado:

```sh
systemctl --user status onedrive.service
journalctl --user -u onedrive.service -f
```

## Notas

Esta configuración está pensada para uso personal en la netbook conectar-igualdad.

No incluye backups, claves privadas, tokens, credenciales ni claves SSH
autorizadas personales.

Los backups manuales de auditoría se guardan fuera del historial Git y están ignorados mediante `backups/`.
