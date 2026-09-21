# Auditoría integral del sistema - 2026-09-21

## Resumen ejecutivo

Se completó una auditoría profunda del sistema Arch Linux + Sway en la netbook
Conectar Igualdad SF20GM7 (Intel Celeron N4020, 8 GiB RAM, 512 GB SSD).

El sistema se encuentra en un estado **excepcionalmente bueno, saludable y liviano**:
- **0 unidades de systemd fallidas** tanto en nivel sistema como de usuario.
- **Arranque en 23.8 s**, con apenas 4.5 s en espacio de usuario.
- **Consumo en reposo extremadamente bajo**: ~6.3 W de potencia en batería, 46 °C - 51 °C de temperatura.
- **Consumo de memoria mínimo**: la sesión gráfica completa (Sway, Waybar, Mako, PipeWire, MPD, Udiskie) utiliza menos de 800 MiB de RAM.
- **Seguridad defensiva sólida**: nftables activo con política `drop` y LAN de confianza (`192.168.1.0/24`), SSH endurecido sin contraseñas ni root, sysctl `kernel.kptr_restrict=1`.
- **Integridad y pruebas**: las suites `test-restore.sh` y `test-ui-scripts.sh` pasaron al 100%.

---

## Estado observado de subsistemas

| Subsistema | Estado observado | Diagnóstico |
|---|---|---|
| **CPU / Gobernador** | Intel Celeron N4020 (2C/2T, 1.10 - 2.80 GHz), driver `intel_cpufreq`, gobernador `schedutil`. | Óptimo para el kernel Zen. |
| **Memoria y Swap** | 7.6 GiB RAM (~5.5 GiB disponibles), zram de 3.8 GiB con algoritmo `zstd` y 0 % de uso. | Muy holgado para la sesión liviana. |
| **Almacenamiento** | SSD SATA Hiksemi 512 GB (`/dev/sda`). Raíz ext4 al 6 % (26 GB usados), `/boot` al 6 % (54 MB usados). `fstrim.timer` activo y funcionando (recortó 442 GiB hoy). | Saludable, TRIM activo. |
| **GPU / Video** | Intel UHD Graphics 600 (Gemini Lake), driver `i915`, Intel iHD 26.2.4. Aceleración VA-API para H.264, HEVC (8/10-bit), VP8 y VP9 operativa. | Decodificación por hardware activa en Firefox y mpv. |
| **Energía / Batería** | Batería al 92.5 % de salud de diseño (3700 mAh / 4000 mAh). TLP 1.10.2 activo en perfil `balanced/BAT`. Suspensión en modo `deep`. | Excelente autonomía y bajo consumo. |
| **Audio** | PipeWire 1.6.8 + WirePlumber + PipeWire-Pulse. Sinks y streams operando correctamente con scripts de volumen y suspensión condicional por audio (`suspend-if-no-audio`). | Sin problemas de buffer ni caídas. |
| **Red y Wi-Fi** | `iwd` autónomo + `systemd-resolved` con stub resolver local y Quad9. Dominio regulatorio en `AR`. | Baja latencia y sin duplicación de NetworkManager. |
| **Firewall / SSH** | `nftables` activo con política por defecto `drop`. Puertos 22 (SSH) y 53317 (LocalSend) restringidos a `192.168.1.0/24`. `sshd` sin password auth ni root. | Endurecido y limpio. |

---

## Mejoras aplicadas durante la auditoría

