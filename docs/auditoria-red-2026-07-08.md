# Auditoria de red hogarenia - 2026-07-08

## Alcance

Auditoria defensiva de la LAN hogarenia desde Arch Linux en la notebook
Conectar Igualdad.

Topologia declarada:

- Fibra optica.
- Router Huawei.
- TP-Link Deco mesh.
- Raspberry Pi con Pi-hole y servicios Docker.
- Auditoria ejecutada desde Arch Linux.

No se hicieron pruebas ofensivas, fuerza bruta ni intentos de evasion. La
revision fue desde dentro de la LAN. La exposicion desde Internet/WAN debe
confirmarse aparte desde el router o desde una red externa.

## Red observada

- Subred LAN: `192.168.1.0/24`
- Arch/notebook: `192.168.1.49`
- Gateway: `192.168.1.1`
- DNS entregado por DHCP: `192.168.1.2`
- Raspberry/Pi-hole: `192.168.1.2`
- Wi-Fi activo: `Huawei-08WT`
- Seguridad Wi-Fi observada: WPA2
- Enlace Wi-Fi de la notebook: 5 GHz, canal 40, senial fuerte.
- IPv6 en la notebook: solo link-local, sin ruta por defecto IPv6 observada.

## Dispositivos principales

| IP | MAC | Rol probable |
| --- | --- | --- |
| `192.168.1.1` | `9c:b2:e8:c4:26:e7` | Huawei/router/gateway |
| `192.168.1.2` | `2c:cf:67:6d:2f:b7` | Raspberry Pi / Pi-hole |
| `192.168.1.3` | `74:da:88:7b:6c:c8` | TP-Link Deco/AP |
| `192.168.1.15` | `74:da:88:7b:6c:60` | TP-Link Deco/AP |
| `192.168.1.6` | `ec:be:dd:c8:27:bf` | Sagemcom Broadband / deco Flow probable |
| `192.168.1.49` | `08:9d:f4:d3:3b:5f` | Arch/notebook |
| `192.168.1.59` | `66:99:46:c3:40:3d` | Mac mini probable |

Otros hosts vistos durante la auditoria:

- `192.168.1.20`
- `192.168.1.24`
- `192.168.1.29`
- `192.168.1.88`
- `192.168.1.89`

## Hallazgos iniciales

### Raspberry Pi

Puertos TCP abiertos antes de ajustes:

- `22`: SSH
- `53`: Pi-hole/dnsmasq
- `80`, `443`: Pi-hole web
- `111`: rpcbind
- `3000`: Homepage
- `3001`: Uptime Kuma
- `5900`: VNC/wayvnc
- `8096`: Jellyfin
- `9443`: Portainer
- `9999`: Dozzle
- `32400`: Plex
- `51821`: wg-easy admin UI

Servicios Docker activos:

| Contenedor | Funcion | Puerto publicado |
| --- | --- | --- |
| `pihole` | DNS / Pi-hole web | host network |
| `plex` | Plex Media Server | host network |
| `jellyfin` | Jellyfin | `8096` |
| `homepage` | dashboard | `3000` |
| `uptime-kuma` | monitoreo | `3001` |
| `portainer` | administracion Docker | `9443` |
| `dozzle` | logs Docker | `9999` |
| `wg-easy` | WireGuard + panel | `51820/udp`, `51821/tcp` |
| `duckdns` | actualizacion DNS dinamico | sin puerto publicado |
| `watchtower` | actualizaciones contenedores | sin puerto publicado |

Servicios systemd relevantes:

- `ssh.service`
- `wayvnc.service`
- `wayvnc-control.service`
- `rpcbind.service`
- `rpcbind.socket`
- `docker.service`
- `avahi-daemon.service`
- `cups.service`

Interpretacion:

- La Raspberry era el activo con mayor superficie interna.
- Muchos paneles administrativos estaban accesibles desde cualquier equipo de
  la LAN.
- VNC se mantiene porque se usa ocasionalmente.
- Plex y Jellyfin se mantienen accesibles a toda la LAN porque son servicios de
  consumo.

### Huawei / gateway

Puertos relevantes:

- `53/tcp`, `53/udp`: DNS con recursion activa.
- `80/tcp`: panel HTTP local.
- `27998/tcp`, `37443/tcp`, `37444/tcp`: servicios altos del router.
- `1900/udp`: `open|filtered` para UPnP/SSDP.

Pendiente:

- Revisar desde panel Huawei si UPnP esta activo.
- Revisar port forwards.
- Confirmar administracion remota WAN desactivada.
- Confirmar WPS desactivado.

### Sagemcom / deco Flow probable (`192.168.1.6`)

Puertos relevantes:

- `7547/tcp`: SOAP/CWMP/TR-069
- `7878/tcp`
- `49152/tcp`: UPnP
- `50000/tcp`: `lighttpd/1.4.45`
- `56789/tcp`, `56790/tcp`
- `1900/udp`: `open|filtered`

Interpretacion:

- Probablemente es un deco Flow/Sagemcom del proveedor.
- Los puertos observados son compatibles con un equipo administrado por ISP.
- No se bloqueo ni modifico para evitar romper TV/IPTV/servicios del proveedor.
- Los puertos especificos no aparecieron abiertos en la IP publica por TCP.
- Tratar como dispositivo IoT/proveedor dentro de la LAN.

### TP-Link Deco

Nodos observados:

- `192.168.1.3`
- `192.168.1.15`

Puertos:

- `80/tcp`: OpenWrt uHTTPd
- `443/tcp`
- `20001/tcp`: Dropbear SSH

Interpretacion:

- Parece exposicion interna normal del mesh.
- Debe mantenerse firmware actualizado y WPS apagado.

## Cambios aplicados

### 1. Acceso SSH a Raspberry con clave

Se instalo la clave publica local de Arch en la Raspberry:

```bash
ssh-copy-id massisalva@192.168.1.2
```

Luego se valido acceso no interactivo:

```bash
ssh -o BatchMode=yes massisalva@192.168.1.2 'hostname; id; uname -a'
```

Resultado:

- Hostname: `raspberrypi`
- Sistema: Debian GNU/Linux 13 trixie
- Kernel: `6.18.33+rpt-rpi-2712`
- Usuario `massisalva` pertenece a `sudo` y `docker`.

### 2. Deshabilitado `rpcbind`

Motivo:

- No se observaron montajes NFS activos.
- `rpcbind` exponia `111/tcp` y `111/udp`.
- Si no hay NFS/RPC, es superficie innecesaria.

Comando aplicado:

```bash
sudo systemctl disable --now rpcbind.service rpcbind.socket
```

Validacion:

```bash
systemctl is-active rpcbind.service rpcbind.socket
nmap -sT -p 111 192.168.1.2
```

Estado posterior:

- `rpcbind.service`: `inactive`
- `rpcbind.socket`: `inactive`
- `111/tcp`: cerrado desde la LAN

Rollback:

```bash
sudo systemctl enable --now rpcbind.socket rpcbind.service
```

### 3. Hardening SSH en Raspberry

Motivo:

- SSH aceptaba clave publica y tambien contrasena.
- `PermitRootLogin` estaba en el valor efectivo `without-password`.
- `X11Forwarding` estaba activo.
- `MaxAuthTries` estaba en `6` y `LoginGraceTime` en `120`.

Se valido primero que la clave actual funcionara sin contrasena:

```bash
ssh -o BatchMode=yes \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  massisalva@192.168.1.2 'echo key-auth-ok'
```

Se creo:

```text
/etc/ssh/sshd_config.d/00-local-hardening.conf
```

Contenido:

```sshconfig
# Managed hardening - 2026-07-08
AllowUsers massisalva
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
```

Nota:

- Se intento primero un archivo `99-local-hardening.conf`, pero
  `50-cloud-init.conf` seguia dejando `PasswordAuthentication yes`.
- En esta instalacion de OpenSSH, el primer valor efectivo importo para esa
  directiva, por eso se uso `00-local-hardening.conf`.
- El archivo `99-local-hardening.conf` fue eliminado.

Validacion de configuracion efectiva:

```bash
sudo sshd -T | grep -E '^(allowusers|permitrootlogin|pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|permitemptypasswords|maxauthtries|logingracetime|x11forwarding)'
```

Resultado posterior:

```text
logingracetime 30
maxauthtries 3
permitrootlogin no
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
x11forwarding no
permitemptypasswords no
allowusers massisalva
```

Pruebas realizadas:

```bash
ssh -o BatchMode=yes \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  massisalva@192.168.1.2 'echo key-login-ok; whoami; hostname'
```

Resultado:

```text
key-login-ok
massisalva
raspberrypi
```

Prueba de password deshabilitado:

```bash
ssh -o BatchMode=yes \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o ConnectTimeout=5 \
  massisalva@192.168.1.2 'echo should-not-login'
```

Resultado esperado:

```text
Permission denied (publickey).
```

Prueba de root deshabilitado:

```bash
ssh -o BatchMode=yes root@192.168.1.2 'echo should-not-login'
```

Resultado esperado:

```text
Permission denied (publickey).
```

Rollback:

```bash
sudo rm -f /etc/ssh/sshd_config.d/00-local-hardening.conf
sudo sshd -t
sudo systemctl reload ssh.service
```

### 4. Restriccion de paneles Docker admin

Objetivo:

Permitir paneles administrativos solo desde:

- Arch/notebook: `192.168.1.49`
- Mac mini probable: `192.168.1.59`
- Clientes WireGuard: `10.8.0.0/24`

