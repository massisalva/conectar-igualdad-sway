# Auditoría integral del sistema - 2026-07-25

## Resultado general

El sistema se encontró estable tras seis días de actividad continua. No hay
unidades fallidas, presión de memoria, paquetes huérfanos, errores de base de
datos de pacman ni errores recientes de almacenamiento, gráficos, Wi-Fi,
temperatura u OOM en el journal del kernel.

La configuración instalada coincide con el repositorio. El chequeo reproducible
terminó con 0 fallos; las advertencias corresponden a archivos que requieren
sudo para leerse y al commit local todavía no publicado en `origin/main`.

## Estado observado

- Kernel `linux-zen` 7.1.3 sobre Intel Celeron N4020.
- Uptime de 6 días y 8 horas, con carga inferior a 0.4 durante la auditoría.
- 7.6 GiB de RAM; 6.8 GiB disponibles y zram de 3.8 GiB sin uso.
- Arranque total de 21.754 s; entorno gráfico disponible a los 5.559 s de
  userspace, prácticamente igual a la medición anterior.
- SSD de 512 GB con 5 % de uso y raíz ext4 montada en lectura/escritura.
- Batería al 100 %, descargando, con 3.7 Ah de capacidad actual sobre 4.0 Ah de
  diseño: 92.5 % de capacidad estimada, sin cambio frente a la auditoría previa.
- Temperaturas informadas entre 20 °C y 36 °C.
- Wi-Fi conectado en 5 GHz con señal de -38 dBm, sin rfkill y con dominio
  regulatorio global `AR`.
- Reloj sincronizado mediante NTP y DNS entregado por la red a
  `systemd-resolved`.
- iwd, systemd-resolved, sshd y TLP activos. Waybar, Mako, PipeWire,
  WirePlumber, MPD y OneDrive activos en la sesión de usuario.
- `kernel.kptr_restrict=1` y configuraciones instaladas de SSH y nftables
  idénticas a las versionadas.

## Seguridad y red

SSH escucha en IPv4 e IPv6 en el puerto 22. La configuración instalada limita
el usuario permitido, deshabilita root, contraseñas y autenticación interactiva,
y conserva autenticación por clave pública.

`nftables.service` está habilitado y cargó `/etc/nftables.conf` correctamente al
arrancar. La unidad finalizó con estado exitoso y luego quedó inactiva, acorde a
su ejecución de carga de reglas. La configuración mantiene entrada y forwarding
en `drop`, y permite SSH y LocalSend solo desde `192.168.1.0/24`.

El ruleset vivo se comprobó con privilegios y coincide con esas políticas. La
lectura SMART actual resultó `PASSED`: 25 °C, 581 horas de encendido, 0 sectores
reasignados o pendientes, 0 errores CRC y ningún error SMART registrado. El
autotest corto anterior continúa registrado como completado sin errores.

## Hallazgos

- Se detectaron y luego instalaron correctamente 38 actualizaciones oficiales,
  entre ellas `linux-zen` 7.1.4, systemd 261.2, OpenSSH 10.4p1-3 y Firefox
  153.0. No quedaron actualizaciones oficiales pendientes.
- No hay paquetes huérfanos.
- La base de datos local de pacman no presenta errores.
- Los tres coredumps existentes son de `bluetoothctl` y pertenecen a la
  investigación del 19 de julio sobre la batería de la JBL Charge 5. No se
  registraron coredumps nuevos desde entonces.
- Antes de agregar este informe, el repositorio estaba limpio. `main` conserva
  un commit local pendiente de publicar:
  `48fb8cc Show Bluetooth battery in Waybar`.

## Acciones recomendadas

1. Reiniciar para cargar el kernel 7.1.4 y completar la actualización de
   componentes base.
2. Después del reinicio, verificar unidades fallidas, journal y funcionamiento
   de Sway, Waybar, red, audio y Bluetooth.
3. Publicar el commit local cuando se decida sincronizar `main` con el remoto.

## Fase correctiva

La actualización completa de 38 paquetes terminó sin errores. Pacman ejecutó
los 20 hooks posteriores y generó correctamente el initramfs para
`7.1.4-zen1-1-zen`. Tras la transacción no hay unidades fallidas y el chequeo
reproducible continúa terminando con 0 fallos.

Secure Boot continúa deshabilitado y la raíz ext4 continúa sin cifrado, ambos
como pendientes deliberados que requieren una intervención separada.
