# Auditoria de red - 2026-07-04

## Alcance

Auditoria defensiva desde la Conectar Igualdad en la LAN actual.

No se probo exposicion desde Internet/WAN ni reglas completas de firewall con
privilegios root. El barrido activo fue acotado a `192.168.1.0/24`.

## Estado local

- Interfaz activa: `wlo2`
- IP local: `192.168.1.49/24`
- Gateway: `192.168.1.1`
- DNS configurado por NetworkManager:
  - `192.168.1.2`
  - `fe80::1%wlo2`
- IPv6: solo ruta link-local `fe80::/64`, sin direccion global observada.
- Perfil Wi-Fi activo: `Huawei-08WT`
- Seguridad Wi-Fi reportada: WPA2 / PSK
- Perfiles Wi-Fi con autoconexion: solo `Huawei-08WT`
- `systemd-resolved`: inactivo; `/etc/resolv.conf` es generado por NetworkManager.

## Servicios locales expuestos

Puertos escuchando en la maquina:

- `0.0.0.0:22` y `[::]:22`: `sshd`
- `127.0.0.1:6600`: MPD, solo loopback

Observaciones:

- MPD no queda expuesto a la LAN.
- SSH si queda expuesto a toda la LAN.
- No se observaron otros servicios TCP/UDP abiertos relevantes desde `ss`.

## SSH

Configuracion efectiva observada en `/etc/ssh/sshd_config.d/10-hardening.conf`:

- `AllowUsers massisalva`
- `PermitRootLogin no`
- `PubkeyAuthentication yes`
- `PasswordAuthentication no`
- `KbdInteractiveAuthentication no`
- `PermitEmptyPasswords no`
- `MaxAuthTries 3`
- `LoginGraceTime 30`
- `X11Forwarding no`

Permisos de claves:

- `~/.ssh`: `700`
- `~/.ssh/authorized_keys`: `600`
- Hay 2 claves `ssh-ed25519` autorizadas.
- Las claves no tienen restricciones visibles tipo `from=`, `restrict` o
  `command=`.

Riesgo principal:

- Aunque SSH esta endurecido, escucha en todas las interfaces y no se demostro
  un firewall activo. En redes no confiables, cualquier equipo de la LAN puede
  intentar conectar al puerto 22.

## Firewall

Servicios consultados:

- `nftables`: inactivo, deshabilitado
- `firewalld`: no instalado
- `ufw`: no instalado
- `iptables`: inactivo

No se pudo leer `nft list ruleset` sin sudo interactivo.

Interpretacion conservadora:

- No hay evidencia de firewall local activo.
- Conviene agregar una politica explicita, aunque la superficie actual sea baja.

## Bluetooth

Estado:

- Bluetooth activo.
- `Discoverable: no`
- `Pairable: no`
- Sin dispositivos conectados al momento de la auditoria.

Riesgo:

- Bajo en el estado observado. Si no se usa Bluetooth a diario, apagarlo reduce
  superficie de ataque local.

## Hosts detectados en la LAN

Barrido ICMP en `192.168.1.0/24`:

- `192.168.1.1`
- `192.168.1.2`
- `192.168.1.3`
- `192.168.1.15`
- `192.168.1.20`
- `192.168.1.29`
- `192.168.1.49`
- `192.168.1.59`
- `192.168.1.70`

Vecinos ARP observados:

- `192.168.1.1`: `9c:b2:e8:c4:26:e7`
- `192.168.1.2`: `2c:cf:67:6d:2f:b7`

Puertos comunes abiertos detectados:

- `192.168.1.1`: `53`, `80`
- `192.168.1.2`: `22`, `53`, `80`, `443`
- `192.168.1.3`: `80`, `443`
- `192.168.1.15`: `80`, `443`
- `192.168.1.20`: `8443`
- `192.168.1.29`: `8443`
- `192.168.1.49`: `22`

Headers HTTP/HTTPS relevantes:

- `192.168.1.1`: HTTP 200 con cabeceras tipicas de panel web/router.
- `192.168.1.2`: HTTP/HTTPS 403 con cabeceras de aplicacion web protegida.
- `192.168.1.3` y `192.168.1.15`: HTTP/HTTPS 200 con headers similares.
- `192.168.1.20:8443` y `192.168.1.29:8443`: HTTPS 404.

## Prioridades

1. Activar firewall local.

   Recomendacion base: permitir loopback, conexiones establecidas, DHCP/DNS
   saliente, ICMP razonable y SSH solo desde la LAN o desde IPs de confianza.

   Implementado en repo como `nftables/nftables.conf`; instalacion explicita con
   `./restore.sh --nftables`.

2. Restringir SSH.

   Opciones:

   - mantener puerto 22, pero filtrado por firewall;
   - limitar `ListenAddress` a `192.168.1.49`;
   - agregar `from=` o `restrict` en claves de `authorized_keys` si cada clave
     tiene origen/uso conocido.

3. Revisar el router y los hosts con panel web.

   Verificar:

   - contrasenas de administracion no default;
   - firmware actualizado;
   - administracion remota WAN desactivada;
   - UPnP desactivado salvo necesidad concreta;
   - WPS desactivado;
   - red de invitados aislada para dispositivos no confiables.

4. Evaluar WPA3 o WPA2 fuerte.

   La red actual reporta WPA2-PSK. Esta bien si la clave es larga y unica.
   Si el router soporta WPA3-Personal o WPA2/WPA3 mixto sin romper equipos,
   conviene migrar.

5. Bluetooth.

   Estado actual razonable. Si no se usa seguido, apagar `bluetooth.service`
   reduce superficie local.

## Limitaciones de esta pasada

- No se hizo escaneo de version profundo porque `nmap` no esta instalado.
- No se verifico exposicion desde Internet.
- No se leyo ruleset nftables con sudo interactivo.
- No se ingreso a paneles de router/servicios.
