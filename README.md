# Conectar Igualdad + Sway

Un escritorio liviano, cuidado y reproducible para Arch Linux, nacido en una
netbook Conectar Igualdad SF20GM7.

El repositorio reúne mi configuración diaria de Sway y las herramientas que la
acompañan: una Waybar informativa, menús simples, música, gestión de discos,
ahorro de energía y servicios de sesión supervisados por systemd. Sigue siendo
mi respaldo personal, pero está organizado y documentado para que otras
personas puedan recorrerlo, reutilizar una parte o instalar el entorno completo.

![Escritorio Sway + Waybar](docs/media/escritorio.png)

## Qué vas a encontrar

- **Sway modular**, con atajos y aplicaciones distribuidas por espacios de trabajo.
- **Waybar compacta**, con música, reloj, Bluetooth, red, audio, brillo, batería,
  discos externos y controles de energía.
- **Menús con fuzzel y foot** para redes, Bluetooth, audio, energía y discos.
- **Sesión mantenible**, con Waybar, Mako, swayidle, polkit y utilidades bajo
  unidades de `systemd --user`.
- **Música y archivos**, con MPD/ncmpcpp, PyRadio, mpv y Yazi tematizados.
- **Respaldo y restauración**, con vista previa, copia de seguridad automática,
  rollback y verificaciones posteriores.
- **Piezas opcionales de sistema**, como polkit, iwd, nftables, OpenSSH,
  systemd-boot y ajustes conservadores del kernel.

La estética combina Catppuccin Mocha con Lexend y glifos Nerd Font. El objetivo
no es llenar la pantalla de información, sino mostrar lo útil sin distraer.

## Antes de instalar

Este no es un paquete universal ni una distribución. Es un conjunto de dotfiles
para **Arch Linux + Sway** que refleja decisiones personales y el hardware donde
se desarrolló.

Conviene revisar especialmente:

- los nombres y reglas de workspaces;
- las carpetas XDG en español y la biblioteca `~/Música`;
- la interfaz y el dominio regulatorio de iwd;
- la red confiable `192.168.1.0/24` usada por nftables;
- las entradas de systemd-boot;
- cualquier configuración de SSH antes de aplicarla.

No se incluyen contraseñas, tokens, claves privadas, perfiles Wi-Fi, sesiones de
navegador ni claves SSH autorizadas. OneDrive también requiere vincular la cuenta
localmente después de restaurar.

## Instalación recomendada

### 1. Clonar y revisar

```sh
git clone https://github.com/massisalva/conectar-igualdad-sway.git
cd conectar-igualdad-sway
./restore.sh --help
```

Para ver los cambios sobre tu `$HOME` sin escribir archivos:

```sh
./restore.sh --dry-run
```

### 2. Restaurar solo el entorno de usuario

Este es el punto de partida más seguro. Copia `home/` sobre tu directorio
personal, ajusta los permisos de los scripts e instala los complementos de Yazi
si `ya` ya está disponible:

```sh
./restore.sh
```

Cada archivo reemplazado se guarda antes en `backups/restore-*`. Al terminar,
podés comprobar el resultado con:

```sh
./check.sh
```

Después iniciá Sway nuevamente o recargá su configuración con `Mod+Shift+c`.

### 3. Instalar paquetes, si los necesitás

Las listas reproducibles están en `docs/pkglist-pacman.txt` y
`docs/pkglist-aur.txt`. Se pueden aplicar por separado:

```sh
./restore.sh --packages
./restore.sh --aur
```

La segunda opción necesita `yay` instalado. Ambas listas representan este
entorno completo; revisalas si solo querés adoptar una parte de la configuración.
Ejecutá `restore.sh` como tu usuario normal (sin `sudo`): el script solicita
privilegios solo para los pasos que los requieren.

### 4. Aplicar cambios del sistema de forma explícita

Las piezas que requieren privilegios no se instalan durante la restauración
normal. Cada una tiene su propia opción:

```sh
./restore.sh --polkit
./restore.sh --iwd
./restore.sh --nftables
./restore.sh --sshd
./restore.sh --sysctl
./restore.sh --zram
./restore.sh --bootloader
```