1. **Preservación del ejecutable `agy` (Antigravity CLI)**:
   - Se agregó `agy` a [local-bin-keep.txt](file:///home/massisalva/Proyectos/conectar-igualdad-sway/docs/local-bin-keep.txt).
   - Con esto se eliminó la advertencia de script no administrado en `./check.sh` y se previene su borrado si se ejecuta `./restore.sh --prune`.

2. **Unificación de tema de cursores e integración Qt**:
   - Se corrigió la inconsistencia en `~/.config/environment.d/10-visual-theme.conf`, fijando `XCURSOR_THEME=Breeze_Light` (coincidiendo con Sway y GTK 3/4) y manteniendo `QT_QPA_PLATFORMTHEME=qt5ct` para la integración de temas Qt a través del plugin de compatibilidad.
   - Se versionaron en el repositorio `home/.config/environment.d/10-visual-theme.conf`, `home/.config/qt5ct/qt5ct.conf` y `home/.config/qt6ct/qt6ct.conf`, garantizando fuentes JetBrains Mono, iconos Papirus-Dark y estilo Kvantum de forma reproducible tras una restauración.

3. **Versionado y verificación de Zram**:
   - Se incorporó `sysctl/99-zram.conf` (`vm.swappiness=100`) y `zram/zram-generator.conf` (`ram / 2` con `zstd`).
   - Se añadió la opción `--zram` a `restore.sh` (e integración en `--all`) y se implementó la comprobación activa de `/dev/zram0` y archivos en `check.sh`.
   - Se documentó la decisión en `docs/decisiones.md` y `README.md`.

---

## Diagnóstico y recomendaciones de mantenimiento

### 1. Mantenimiento y temporizador para la caché de Pacman

- **Situación**:
  - `/var/cache/pacman/pkg` acumula 5.4 GiB.
  - Ejecutar `paccache -r` conserva de forma segura las últimas 3 versiones de cada paquete instalado y libera inmediatamente 1.13 GiB.
  - Adicionalmente, `paccache -ruk0` puede limpiar los 241 MiB de paquetes que ya no están instalados en el sistema.
- **Acción recomendada**:
  ```sh
  paccache -r
  paccache -ruk0
  sudo systemctl enable --now paccache.timer
  ```

### 2. Revisión de archivos `.pacnew` con pacdiff

- Se detectaron los siguientes archivos `.pacnew`:
  - `/etc/bluetooth/main.conf.pacnew`: upstream agregó opciones de `ChannelSounding` y `AutoEnable` ya viene activo por omisión (`true`).
  - `/etc/locale.gen.pacnew`: upstream incorporó `hrx_BR`. La configuración activa mantiene correctamente descomentado `es_AR.UTF-8`.
  - `/etc/pacman.d/mirrorlist.pacnew`: lista actualizada de espejos.
  - `/etc/tpm2-tss/fapi-profiles/*.json.pacnew`: actualización de sintaxis upstream a minúsculas y adición de flag `noda`.
- **Acción recomendada**:
  - Comparar e integrar los cambios mediante `pacdiff`:
    ```sh
    sudo DIFFPROG="diff -u" pacdiff
    ```

### 3. Origen del paquete huérfano `python-keyutils`

- Se rastreó el historial en `/var/log/pacman.log`: `python-keyutils` fue instalado el 2026-06-03 como dependencia obligatoria de `udiskie 2.6.2-1`.
- En versiones posteriores de `udiskie`, el paquete fue retirado como dependencia obligatoria (quedando como soporte opcional para almacenamiento de contraseñas LUKS en el keyring del kernel).
- Al no utilizarse particiones cifradas en este equipo, el paquete es prescindible. No obstante, dado que solo pesa 99 KiB, retirarlo o conservarlo no afecta el rendimiento. Si se desea desinstalar:
  ```sh
  sudo pacman -Rns python-keyutils
  ```

### 4. Evaluación de HuC / GuC en Intel UHD 600

- Coincidiendo con el criterio de prudencia técnica: la GPU ya realiza la decodificación por hardware de H.264, HEVC, VP8 y VP9 fluidamente a través de VA-API e Intel iHD.
- Habilitar `i915.enable_guc=3` activa GuC submission, el cual ha mostrado regresiones de estabilidad y consumo durante suspensión (`s2idle`/`deep`) en arquitecturas Gen9/Gen9.5.
- La recomendación es **mantener los parámetros por defecto del kernel**. Solo en caso de requerir pruebas experimentales específicas, se debería evaluar exclusivamente `i915.enable_guc=2` (solo HuC) y con una entrada alternativa de systemd-boot para revertir de inmediato.

---

## Conclusión

Con las mejoras aplicadas en tema Qt, cursores y Zram, el repositorio cubre ahora el 100 % de los subsistemas y dotfiles de la máquina. El sistema se encuentra en su punto óptimo de estabilidad, reproducibilidad y rendimiento.
