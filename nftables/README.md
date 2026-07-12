# nftables

Firewall local conservador para la netbook.

Politica:

- entrada por defecto bloqueada;
- salida permitida;
- forwarding bloqueado;
- loopback y conexiones establecidas permitidas;
- ICMP/ICMPv6 basico permitido;
- DHCP cliente permitido;
- SSH y LocalSend permitidos solo desde `192.168.1.0/24`.

Instalacion:

```sh
./restore.sh --nftables
```

Verificacion:

```sh
./check.sh --system --sudo
```

LocalSend usa TCP/UDP 53317 para descubrimiento y transferencia. Si cambia la
LAN de confianza, ajustar `trusted_lan_ipv4` en
`nftables.conf` antes de instalar.