Paneles restringidos:

| Puerto | Servicio |
| --- | --- |
| `3000/tcp` | Homepage |
| `3001/tcp` | Uptime Kuma |
| `9443/tcp` | Portainer |
| `9999/tcp` | Dozzle |
| `51821/tcp` | wg-easy admin UI |

No se restringieron:

- `53`: DNS/Pi-hole
- `80`, `443`: Pi-hole web
- `8096`: Jellyfin
- `32400`: Plex
- `51820/udp`: WireGuard VPN
- `5900`: VNC
- `22`: SSH

Implementacion:

Se creo el script:

```text
/usr/local/sbin/restrict-docker-admin-panels.sh
```

Contenido logico:

- Crear/limpiar cadena `RPI-ADMIN-PANELS`.
- Para cada puerto admin:
  - permitir origen `192.168.1.49`;
  - permitir origen `192.168.1.59`;
  - bloquear el resto.
- Insertar la cadena al inicio de `DOCKER-USER`.

Se creo el servicio systemd:

```text
/etc/systemd/system/restrict-docker-admin-panels.service
```

Comandos aplicados:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now restrict-docker-admin-panels.service
```

Validacion:

```bash
sudo /usr/sbin/iptables -S DOCKER-USER
sudo /usr/sbin/iptables -S RPI-ADMIN-PANELS
sudo /usr/sbin/iptables -vnL RPI-ADMIN-PANELS
```

Resultado:

- La cadena `RPI-ADMIN-PANELS` quedo referenciada desde `DOCKER-USER`.
- Los contadores subieron para trafico desde `192.168.1.49`.
- Desde Arch los paneles siguen accesibles.

Rollback temporal:

```bash
sudo systemctl stop restrict-docker-admin-panels.service
sudo /usr/sbin/iptables -D DOCKER-USER -j RPI-ADMIN-PANELS
```

Rollback persistente:

```bash
sudo systemctl disable --now restrict-docker-admin-panels.service
sudo rm -f /etc/systemd/system/restrict-docker-admin-panels.service
sudo rm -f /usr/local/sbin/restrict-docker-admin-panels.sh
sudo systemctl daemon-reload
```

Si la cadena queda creada, se puede borrar con:

```bash
sudo /usr/sbin/iptables -F RPI-ADMIN-PANELS
sudo /usr/sbin/iptables -X RPI-ADMIN-PANELS
```

### 5. Reparacion de `wg-easy` / WireGuard

Estado encontrado:

- Contenedor `wg-easy`: `Up ... (unhealthy)`.
- Puerto publicado: `51820/udp`.
- Panel publicado: `51821/tcp`.
- `wg0` no quedaba levantado.

Error principal en logs:

```text
modprobe: FATAL: Module ip_tables not found in directory /lib/modules/6.18.33+rpt-rpi-2712
iptables v1.8.11 (legacy): can't initialize iptables table `nat'
Command failed: wg-quick up wg0
```

Causa:

- El host Raspberry usa `iptables-nft`.
- Dentro del contenedor, `iptables` apuntaba a `iptables-legacy`.
- El kernel actual no tenia disponible el modulo legacy `ip_tables`.
- `wg-quick` fallaba al aplicar NAT/firewall y eliminaba `wg0`.

Prueba temporal realizada:

```bash
docker exec wg-easy sh -lc '
update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-nft 20 \
  --slave /usr/sbin/iptables-restore iptables-restore /usr/sbin/iptables-nft-restore \
  --slave /usr/sbin/iptables-save iptables-save /usr/sbin/iptables-nft-save
update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-nft 20 \
  --slave /usr/sbin/ip6tables-restore ip6tables-restore /usr/sbin/ip6tables-nft-restore \
  --slave /usr/sbin/ip6tables-save ip6tables-save /usr/sbin/ip6tables-nft-save
update-alternatives --set iptables /usr/sbin/iptables-nft
update-alternatives --set ip6tables /usr/sbin/ip6tables-nft
'
docker restart wg-easy
```

Resultado de la prueba:

- `wg0` levanto correctamente.
- `wg-easy` paso a `healthy`.

Fix persistente:

Se creo un wrapper en:

```text
/home/massisalva/Docker/Wg-easy/wg-easy-nft-entrypoint.sh
```

Contenido:

```sh
#!/bin/sh
set -eu

update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-nft 20 \
  --slave /usr/sbin/iptables-restore iptables-restore /usr/sbin/iptables-nft-restore \
  --slave /usr/sbin/iptables-save iptables-save /usr/sbin/iptables-nft-save
update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-nft 20 \
  --slave /usr/sbin/ip6tables-restore ip6tables-restore /usr/sbin/ip6tables-nft-restore \
  --slave /usr/sbin/ip6tables-save ip6tables-save /usr/sbin/ip6tables-nft-save
