# Auditoría del sistema — 2026-11-16

Hecha por Claude desde la ThinkPad por SSH, en solo lectura (lo de root, con `./check.sh --sudo` corrido por Maxi). Motivo: Streamrip no abría desde el botón de Arch de Waybar.

**Resumen:** el sistema está **sano**. El único error real era el de Streamrip (arreglado, ver H1). Lo demás son mejoras chicas.

## Hallazgos

**H1 (arreglado, `cef495d`). Lo que se abre desde Waybar no encontraba los comandos de `~/.local/bin`.** Waybar corre como servicio de systemd (`waybar.service`) con `PATH=/usr/local/bin:/usr/bin`: no lee `.profile` ni fish. El botón nuevo de Arch (`f3af0a4`) abre fuzzel desde Waybar, así que foot no encontraba `streamrip-menu` (registro: `streamrip-menu: failed to execute: No such file or directory`, 14:05). Afectaba a Streamrip y a `music-update`. Con Super+D andaba (fuzzel lo abre Sway). **Arreglo:** `home/.config/environment.d/20-path.conf` (`PATH=$HOME/.local/bin:$PATH`, probado con el generador de systemd), aplicado en caliente (`systemctl --user set-environment` + reinicio de Waybar) y control nuevo en `check.sh` (PATH de Waybar). Verificado: todos los lanzadores (propios y del sistema) resuelven su comando con el PATH de los servicios, y Maxi confirmó que Streamrip abre desde Waybar.

**H2 (hecho, `cef495d`). `check.sh` no puede validar Sway por SSH** (`sway -C` no consigue la pantalla: "No backend was able to open a seat"). Con un backend virtual sí se puede: `WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 sway -C` (y un `XDG_RUNTIME_DIR` temporal) → salida 0, sin errores. **Hecho:** `check.sh` lo usa como segundo intento; probado que un error real de configuración da fallo (salida 1, "Error on line"). Test en `test-ui-scripts.sh`.

**H3 (pregunta). `~/Música` (5,5 GB) no tiene backup.** Cuatro carpetas (0,5–2,6 GB) más `streamrip/`. Lo de Streamrip se vuelve a bajar; las otras cuatro, no se sabe. El repo guarda solo la configuración. **Pregunta para Maxi:** ¿son reemplazables? Si no: copiarlas a la mini (una carpeta dentro de `/srv` que entre en el backup; `compartido` NO tiene backup).

**H4 (informativo).** `systemd-resolved` tiene LLMNR (5355) y mDNS (5353) prendidos en todas las interfaces, pero el firewall (política drop) no deja entrar nada salvo SSH y LocalSend desde la LAN: no quedan expuestos. Efecto colateral: las respuestas mDNS de otros equipos tampoco entran, así que los nombres `.local` (p. ej. `mini.local`) probablemente no resuelven desde la Conectar (sin verificar). No molesta: el montaje de la mini usa la IP.

## Lo que está bien (verificado)

| Área | Estado |
|---|---|
| `check.sh --sudo` | 0 fallos y 0 avisos (después de H1 y H2) |
| Tests | `test-ui-scripts`, `test-restore`, `test-check`: OK |
| Sistema | Actualizado el 16/11 14:00, 0 pendientes (oficiales y AUR), 0 huérfanos, 0 `.pacnew`; `paccache.timer` activo (caché 3,3 GB); kernel 7.3.4-zen |
| Servicios | 0 fallidos (sistema y usuario). Errores del arranque: solo mensajes de hardware (SGX, TDX, certificado X.509, i915) |
| Disco | SSD sano: 660 h, 0 sectores reasignados o pendientes, desgaste 0, 27 °C. `/` al 6 % |
| Batería | 92,5 % de la capacidad de diseño (28,1 / 30,4 Wh) |
| Seguridad | SSH: solo clave, solo `massisalva`, sin root, sin X11, 3 intentos. nftables vivo = repo (entrada drop; SSH y LocalSend solo LAN). Polkit y systemd-boot = repo |
| Puertos | 22 (SSH), MPD 6600 y Headroom 8787 solo en 127.0.0.1; resolved local |
| Sway | Configuración válida (backend virtual) |
| Repo | Igual a Forgejo y a GitHub (`5fec77e`); sin binarios `.old` de agy en `~/.local/bin` |
