# Impala + iwd

Impala reemplaza a `nmtui` como interfaz de terminal para administrar Wi-Fi.
Impala se comunica directamente con iwd, por lo que NetworkManager debe
permanecer deshabilitado para evitar que ambos servicios controlen la misma
interfaz.

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
apunta `/etc/resolv.conf` a su stub, deshabilita `NetworkManager.service` y
habilita `iwd.service`. La conexión puede interrumpirse brevemente durante el
cambio de servicio.

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

NetworkManager debe aparecer inactivo y deshabilitado.

## Recuperación con NetworkManager

NetworkManager permanece instalado para permitir una vuelta manual si iwd no
puede establecer la conexión:

```sh
sudo systemctl disable --now iwd.service
sudo systemctl enable --now NetworkManager.service
```

Después de recuperar conectividad con NetworkManager se puede revisar el estado
de iwd y repetir `./restore.sh --iwd` cuando corresponda.