update-alternatives --set iptables /usr/sbin/iptables-nft
update-alternatives --set ip6tables /usr/sbin/ip6tables-nft

exec docker-entrypoint.sh /usr/bin/dumb-init node server/index.mjs
```

Se modifico:

```text
/home/massisalva/Docker/Wg-easy/compose.yaml
```

Cambios relevantes:

```yaml
entrypoint: ["/usr/local/bin/wg-easy-nft-entrypoint.sh"]
volumes:
  - /home/massisalva/Docker/Wg-easy/wg-easy-nft-entrypoint.sh:/usr/local/bin/wg-easy-nft-entrypoint.sh:ro
```

Backup previo:

```text
/home/massisalva/Docker/Wg-easy/compose.yaml.bak-20260708
```

Actualizacion posterior:

- Se amplio `ALLOWED` en
  `/usr/local/sbin/restrict-docker-admin-panels.sh` para incluir
  `10.8.0.0/24`.
- Motivo: permitir que clientes conectados por WireGuard administren los
  paneles Docker internos.
- Backup del script anterior:
  `/usr/local/sbin/restrict-docker-admin-panels.sh.bak-20260708-wg`.
- Se reaplico con:

```bash
sudo systemctl restart restrict-docker-admin-panels.service
```

Validacion desde cliente WireGuard:

- `http://192.168.1.2/admin`: funciona.
- `http://192.168.1.2:3000`: funciona.
- `http://192.168.1.2:51821`: funciona.
- `https://192.168.1.2:9443`: funciona.

Nota:

- Portainer en `9443` requiere `https://`.
- Si se usa `http://192.168.1.2:9443`, Portainer responde con un error del tipo
  "Client sent an HTTP request to an HTTPS server".

Comando de aplicacion:

```bash
cd /home/massisalva/Docker/Wg-easy
docker compose up -d wg-easy
```

Validacion posterior:

```text
Health=healthy Status=running
RestartCount=0
iptables v1.8.11 (nf_tables)
ip6tables v1.8.11 (nf_tables)
wg0-up
listening port: 51820
```

El panel `51821/tcp` sigue protegido por la cadena `RPI-ADMIN-PANELS` y solo
queda accesible desde:

- `192.168.1.49`
- `192.168.1.59`

Comando manual para verificar UDP desde Arch, requiere sudo local:

```bash
sudo nmap -sU -p 51820 192.168.1.2
```

Prueba desde fuera de la LAN:

- Se creo port forward manual en Huawei para `51820/udp` hacia
  `192.168.1.2:51820`.
- Se reviso el panel del Huawei y se confirmo que no habia otros port forwards
  visibles; solo la regla de WireGuard.
- Se probo conexion desde un cliente externo/datos moviles.
- `wg show wg0 dump` mostro endpoint remoto y trafico.

Resultado observado:

```text
endpoint=181.9.226.226:2171
allowed_ips=10.8.0.2/32,fdcc:ad94:bacf:61a4::cafe:2/128
latest_handshake=2026-07-08 21:36:45 -03
rx=31332
tx=160920
```

Interpretacion:

- WireGuard quedo funcionando desde fuera de la LAN.
- Hay handshake reciente y transferencia en ambos sentidos.
- `wg-easy` permanecio `healthy`.

Rollback:

```bash
cd /home/massisalva/Docker/Wg-easy
cp -a compose.yaml.bak-20260708 compose.yaml
docker compose up -d wg-easy
```

### 6. Reservas DHCP recomendadas/configuradas

Se pidio reservar IPs en el Huawei/DHCP:

| Nombre | IP | MAC |
| --- | --- | --- |
| `raspberrypi` | `192.168.1.2` | `2c:cf:67:6d:2f:b7` |
| `arch` | `192.168.1.49` | `08:9d:f4:d3:3b:5f` |
| `mac-mini` | `192.168.1.59` | `66:99:46:c3:40:3d` |

Validacion posterior:

- Arch mantuvo `192.168.1.49`.
- Raspberry mantuvo `192.168.1.2`.
- `192.168.1.59` no respondio al ultimo ping/descubrimiento; puede estar
  dormida, con firewall o sin renovar DHCP.

Pendiente:

- Confirmar desde la Mac mini:

```bash
ipconfig getifaddr en0
```

Y probar:

```text
http://192.168.1.2:3000
https://192.168.1.2:9443
```

### 7. Restriccion de VNC a Mac mini

Motivo:

- `wayvnc` escucha en `5900/tcp`.
- VNC se usa ocasionalmente desde la Mac mini, por lo que no se apago.
- Se redujo la exposicion para que no quede disponible desde toda la LAN.

Se creo el script:

```text
/usr/local/sbin/restrict-host-services.sh
```

