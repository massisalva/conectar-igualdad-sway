# Auditoría integral del sistema - 2026-08-01

## Resultado general

El sistema se encontró estable después del reinicio: no hay unidades fallidas,
presión de memoria, paquetes huérfanos ni errores de configuración en Sway,
Waybar, MPD o los scripts de sesión. Los servicios críticos de sistema y usuario
están activos.

La revisión del repositorio detectó debilidades de validación y recuperación,
pero ningún incidente crítico activo. Las correcciones se implementaron y la
regresión reproducible finalizó con 0 fallos.

## Estado observado

- Kernel `linux-zen` 7.1.5.
- 7.6 GiB de RAM, con aproximadamente 6.7 GiB disponibles durante la auditoría.
- zram de 3.8 GiB sin uso.
- Raíz ext4 de 468 GB al 6 % y partición de arranque al 6 %.
- Batería con 92.5 % de capacidad estimada respecto del diseño.
- Temperaturas observadas entre 42 °C y 48 °C.
- Wi-Fi conectado en 5 GHz, sin bloqueos rfkill y con reloj sincronizado.
- Sway, Waybar, Mako, MPD, PipeWire, WirePlumber y OneDrive activos.
- iwd, systemd-resolved, sshd, nftables, Bluetooth y TLP habilitados o activos.
- Sin paquetes huérfanos ni errores en la base de datos de pacman.
- 710 paquetes instalados, 119 explícitos y ninguna actualización pendiente.
- Raíz ext4 al 4 % después de limpiar cachés regenerables.

## Correcciones implementadas

- `disk-status` genera JSON mediante `json.dumps` y acepta etiquetas externas
  con comillas o separadores sin romper Waybar.
- Los menús de discos y audio ya no dependen de descripciones o delimitadores
  ambiguos para resolver el dispositivo elegido.
- `swayidle` se reemplaza por nombre y se verifica que exista una sola instancia.
- MPD dejó de declarar `pid_file` bajo systemd y deshabilita el decoder WildMIDI
  no configurado.
- El bootloader solo se instala cuando el UUID versionado coincide con la raíz
  activa.
- `check.sh` valida configuración efectiva de SSH, ruleset vivo de nftables,
  JSON de módulos, configuración gráfica, procesos duplicados, paquetes
  huérfanos, scripts residuales, unidades fallidas, journal, puertos y SMART.
- `restore.sh` crea backups con manifiesto, permite rollback y ofrece un modo
  `--prune` recuperable para scripts residuales.
- Una segunda revisión corrigió `--prune` para preservar explícitamente
  `headroom`, `uv` y `uvx`; antes podían confundirse con scripts residuales y
  eliminarse pese a ser herramientas externas legítimas.
- El rollback rechaza destinos fuera de `$HOME`, `/etc` y `/boot`, incluidas
  rutas con componentes `..`, para impedir que un manifiesto alterado escriba o
  elimine archivos arbitrarios.
- Se agregaron pruebas automatizadas para restauración, rollback, prune, discos
  con etiquetas adversas y salidas de audio con descripciones duplicadas.
- Se retiraron Qutebrowser, Mission Center, Nano y Vim; Firefox, btop y Neovim
  quedan como alternativas principales.
- Se limpiaron las cachés de npm, Cargo, Pub y uv sin retirar sus SDK.
- Headroom 0.33.0 quedó instalado con el perfil `proxy,code`, como servicio de
  usuario local para Codex, con telemetría desactivada.
- Una ejecución mínima de Codex atravesó el proxy correctamente y quedó
  registrada por `headroom perf`.

## Validación

`./check.sh` terminó con 0 fallos. Las advertencias sin privilegios corresponden
a archivos protegidos, la comprobación efectiva de SSH/nftables y el estado Git
local. Las pruebas automatizadas finalizaron correctamente.

La segunda pasada sumó una regresión para la preservación de herramientas
externas y otra para manifiestos de rollback manipulados. Ambas pruebas pasan;
`check.sh` ahora reconoce esas herramientas y ya no las reporta como residuos.

La validación privilegiada terminó con 0 fallos. El journal contenía 6 eventos
de prioridad error, aunque la salida multilínea hacía que el verificador
informara 19. Se corrigió el conteo usando registros JSON. El único core dump
era un proceso temporal `sway --validate` ejecutado durante la auditoría en un
entorno aislado; no fue la sesión gráfica activa, que permaneció saludable y
validó correctamente desde la terminal real.

La comprobación privilegiada completa debe ejecutarse en una terminal con:

```sh
./check.sh --system --sudo
```

## Pendientes deliberados

- Secure Boot continúa deshabilitado.
- La raíz ext4 continúa sin cifrado.
- El arranque actual registró reemplazo de journals tras un cierre no limpio y
  mensajes del controlador i915. No produjeron fallos de servicios ni de la
  sesión gráfica; conviene vigilar si se repiten.
- Los commits locales deben publicarse en `origin/main` para completar la
  sincronización del repositorio.
