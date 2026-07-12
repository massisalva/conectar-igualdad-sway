# Auditoría integral del sistema - 2026-07-12

## Resultado general

El sistema se encontró estable, sin unidades fallidas, paquetes huérfanos ni
actualizaciones pendientes. La migración de NetworkManager a Impala+iwd quedó
operativa: Wi-Fi, DHCP, DNS y NTP funcionan correctamente.

## Estado observado

- Kernel `linux-zen` 7.1.3 sobre Intel Celeron N4020.
- 7.6 GiB de RAM y zram de 3.8 GiB sin presión de memoria.
- Arranque total de 21.969 s; entorno gráfico disponible a los 5.610 s de userspace.
- SSD de 512 GB con aproximadamente 5 % de uso.
- TLP activo en perfil `balanced/BAT`; batería con 92.5 % de capacidad estimada.
- Sway, Waybar, Mako, PipeWire, MPD y OneDrive activos y sin fallos de servicio.
- nftables activo con política de entrada y forwarding `drop`.
- SSH limitado a clave pública, sin root ni contraseña, y permitido solo desde la LAN.

## Ajustes derivados

- Dominio regulatorio Wi-Fi fijado en `AR`.
- LocalSend permitido en TCP/UDP 53317 solo desde `192.168.1.0/24`.
- `kernel.kptr_restrict` elevado de 0 a 1.
- `smartmontools` agregado para controlar salud SMART del SSD.
- `nmap` incorporado a la lista reproducible por su uso en auditorías de red.
- `linux-zen-headers` retirado porque no hay módulos DKMS instalados.
- `python-httpx` retirado por no tener dependientes ni uso local identificado.
- `ueberzugpp` retirado: los previews gráficos estaban deshabilitados y el
  adaptador Wayland generaba coredumps al salir; Chafa queda como fallback.
- La limpieza de paquetes y dependencias exclusivas liberó aproximadamente
  494 MiB.

## Salud del SSD

Se instaló `smartmontools` y se realizó una lectura SMART completa:

- evaluación general `PASSED`;
- 0 sectores reasignados y 0 sectores pendientes;
- 0 errores SATA/CRC y ningún error SMART registrado;
- 25 °C durante la auditoría;
- 575 horas de encendido;
- indicador de desgaste en 0 % usado.

El autotest SMART corto finalizó sin errores y sin LBA defectuoso informado.

## Pendientes deliberados

- Secure Boot permanece deshabilitado.
- La raíz ext4 no está cifrada.
- Reducir el sondeo musical de Waybar ahorraría CPU, pero se conserva el
  intervalo de dos segundos para mantener respuesta inmediata.

Secure Boot y cifrado requieren una intervención separada, con respaldo y plan
de recuperación de arranque.