Se creo el servicio systemd:

```text
/etc/systemd/system/restrict-host-services.service
```

Regla aplicada:

- Permitir `5900/tcp` solo desde `192.168.1.59`.
- Bloquear `5900/tcp` para el resto de origenes por `eth0`.

Comando de aplicacion:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now restrict-host-services.service
```

Validacion:

- Desde Arch `192.168.1.49`, `nmap -sT -p 5900 192.168.1.2` devuelve
  `filtered`.
- `wayvnc.service` y `wayvnc-control.service` siguen `active`.
- `ss -tulpen` confirma que `wayvnc` sigue escuchando en `*:5900`.

Rollback temporal:

```bash
sudo systemctl stop restrict-host-services.service
sudo /usr/sbin/iptables -D INPUT -j RPI-HOST-SERVICES
```

Rollback persistente:

```bash
sudo systemctl disable --now restrict-host-services.service
sudo rm -f /etc/systemd/system/restrict-host-services.service
sudo rm -f /usr/local/sbin/restrict-host-services.sh
sudo systemctl daemon-reload
sudo /usr/sbin/iptables -F RPI-HOST-SERVICES
sudo /usr/sbin/iptables -X RPI-HOST-SERVICES
```

## Estado posterior de Raspberry

Desde el Arch permitido, siguen abiertos:

- `22/tcp`: SSH
- `53/tcp`: DNS
- `80/tcp`: Pi-hole web
- `443/tcp`: Pi-hole web HTTPS
- `3000/tcp`: Homepage, permitido solo a IPs confiables
- `3001/tcp`: Uptime Kuma, permitido solo a IPs confiables
- `5900/tcp`: VNC
- `8096/tcp`: Jellyfin
- `9443/tcp`: Portainer, permitido solo a IPs confiables
- `9999/tcp`: Dozzle, permitido solo a IPs confiables
- `32400/tcp`: Plex
- `51821/tcp`: wg-easy admin, permitido solo a IPs confiables

Cerrado:

- `111/tcp`: rpcbind

## Retoma y validacion - 2026-07-09

Validacion no destructiva ejecutada desde Arch el 2026-07-09.

Estado local:

- Arch/notebook conserva `192.168.1.49/24` en `wlo2`.
- Gateway por defecto: `192.168.1.1`.
- La conexion SSH a Raspberry funciona con clave usando `192.168.1.2`.

Servicios relevantes en Raspberry:

- `ssh`: `active`.
- `docker`: `active`.
- `restrict-docker-admin-panels.service`: `active`.
- `restrict-host-services.service`: `active`.
- `rpcbind.service`: `inactive`.
- `rpcbind.socket`: `inactive`.

Contenedores relevantes:

- `wg-easy`: `Up ... (healthy)`, `RestartCount=0`.
- `homepage`: `healthy`.
- `uptime-kuma`: `healthy`.
- `pihole`: `healthy`.
- `watchtower`: `healthy`.
- `dozzle`, `portainer`, `duckdns`, `plex`, `jellyfin`: activos.

Escaneo TCP acotado desde Arch:

```bash
nmap -sT -p 22,53,80,111,443,3000,3001,5900,8096,9443,9999,32400,51821 --open 192.168.1.2
```

Resultado:

- Abiertos: `22`, `53`, `80`, `443`, `3000`, `3001`, `8096`, `9443`,
  `9999`, `32400`, `51821`.
- `111/tcp` no aparece abierto.
- `5900/tcp` no aparece abierto desde Arch, coherente con la restriccion de
  VNC a `192.168.1.59`.

Reglas activas:

- `DOCKER-USER` referencia `RPI-ADMIN-PANELS`.
- `RPI-ADMIN-PANELS` permite `3000`, `3001`, `9443`, `9999` y `51821` desde
  `192.168.1.49`, `192.168.1.59` y `10.8.0.0/24`; bloquea el resto por
  `eth0`.
- `RPI-HOST-SERVICES` permite `5900/tcp` desde `192.168.1.59`; bloquea el
  resto por `eth0`.
- Los contadores muestran trafico permitido desde `192.168.1.49` y
  `192.168.1.59`, y drops para accesos no permitidos.

WireGuard:

- El binario `wg` no esta instalado en el host Raspberry.
- `wg` si esta disponible dentro del contenedor `wg-easy`.
- `wg0` escucha en `51820`.
- Peer `10.8.0.2/32` conserva endpoint externo y trafico acumulado.
- Ultimo handshake observado: aproximadamente 14 h 46 min antes de la
  validacion, por lo que no habia una sesion externa activa reciente al momento
  de retomar, pero el tunel habia funcionado despues de la reparacion.

SSH efectivo en Raspberry sigue endurecido:

```text
logingracetime 30
maxauthtries 3
permitrootlogin no
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
x11forwarding no
permitemptypasswords no
allowusers massisalva
```

Huawei/router:

- Escaneo TCP acotado desde LAN:
  - abiertos: `53/tcp`, `80/tcp`, `27998/tcp`, `37443/tcp`, `37444/tcp`;
  - cerrados/filtrados en el set probado: `22`, `23`, `443`, `7547`,
    `1900`, `50000`, `56789`, `56790`.
- Deteccion liviana de version:
  - `53/tcp`: DNS generico;
  - `80/tcp`: panel web local;
  - `27998/tcp`: SSL/desconocido;
  - `37443/tcp`: SSL/desconocido;
  - `37444/tcp`: `tcpwrapped`.
- HTML inicial del panel:
  - modelo declarado: `HG8245W5-8T-V2`;
  - modo/configuracion: `TELECOM2`;
  - `WebAccessMode`: `lan`.
- Consulta SSDP multicast con `M-SEARCH` no devolvio respuestas en esta
  prueba. No confirma por si sola que UPnP este apagado; debe verificarse en el
  panel.

DNS/DHCP:

- NetworkManager muestra que el perfil Wi-Fi activo `Huawei-08WT` recibio por
  DHCP:
  - gateway: `192.168.1.1`;
  - DNS 1: `192.168.1.1`;
  - DNS 2: `1.1.1.1`.
- `/etc/resolv.conf` coincide:
  - `nameserver 192.168.1.1`;
  - `nameserver 1.1.1.1`.
- Esto contradice el estado documentado previamente, donde DHCP entregaba
  `192.168.1.2`.
- Pruebas DNS UDP minimas:
  - `192.168.1.2` responde correctamente para dominios externos y `pi.hole`;
  - `1.1.1.1` responde correctamente para dominios externos;
  - `192.168.1.1` responde para algunos dominios externos, pero devolvio
    NXDOMAIN para `example.com` y no resuelve `pi.hole`.
- Recomendacion: corregir DHCP en el Huawei para que entregue solo
  `192.168.1.2` como DNS si se quiere que Pi-hole sea el resolver central.
  Como mitigacion local, se puede fijar DNS manual en el perfil
  NetworkManager `Huawei-08WT`.

Mitigacion local aplicada en Arch:

```bash
nmcli connection modify Huawei-08WT \
  ipv4.ignore-auto-dns yes \
  ipv4.dns 192.168.1.2 \
  ipv6.ignore-auto-dns yes
