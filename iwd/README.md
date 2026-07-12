# Impala + iwd

Impala reemplaza a `nmtui` como interfaz de terminal para administrar Wi-Fi.
Impala se comunica directamente con iwd. NetworkManager no forma parte de esta
instalación, evitando mantener dos pilas que puedan controlar la misma interfaz.

## Componentes

- `impala`: interfaz TUI que se abre desde el módulo de red de Waybar.
- `iwd`: administra la interfaz, las redes Wi-Fi y DHCP.
- `systemd-resolved`: recibe de iwd los servidores DNS de la conexión.
- `main.conf`: habilita la configuración de red integrada de iwd y su
  integración con systemd-resolved.

Los perfiles creados al conectarse se guardan en `/var/lib/iwd`. Pueden incluir
contraseñas y no se copian ni versionan en este repositorio.

## Aplicación

Primero deben estar instalados los paquetes `impala` e `iwd`. La restauración
completa los cambios de sistema con:

```sh
./restore.sh --iwd
```

Este paso instala `/etc/iwd/main.conf`, habilita `systemd-resolved.service`,
apunta `/etc/resolv.conf` a su stub y habilita `iwd.service`.

Después se puede abrir el módulo de red de Waybar o ejecutar:

```sh
impala
```

## Verificación

La configuración versionada y el estado de los servicios se verifican con:

```sh
./check.sh --system --sudo
```

Para una comprobación manual:

```sh
systemctl is-active iwd.service systemd-resolved.service
systemctl is-enabled iwd.service systemd-resolved.service
iwctl station list
resolvectl status
```

`check.sh` también confirma que NetworkManager y `tlp-rdw` no estén instalados.
TLP permanece instalado; solo se retira RDW porque depende de NetworkManager y
no hay reglas de radio configuradas que lo necesiten.

## Recuperación

Si Impala no puede establecer una conexión, se puede usar directamente la CLI
de iwd:

```sh
iwctl device list
iwctl station wlan0 scan
iwctl station wlan0 get-networks
iwctl station wlan0 connect NOMBRE_DE_RED
```

Los perfiles conocidos permanecen en `/var/lib/iwd`, por lo que reiniciar iwd o
el equipo normalmente restaura automáticamente la conexión. Si fuera necesario
volver a NetworkManager, se puede reinstalar y cambiar los servicios manualmente:

```sh
sudo pacman -S networkmanager
sudo systemctl disable --now iwd.service
sudo systemctl enable --now NetworkManager.service
```