`--zram` instala la configuración, pero el generador de systemd la aplica de
forma más segura en el próximo reinicio. No reinicia automáticamente la unidad
en caliente, porque eso puede desplazar temporalmente páginas de la swap.

No recomiendo usar `--all` en otra máquina sin haber revisado antes esas
configuraciones. Para inspeccionar el conjunto completo sin aplicarlo:

```sh
./restore.sh --all --dry-run
```

Si ya adaptaste todo a tu equipo:

```sh
./restore.sh --all
./check.sh --system --sudo
```

## Volver atrás

Cada restauración crea un respaldo con manifiesto. Para recuperar el estado
anterior de los archivos:

```sh
./restore.sh --rollback backups/restore-AAAAMMDD-HHMMSS-PID
```

El rollback restaura archivos; si alcanzó una configuración del sistema, puede
ser necesario recargar o reiniciar el servicio correspondiente.

Los scripts antiguos de `~/.local/bin` se conservan por defecto. Se pueden
detectar y quitar, siempre con respaldo previo, mediante:

```sh
./restore.sh --prune --dry-run
./restore.sh --prune
```

## Mapa del repositorio

| Ruta | Contenido |
| --- | --- |
| `home/` | Archivos que se restauran sobre `$HOME` |
| `home/.config/` | Configuración de Sway, Waybar, foot, fuzzel, Mako, Yazi y otras aplicaciones |
| `home/.local/bin/` | Scripts que implementan menús, módulos y comportamiento de la sesión |
| `polkit/` | Reglas locales para discos y energía |
| `iwd/` | Wi-Fi con iwd, Impala y systemd-resolved |
| `nftables/` | Firewall local y acceso desde la LAN confiable |
| `sshd/` | Endurecimiento conservador de OpenSSH |
| `sysctl/` | Ajustes locales del kernel y swappiness |
| `zram/` | Configuración de zram-generator para swap comprimido |
| `bootloader/` | Ejemplos de systemd-boot para revisión manual |
| `docs/` | Inventario, decisiones, auditorías, paquetes y notas de recuperación |
| `tests/` | Pruebas de restauración y scripts de interfaz |

## Verificación y mantenimiento

La comprobación habitual es:

```sh
./check.sh
```

Además de comparar los archivos activos con el repositorio, valida scripts,
JSON de Waybar, dependencias, procesos duplicados, paquetes huérfanos y las
pruebas automatizadas.

Para incluir archivos protegidos y el estado efectivo de servicios del sistema:

```sh
./check.sh --system --sudo
```

Ese modo también revisa SSH, nftables, unidades fallidas, errores del arranque,
puertos TCP en escucha y el estado SMART del disco raíz.

## Notas de uso

- La configuración de OneDrive limita la sincronización a `02 - Linux`, pero no
  guarda credenciales. La cuenta se vincula ejecutando `onedrive` y el servicio
  se habilita con `systemctl --user enable --now onedrive.service`.
- Las claves reales de `authorized_keys` quedan fuera del repositorio. Solo se
  incluye `home/.ssh/authorized_keys.example`.
- El firewall permite LocalSend y SSH únicamente desde la LAN configurada. Hay
  más contexto en `nftables/README.md`.
- La migración a iwd y sus pasos de recuperación están documentados en
  `iwd/README.md`.
- Las decisiones de alcance y los datos que deliberadamente no se versionan se
  explican en `docs/decisiones.md`.

## Adaptarlo y compartir mejoras

Podés tomar el repositorio completo o copiar solo las partes que te resulten
útiles. Para una instalación propia, lo más razonable es hacer un fork, cambiar
las preferencias ligadas al equipo y comenzar con `--dry-run`.

Si encontrás una mejora generalizable, una corrección o una forma más clara de
documentar algo, los issues y pull requests son bienvenidos.

---

Hecho para prolongar la vida útil de una netbook sencilla y mantener un entorno
que pueda reconstruirse sin depender de la memoria.