nmcli device reapply wlo2
```

Validacion posterior:

- Perfil `Huawei-08WT`:
  - `ipv4.ignore-auto-dns`: `yes`;
  - `ipv4.dns`: `192.168.1.2`;
  - `ipv6.ignore-auto-dns`: `yes`.
- NetworkManager en `wlo2`:
  - gateway: `192.168.1.1`;
  - DNS efectivo: `192.168.1.2`.
- `/etc/resolv.conf`:
  - `nameserver 192.168.1.2`.
- Consultas DNS directas a Pi-hole:
  - `example.com`: `rcode=0`, con respuestas;
  - `pi.hole`: `rcode=0`, con respuesta.

Rollback local:

```bash
nmcli connection modify Huawei-08WT \
  ipv4.ignore-auto-dns no \
  ipv4.dns "" \
  ipv6.ignore-auto-dns yes
nmcli device reapply wlo2
```

Nota local SSH:

- Dentro de la sandbox, `ssh` sin `-F /dev/null` fallo por
  permisos/ownership considerados inseguros en
  `/etc/ssh/ssh_config.d/20-systemd-ssh-proxy.conf`.
- Ejecutado con permisos fuera de la sandbox, `ssh` normal a la Raspberry
  funciono correctamente.
- Interpretacion: no hay evidencia de problema real en la configuracion SSH del
  sistema; fue un efecto del entorno restringido de ejecucion.

## Verificacion posterior a ajustes Huawei - 2026-07-09

El usuario indico haber aplicado los ajustes del panel Huawei. Se hizo una
revision no destructiva desde Arch.

DNS/DHCP:

- `wlo2` sigue en `192.168.1.49/24`.
- Gateway efectivo: `192.168.1.1`.
- DNS efectivo en NetworkManager: `192.168.1.2`.
- `/etc/resolv.conf`: solo `nameserver 192.168.1.2`.
- Opciones DHCP crudas recibidas desde el Huawei:
  - `dhcp_server_identifier = 192.168.1.1`;
  - `routers = 192.168.1.1`;
  - `domain_name_servers = 192.168.1.2`.

Interpretacion:

- El cambio global de DHCP quedo aplicado: el Huawei ahora entrega Pi-hole como
  DNS.
- En ese momento la mitigacion local de Arch seguia configurada
  (`ipv4.ignore-auto-dns yes` y `ipv4.dns 192.168.1.2`), pero ya no era la
  unica razon por la que Arch usaba Pi-hole; el DHCP del router tambien
  entregaba `192.168.1.2`.
- La mitigacion local fue revertida mas tarde; ver seccion
  "Ajuste DNS local revertido y Wi-Fi - 2026-07-09".

Pruebas DNS:

- `192.168.1.2` responde correctamente para `example.com`, `google.com` y
  `pi.hole`.
- `1.1.1.1` responde para dominios externos.
- `192.168.1.1` sigue respondiendo de forma irregular:
  - `google.com`: respuesta valida;
  - `example.com`: NXDOMAIN;
  - `pi.hole`: NXDOMAIN.

Huawei:

- Escaneo TCP acotado sin cambios relevantes:
  - abiertos: `53/tcp`, `80/tcp`, `27998/tcp`, `37443/tcp`, `37444/tcp`.
  - no abiertos en el set probado: `22`, `23`, `443`, `7547`, `1900`,
    `50000`, `56789`, `56790`.
- Consulta SSDP multicast `M-SEARCH`: sin respuestas.

Raspberry:

- Servicios:
  - `ssh`: `active`;
  - `docker`: `active`;
  - `restrict-docker-admin-panels.service`: `active`;
  - `restrict-host-services.service`: `active`;
  - `rpcbind.service`: `inactive`;
  - `rpcbind.socket`: `inactive`.
- `wg-easy`: `Health=healthy`, `Status=running`, `RestartCount=0`.
- Escaneo TCP acotado:
  - abiertos desde Arch: `22`, `53`, `80`, `443`, `3000`, `3001`, `8096`,
    `9443`, `9999`, `32400`, `51821`;
  - `111/tcp` no aparece abierto;
  - `5900/tcp` no aparece abierto desde Arch, coherente con la restriccion a
    `192.168.1.59`.
- Reglas `RPI-ADMIN-PANELS` y `RPI-HOST-SERVICES` siguen activas y con
  contadores.
- WireGuard:
  - `wg0` escucha en `51820`;
  - peer externo conserva trafico acumulado;
  - ultimo handshake observado: aproximadamente 15 horas antes de la revision.

Limitacion:

- Esta revision desde la LAN no confirma por si sola la exposicion desde
  Internet/WAN ni la lista real de port forwards del Huawei. Para eso sigue
  siendo necesario revisar el panel o probar desde una red externa controlada.

## Ajuste DNS local revertido y Wi-Fi - 2026-07-09

Se revirtio la mitigacion local de DNS en Arch para confiar en el DHCP del
Huawei, ahora que el router entrega Pi-hole correctamente.

Comandos aplicados:

```bash
nmcli connection modify Huawei-08WT \
  ipv4.ignore-auto-dns no \
  ipv4.dns "" \
  ipv6.ignore-auto-dns yes
