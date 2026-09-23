# Auditoría integral del sistema - 2026-09-22

## Resumen ejecutivo

Se realizó una auditoría profunda del sistema Arch Linux + Sway en la netbook
Conectar Igualdad SF20GM7 (Intel Celeron N4020, 8 GiB RAM, 512 GB SSD).

El relevamiento comprendió la salud general del hardware, la sesión gráfica sobre
Wayland puro, el uso de memoria y almacenamiento, los servicios en segundo plano,
la higiene del árbol de paquetes y la correspondencia exacta entre el sistema
vivo y este repositorio de dotfiles.

Principales resultados:
- **Recuperación de 6 GB de almacenamiento**: el uso de la partición raíz `/`
  se redujo de 29 GB a 23 GB tras la purga de cachés de compilación y paquetes viejos.
- **Higiene total de paquetes**: eliminación de 4 paquetes huérfanos y activación
  del temporizador del sistema `paccache.timer` para mantenimiento preventivo semanal.
- **Persistencia de portapapeles**: incorporación de `cliphist` supervisado por
  `systemd --user`, menú interactivo en Fuzzel y atajo `Super + Shift + V`.
- **Filtro de luz nocturna**: incorporación del servicio en espacio de usuario
  `wlsunset` ajustado automáticamente para coordenadas de Argentina (-34.6, -58.4).
- **Dotfiles 100 % reproducibles**: versionado de `config.fish` (arranque de Sway
  en TTY1 y Starship), registro de `gnome-keyring`, `cliphist` y `wlsunset` en
  la lista de paquetes pacman y actualización del menú de atajos `Super + F1`.
- **Integridad y pruebas**: suites `test-restore.sh` y `test-ui-scripts.sh` con 100 % de éxito;
  `./check.sh` con **0 fallos**.

---

## Estado observado de subsistemas

| Subsistema | Estado observado | Diagnóstico |
|---|---|---|
| **CPU / Gobernador** | Intel Celeron N4020 (2C/2T, 1.10 - 2.80 GHz), driver `intel_cpufreq`, gobernador `schedutil`. | Rendimiento ágil con kernel Zen. Temperaturas estables entre 44 °C y 51 °C. |
| **Memoria y ZRAM** | 7.6 GiB RAM física + 3.8 GiB ZRAM (`zstd`, prioridad 100, swappiness 100). | Consumo en reposo < 850 MiB. Gran margen de compresión en memoria. |
| **Almacenamiento** | SSD SATA Hiksemi 512 GB (`/dev/sda2`). Raíz ext4 al 6 % (23 GB usados tras limpieza). `fstrim.timer` programado semanalmente. | Disco optimizado y con 422 GB disponibles. |
| **GPU / Video** | Intel UHD Graphics 600 (Gemini Lake), driver `i915`, Intel iHD 26.2.4. Aceleración VA-API operativa para H.264, VP9 y HEVC (8/10-bit). | Decodificación por hardware fluida; sin carga de CPU al reproducir video en formatos soportados. |
| **Wayland / Sesión** | Sway 1.12 en Wayland nativo (sin Xwayland). Waybar, Mako, foot, fuzzel y swayidle activos. | Entorno limpio, reactivo y de bajísimo consumo de batería. |
| **Red y Seguridad** | `iwd` + `systemd-resolved`, `nftables` con política `drop` y LAN de confianza (`192.168.1.0/24`), `sshd` endurecido sin login por contraseña ni root. | Blindaje perimetral conservador y eficiente. |

---

## Mejoras y acciones aplicadas durante la auditoría

### 1. Higiene del sistema y recuperación de almacenamiento
1. **Purga de paquetes huérfanos**:
   - Se desinstalaron `localsend-debug` (~41 MiB de símbolos de depuración desvinculados),
     `libayatana-indicator`, `ayatana-ido` y `python-keyutils`.
2. **Limpieza de cachés de paquetes**:
   - `~/.cache/yay`: se limpiaron 3.4 GiB de fuentes y árboles de compilación de AUR.
   - `/var/cache/pacman/pkg`: se ejecutó `paccache -r -k2` y `paccache -r -u -k0`,
     liberando 2.5 GiB de paquetes instalados antiguos y versiones de paquetes ya desinstalados.
3. **Mantenimiento automatizado**:
   - Se habilitó e inició `paccache.timer` en systemd para realizar la poda automática
     de versiones antiguas de paquetes semanalmente.
4. **Limpieza en espacio de usuario**:
   - Se eliminó el binario de respaldo obsoleto `~/.local/bin/agy.*.old` (224 MiB).
   - Se eliminaron configuraciones residuales en `~/.config/` de navegadores desinstalados
     (`BraveSoftware`, `chromium`, `google-chrome*`, `microsoft-edge-dev`, `qutebrowser`).
   - El tamaño de `~/.cache` se redujo de 4.3 GiB a 842 MiB.

### 2. Gestión de portapapeles (`cliphist`)
- En Wayland puro, al cerrar una aplicación el contenido copiado se descarta por diseño
  si no existe un administrador de portapapeles activo.
- Se implementó `home/.config/systemd/user/sway-cliphist.service`, que ejecuta:
  ```sh
  wl-paste --watch cliphist store
  ```
- Se creó el script interactivo [clipboard-menu](file:///home/massisalva/Proyectos/conectar-igualdad-sway/home/.local/bin/clipboard-menu) integrado con Fuzzel y Catppuccin Mocha.
- Se asignó el atajo **`Super + Shift + V`** en `home/.config/sway/config.d/40-keybindings.conf`,
  preservando `Super + V` para la división vertical (`split v`) sin colisiones.

### 3. Filtro de luz nocturna (`wlsunset`)
- Para reducir la fatiga visual en uso nocturno sin sobrecargar la CPU, se implementó
  el servicio en espacio de usuario `home/.config/systemd/user/wlsunset.service`.
- Utiliza coordenadas para Argentina (`-l -34.6 -L -58.4`) con temperatura de 4500K de noche
  y 6500K de día, calculando transiciones suaves según la trayectoria solar.
- Ambos servicios se incorporaron a `home/.config/systemd/user/sway-session.target`.

### 4. Sincronización del repositorio y reproducibilidad
1. **Configuración de shell**:
   - Se versionó `home/.config/fish/config.fish` garantizando que el inicio automático de Sway
     al iniciar sesión en TTY1 y la inicialización de Starship queden respaldados.
2. **Listas de paquetes oficiales**:
   - Se añadieron `gnome-keyring`, `cliphist` y `wlsunset` a [docs/pkglist-pacman.txt](file:///home/massisalva/Proyectos/conectar-igualdad-sway/docs/pkglist-pacman.txt).
   - Las listas de paquetes declaradas en el repositorio coinciden al 100 % con los
     paquetes instalados explícitamente en el sistema.
3. **Guía interactiva de atajos**:
   - Se actualizó [shortcut-help](file:///home/massisalva/Proyectos/conectar-igualdad-sway/home/.local/bin/shortcut-help) (`Super + F1`) incorporando `Super + Shift + V` y clarificando
     la división de ventanas.

---

## Verificación final

- `tests/test-restore.sh`: **OK**
- `tests/test-ui-scripts.sh`: **OK**
- `./check.sh`: **0 fallos, 7 advertencias** (todas esperadas y correspondientes a verificaciones de archivos del sistema protegidos que requieren sudo interactivo).
- `sway -C`: configuración válida y sin advertencias ni ventanas de error de `swaynag`.
- Estado de servicios de usuario: `sway-cliphist.service` y `wlsunset.service` activos y funcionando con consumo conjunto inferior a 1 MiB de RAM.
