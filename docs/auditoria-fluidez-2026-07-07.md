# Auditoria de fluidez - 2026-07-07

Objetivo: buscar mejoras de fluidez y menor trabajo en segundo plano para la
Conectar Igualdad SF20GM7 con Arch Linux, Sway y Waybar.

## Base observada

- CPU: Intel Celeron N4020, 2 nucleos, sin SMT.
- GPU: Intel UHD Graphics 600 con driver `i915`.
- RAM: 7.6 GiB, con ~6.8 GiB disponible durante la auditoria.
- Swap: zram de 3.8 GiB, prioridad 100.
- Disco: SSD SATA 512 GB, root ext4 con ~5% usado.
- Kernel: `linux-zen` 7.1.2.
- Arranque: 22.269s total; `graphical.target` a 7.060s.
- Servicios fallidos: ninguno en sistema ni en usuario.

## Cambios aplicados

### Firefox / video

- Se instalaron `intel-media-driver`, `intel-gmmlib` y `libva-utils`.
- `vainfo` valida VA-API en Wayland con Intel iHD 26.1.5.
- Perfiles de decode disponibles: H264, VP8, VP9, HEVC, entre otros.
- Dark Reader quedo deshabilitado en el perfil activo de Firefox.

Impacto esperado: menos CPU en video y paginas pesadas; mejora ya percibida.

### Waybar musica

- Se evaluo subir el sondeo de 2s a 5s, pero se dejo en 2s porque la respuesta
  inmediata del modulo musica es preferible en el uso diario.
- El costo en este equipo no justifica degradar la experiencia del indicador.

### Wi-Fi regulatory database

- Se instalo `wireless-regdb`.
- Se agrego `wireless-regdb` a `docs/pkglist-pacman.txt`.
- La instalacion regenero initramfs correctamente.

Impacto esperado: resolver el warning `Direct firmware load for regulatory.db
failed`; no es una mejora directa de fluidez, pero deja Wi-Fi mas completo.

## Estado sano

- TLP activo y aplicando perfil `balanced/BAT`.
- zram configurado con `zram-size = ram / 2`, `zstd` y `vm.swappiness=100`.
- `/tmp` en tmpfs.
- `/` montado con `rw,relatime`.
- No hay paquetes huerfanos (`pacman -Qtdq` sin salida).
- Journal en 139.2 MiB, sin presion de disco.
- `mpd` consume muy poco CPU en reposo.
- `onedrive` sincroniza correctamente y sin errores, cada 300s.

## Candidatos no aplicados

### OneDrive en modo menos residente

Estado actual:

- `onedrive.service` esta habilitado como servicio de usuario.
- Corre en monitor, usa WebSocket y sincroniza cada 300s.
- RSS observado: ~34 MiB.

Opcion de ahorro:

- Deshabilitar monitor continuo.
- Usar sincronizacion manual o un timer cada 15/30/60 minutos.

Tradeoff: menos consumo de fondo, pero cambios remotos/locales tardan mas en
sincronizarse.

Decision: no aplicar. Se prefiere monitoreo continuo y subida casi inmediata.

### MPD bajo demanda

Estado actual:

- `mpd.service` esta habilitado como servicio de usuario.
- RSS observado: ~54 MiB.
- CPU historica baja.

Opcion de ahorro:

- Deshabilitar `mpd.service` y arrancarlo al abrir `ncmpcpp` o al usar musica.

Tradeoff: menos memoria residente, pero peor integracion inmediata con Waybar y
controles de musica.

Decision: no aplicar. La mejora no es significativa frente a mantener la
integracion musical lista.

### Accesibilidad AT-SPI

Estado actual:

- `at-spi-dbus-bus.service` y `at-spi2-registryd` estan activos.
- RSS combinado bajo, alrededor de 14 MiB.

Opcion de ahorro:

- Exportar `NO_AT_BRIDGE=1` en la sesion si no se usan lectores de pantalla ni
herramientas de accesibilidad.

Tradeoff: puede romper integracion de accesibilidad o apps GTK que esperan el
bus AT-SPI.

### Pacman cache

Estado actual:

- `/var/cache/pacman/pkg`: ~2.1 GiB.
- Hay mucho espacio libre, asi que no afecta fluidez.

Opcion:

- Limpiar cache con `paccache` si se necesita espacio.

## Warnings observados

- `i915`: `conflict detected with stolen region`. Se observo como warning de
kernel; no se aplico cambio porque el escritorio funciona y tocar parametros de
GPU sin sintoma claro puede empeorar estabilidad.
- `NetworkManager`: warning temporal en `p2p-dev-wlo2`. No requiere accion si
la red funciona.
- `mako`: warning de nombre D-Bus del service. Inocuo con mako corriendo.
- `wireplumber`: warning inicial al consultar UPower antes de estar disponible.
Inocuo.

## Verificaciones usadas

```sh
systemd-analyze
systemd-analyze blame --no-pager
systemd-analyze critical-chain --no-pager
systemctl --failed
systemctl --user --failed
systemctl --type=service --state=running
systemctl --user --type=service --state=running
ps -eo pid,ppid,comm,%cpu,%mem,rss,args --sort=-rss
free -h
swapon --show
lsblk -o NAME,TYPE,SIZE,FSTYPE,FSUSED,FSAVAIL,FSUSE%,MOUNTPOINTS,MODEL
vainfo
tlp-stat -s -p -c
journalctl -b -p warning --no-pager
journalctl --user -b -p warning --no-pager
```