nmcli device reapply wlo2
```

Validacion:

- Perfil `Huawei-08WT`:
  - `ipv4.ignore-auto-dns`: `no`;
  - `ipv4.dns`: vacio;
  - `ipv6.ignore-auto-dns`: `yes`.
- DHCP recibido:
  - `dhcp_server_identifier = 192.168.1.1`;
  - `routers = 192.168.1.1`;
  - `domain_name_servers = 192.168.1.2`.
- DNS efectivo:
  - NetworkManager: `192.168.1.2`;
  - `/etc/resolv.conf`: `nameserver 192.168.1.2`.

Revision Wi-Fi visible desde Arch:

- Conexion actual:
  - SSID: `Huawei-08WT`;
  - BSSID: `74:da:88:7b:6c:cb`;
  - banda/frecuencia: 5 GHz / `5200 MHz`;
  - canal: `40`;
  - seguridad observada: `WPA2`;
  - senial: `-46 dBm`;
  - ancho observado: `80 MHz`.
- Red propia/mesh observada:
  - `Huawei-08WT` y `Familia Salva` aparecen en 2.4 GHz canal `3`;
  - `Huawei-08WT` y `Familia Salva` aparecen en 5 GHz canal `40`.
- Redes cercanas relevantes:
  - canal 1: `Flia_Machuca`, senial menor;
  - canal 6: `Personal-WiFi-50E`, senial media;
  - canal 11: `Personal Wifi Zone`, abierta, senial menor;
  - canal 3: tambien aparece una impresora `DIRECT-95-HP Laser 107w` con
    senial alta.

Recomendacion Wi-Fi:

- Mantener 5 GHz canal `40` si la estabilidad sigue bien.
- Cambiar 2.4 GHz de canal `3` a un canal no solapado: `1`, `6` u `11`.
  Con lo observado, `11` parece el candidato menos conflictivo por intensidad,
  aunque debe validarse desde el panel/app del mesh.
- Migrar a WPA3-Personal o WPA2/WPA3 mixto solo si todos los dispositivos lo
  soportan sin perder conectividad.
- Mantener WPS desactivado.
- Usar red de invitados/IoT aislada para dispositivos menos confiables si el
  Huawei/Deco lo permite.

## Decisiones tomadas

- Mantener VNC activo porque se usa ocasionalmente.
- No tocar Plex/Jellyfin por ahora porque deben quedar disponibles para la LAN.
- No tocar Pi-hole porque es DNS central.
- No hacer cambios destructivos en Docker Compose; se prefirio filtrar via
  `DOCKER-USER`.
- Usar IPs reservadas para reglas de confianza.

## Pendientes recomendados

### Raspberry

1. Endurecer SSH:

   - Implementado: `PasswordAuthentication no`.
   - Implementado: `PermitRootLogin no`.
   - Implementado: `PubkeyAuthentication yes`.
   - Pendiente opcional: permitir SSH solo desde `192.168.1.49` y
     `192.168.1.59`.

2. Evaluar VNC:

   - mantenerlo si se usa;
   - Implementado: `5900/tcp` restringido a `192.168.1.59` Mac mini probable;
   - Pendiente: confirmar acceso RealVNC desde la Mac mini.

3. Revisar `wg-easy`:

   - Implementado: reparado backend `iptables-nft`.
   - Estado posterior: `healthy`, `wg0` levantado.
   - Implementado: conexion desde fuera de la LAN probada con handshake.
   - mantener `51820/udp` abierto solo si se usa WireGuard.

4. Revisar Watchtower:

   - varios contenedores tienen Watchtower habilitado;
   - para servicios criticos, evaluar `monitor-only` o actualizacion manual.

### Router Huawei

1. DHCP DNS:

   - Implementado/verificado: entrega solo `192.168.1.2`.

2. Confirmar desde el panel:

   - UPnP desactivado o justificar su uso;
   - WPS desactivado;
   - administracion remota WAN desactivada;
   - port forwards: mantener solo `51820/udp -> 192.168.1.2` si WireGuard se
     usa desde fuera.

3. Pendiente de verificacion externa:

   - probar desde una red fuera de la LAN que no haya exposicion WAN no
     esperada.

### Sagemcom / deco Flow probable

1. Identificado como probable deco Flow/Sagemcom.
2. No bloquear por ahora para evitar romper TV/servicio del proveedor.
3. Si en el futuro se crea una red IoT/invitados aislada, evaluar moverlo ahi
   solo si Flow sigue funcionando correctamente.

### Wi-Fi

1. Estado observado:

   - conexion actual en 5 GHz canal `40`, WPA2, senial fuerte;
   - 2.4 GHz sigue en canal `3`.

2. Recomendaciones:

   - mantener 5 GHz canal `40` si la estabilidad sigue bien;
   - cambiar 2.4 GHz de canal `3` a `11` como primera opcion observada, o a
     `1`/`6` si el panel/app del mesh muestra mejor ocupacion;
   - migrar a WPA3-Personal o WPA2/WPA3 mixto solo si todos los equipos lo
     soportan;
   - mantener WPS desactivado;
   - separar invitados/IoT de la LAN principal si el equipo lo permite.

## Comandos utiles

Reescanear Raspberry:

```bash
nmap -sT -p 22,53,80,111,443,3000,3001,5900,8096,9443,9999,32400,51821 --open 192.168.1.2
```

Ver reglas del filtro admin:

```bash
ssh massisalva@192.168.1.2 'sudo /usr/sbin/iptables -vnL RPI-ADMIN-PANELS'
```

Reaplicar reglas manualmente:

```bash
ssh massisalva@192.168.1.2 'sudo systemctl restart restrict-docker-admin-panels.service'
```

Ver contenedores y puertos:

```bash
ssh massisalva@192.168.1.2 'docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"'
```

Ver sockets de la Raspberry:

```bash
ssh massisalva@192.168.1.2 'ss -tulpen'
```

Ver servicios activos:

```bash
ssh massisalva@192.168.1.2 'systemctl --type=service --state=running --no-pager --plain'
```

## Notas de seguridad

- Las reglas actuales dependen de IPs estables. Si Arch o Mac mini cambian de
  IP, perderan acceso a los paneles restringidos.
- La Mac mini `192.168.1.59` se infirio por servicios AirPlay/RTSP. Conviene
  confirmarla desde macOS.
- Docker puede modificar reglas al reiniciar. El servicio
  `restrict-docker-admin-panels.service` se ejecuta despues de Docker para
  reinstalar el filtro.
- La auditoria no prueba exposicion desde Internet. UPnP/port forwards deben
  revisarse en el Huawei y, si aplica, en el Sagemcom.
