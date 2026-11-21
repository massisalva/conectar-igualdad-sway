# Auditoría del proyecto — 2026-11-20

Documento de discusión para Maxi y Claude. Revisión de solo lectura sobre HEAD
`218c0f1`, complementaria a `auditoria-proyecto-2026-11-19.md` y
`auditoria-profunda-2026-11-19.md`: no repite hallazgos ya cerrados o aceptados,
sino huecos nuevos y cabos sueltos tras los cambios recientes.

Las propuestas quedan pendientes de decisión: documentarlas no autoriza
implementarlas ni aplicarlas al sistema. No se modificó ningún archivo de
código ni configuración activa; las reproducciones se ejecutaron en directorios
temporales.

## Alcance y verificaciones

Se revisaron `restore.sh`, `check.sh`, `lib/system-files.sh`, los 25 scripts de
`home/.local/bin/`, configuraciones de Sway, Waybar, Mako, Yazi, MPD,
unidades de `systemd --user`, piezas de sistema (`polkit/`, `nftables/`,
`sshd/`, `sysctl/`, `zram/`, `samba/`, `bootloader/`, `iwd/`), listas de
paquetes, `.desktop`, pruebas y `README.md`.

| Comprobación | Resultado observado |
| --- | --- |
| `tests/run-all.sh` — sintaxis Bash | OK |
| `tests/run-all.sh` — TOML de `home/` | OK |
| `tests/run-all.sh` — ShellCheck | OK |
| `tests/test-check.sh`, `test-restore.sh`, `test-system-files.sh`, `test-ui-scripts.sh` | OK |
| `tests/test-session-scripts.sh` | Falló en el sandbox por proceso zombie sin PID 1 cosechador (ver H1) |
| Reproducción aislada de carrera en `suspend-if-no-audio --cancel` (30 corridas) | Falló 3 de 30 (10 %, confirmado) |
| Prueba aislada de `cliphist wipe` en caché vacía y `CLIPHIST_DB_PATH` | OK (ambos funcionan en la versión instalada) |
| `git status` | Árbol limpio (sin cambios ajenos) |

La auditoría no certifica el estado vivo de servicios privilegiados, reglas
activas de firewall, SMART ni actualizaciones de paquetes.

---

## Prioridad alta

### H1 — Condición de carrera en `suspend-if-no-audio --cancel` y fuga de proceso en los tests

**Confirmado con reproducción aislada (3 de 30 corridas).**

Referencias: `home/.local/bin/suspend-if-no-audio` (L42–L73),
`tests/test-session-scripts.sh` (L79–L84, L115–L126) y
`home/.local/bin/start-idle` (L40–L46).

Al detectar audio activo, `suspend-if-no-audio` lanza
`setsid -f "$SELF" --wait` y retorna de inmediato. El proceso hijo todavía tiene
que arrancar `bash`, ejecutar `realpath` y recién después escribir su PID en
`$PID_FILE`. Si `--cancel` corre en esa ventana, no encuentra `$PID_FILE`,
termina con código `0` y la espera queda viva.

Dos consecuencias reales:

1. **En `tests/test-session-scripts.sh` (L82–L83):** el bucle corre
   `SUSPEND_AUDIO_INTERVAL=3600 bash .../suspend-if-no-audio` e inmediatamente
   llama a `--cancel` sin esperar a que exista `$PID_FILE`. Si cae en la
   carrera, el test termina y su `trap` borra `$TEST_ROOT/bin`, pero el
   `--wait` sobrevive durmiendo 1 hora; al despertar, `PATH` cae al
   `/usr/bin/pactl` y `/usr/bin/systemctl` reales y **puede suspender la netbook
   mientras la estás usando**.
2. **En la sesión real:** si el usuario vuelve justo al dispararse el timeout
   de 1800 s se da la misma carrera. Además:
   - `before-sleep` en `start-idle` solo ejecuta `lock-screen`, no
     `suspend-if-no-audio --cancel`: si suspendés a mano (tapa o `power-menu`)
     mientras hay una espera activa, esa espera puede quedar viva al despertar.
   - `trap 'exit 0' TERM INT` en `wait_for_silence` no mata al hijo
     `sleep "$INTERVAL"`, que queda huérfano hasta 60 s tras cancelar.
3. **Portabilidad del test:** en entornos donde PID 1 no cosecha huérfanos
   (contenedores o sandboxes), `setsid -f` deja al `--wait` en estado
   `Z (zombie)` tras `kill`; `kill -0` sigue devolviendo `0` y hace fallar
   `test-session-scripts.sh` (`FAIL: --cancel no terminó la espera`) aunque
   `--cancel` sí lo haya matado.

**Cambio propuesto:**

- Escribir `$PID_FILE` de forma síncrona desde el padre antes de retornar (p.
  ej. `setsid "$SELF" --wait </dev/null >/dev/null 2>&1 &` sin `-f` y guardar
  `$!` en `$PID_FILE`, o esperar confirmación del hijo con un FIFO/archivo
  atómico).
- En `wait_for_silence`: guardar el PID de `sleep` y matarlo en el `trap` de
  `TERM`/`INT`; antes de `exec systemctl suspend`, verificar que `$PID_FILE`
  siga conteniendo `$$`.
- En `start-idle`: cancelar también cualquier espera pendiente en `before-sleep`
  (o desde `power-menu` antes de suspender).
- En `test-session-scripts.sh`: agregar prueba de cancelación inmediata sin
  `wait_for` previo y comprobar terminación tolerando zombies en contenedores
  (p. ej. estado distinto de `Z` en `/proc/$waiter/status` o ausencia de
  `/proc/$waiter/cmdline`).

---

### H2 — «No molestar» oculta el aviso de batería crítica (5 %)

**Confirmado por lectura de configuración.**

Referencias: `home/.config/mako/config` (L35–L40) y
`home/.local/bin/waybar-battery` (L66–L69).

En Mako las secciones se evalúan en orden y la última prevalece. En
`mako/config`, `[mode=do-not-disturb]` con `invisible=1` aparece después de
`[urgency=high]` sin ninguna excepción para urgencia alta.

**Efecto:** si está activo «No molestar» (`Super+Ctrl+N`), tampoco se muestra
la notificación crítica de batería al 5 % (`notify-send -u critical`), y al 2 %
UPower apaga el equipo sin ningún aviso visible.

**Cambio propuesto:** sumar al final de `home/.config/mako/config`:

```ini
[mode=do-not-disturb urgency=high]
invisible=0
```

**Aceptación:** verificar con `makoctl mode -a do-not-disturb` que una
notificación `-u normal` queda oculta y una `-u critical` sí se muestra.

---

### H3 — El historial del portapapeles queda en texto plano en el disco al apagar (brecha en M3)

**Confirmado por lectura de unidad y prueba aislada de `cliphist`.**

Referencias: `home/.config/systemd/user/sway-cliphist.service` (L9–L15) y
`home/.local/bin/clipboard-menu`.

M3 buscaba evitar que lo copiado quede expuesto en el disco `sda2` sin cifrar
si la netbook se pierde o la roban fuera de casa. Sin embargo,
`ExecStartPre=/usr/bin/cliphist wipe` limpia la base recién al **próximo inicio
de sesión en Sway**. Mientras el equipo está apagado en la mochila, las
últimas 100 entradas siguen en claro en `~/.cache/cliphist/db` (además creado
con modo `644`).

Se verificó que la versión instalada de `cliphist` soporta `CLIPHIST_DB_PATH` y
`-db-path`.

**Cambio propuesto:** mover la base de cliphist a tmpfs en RAM, por ejemplo
`$XDG_RUNTIME_DIR/cliphist.db` (dentro de `/run/user/1000`, que tiene permisos
`700` y desaparece al apagar o cortar la energía), definiendo
`CLIPHIST_DB_PATH` en `home/.config/environment.d/` (y como respaldo en
`sway-cliphist.service` / `clipboard-menu`), y borrar una vez el viejo
`~/.cache/cliphist/db` residual.

**Aceptación:** al copiar texto en la sesión, se crea únicamente en
`$XDG_RUNTIME_DIR` y `~/.cache/cliphist/db` no existe; `clipboard-menu` lista,
decodifica y limpia correctamente; el test de M3 comprueba que la base apunta a
runtime/tmpfs.

---

## Prioridad media

### H4 — `disk-status` no detecta discos cifrados (LUKS) montados

**Confirmado por lectura del código.**

Referencias: `home/.local/bin/disk-status` (L40) y
`home/.local/bin/disk-manager` (L104).

Tras B1, `disk-manager` incluye nodos de tipo `crypt`, pero `disk-status` sigue
filtrando `device_type in ("part", "disk")`. Cuando se desbloquea y monta un
pendrive LUKS, el punto de montaje pertenece al nodo `crypt` (`/dev/mapper/...`),
por lo que Waybar nunca cambia a clase `mounted` y sigue informando
«conectado sin montar · Sistema: crypto_LUKS».

**Cambio propuesto:** incluir `"crypt"` en `disk-status` y filtrar montajes de
sistema (`/`, `/boot`, `[SWAP]`) de forma coherente con `disk-manager`, más una
prueba unitaria en `tests/test-ui-scripts.sh` con `lsblk` simulado de un LUKS
desbloqueado y montado.

---

### H5 — Bug de foco e inconsistencias en `waybar-music`

**Confirmado por lectura del código.**

Referencias: `home/.local/bin/waybar-music` (L97–L116, L181–L193, L347–L379,
L509–L542).

1. **Bug en `pid_for_child_process` (L183–L189):** `rows[current]` almacena
   `(ppid, args_de_current)`, pero se desempaqueta como
   `parent_pid, parent_args` y cuando `term_patterns` coincide con
   `parent_args` imprime `parent_pid` (el padre de la terminal, p. ej. Sway o
   systemd) en vez de `current` (el PID de `foot`).
2. **Prioridad invertida entre mostrar y controlar:** si MPD está pausado y
   Firefox o ncspot también están pausados, `current_song()` muestra el
   reproductor MPRIS (paso 2 antes que paso 3), mientras que `active_source()`
   elige `mpd` (L106 antes que L111). Hacer click en la barra o usar teclas
   multimedia actúa sobre un reproductor distinto al que se ve.
3. **`mpv` suelto sin soporte completo:** `active_source()` pasa `allow_mpv=1`
   a `music_player`, pero `current_song()` pasa `0` y `open_active()` no tiene
   rama `player:*mpv*`, cayendo a abrir `ncmpcpp`.

**Cambio propuesto:** imprimir `current` en `pid_for_child_process`, alinear la
prioridad entre `current_song()` y `active_source()`, y definir si `mpv` suelto
(fuera de PyRadio) se incluye en las tres funciones o se excluye de
`active_source()`, con pruebas simuladas.

---

### H6 — `./restore.sh --<pieza>` restaura `$HOME` por defecto y duplica `streamrip/config.toml` en cada backup

**Confirmado por lectura y verificación de `backups/`.**

Referencias: `restore.sh` (L12–L22, L423–L448) y `README.md` (L116–L126).

1. **Comportamiento sorprendente de flags individuales:** el README presenta
   `./restore.sh --polkit`, `./restore.sh --power`, etc. como pasos de sistema
   por separado, pero `RESTORE_USER=1` e `INSTALL_YAZI=1` quedan activos por
   defecto. Ejecutar `./restore.sh --power` sin `--no-user --no-yazi` también
   copia todo `home/` sobre `$HOME`, crea un backup completo, reajusta permisos
   y corre `ya pkg install`.
2. **Proliferación de copias de `streamrip/config.toml` (token ARL):** en cada
   restauración, `restore_user_files` ejecuta incondicionalmente
   `backup_target` y `chmod 600` sobre `~/.config/streamrip/config.toml` aunque
   **ya tenga modo `600`**. Hoy hay **5 copias** de ese archivo en
   `backups/restore-*`, además de `backups/manual-20261116-streamrip/config.toml`
   (carpeta `755`, archivo `600`). Lo mismo ocurre con `~/.ssh` y
   `~/.ssh/authorized_keys` cuando sus permisos ya son los esperados.

**Cambio propuesto:**

- En `restore.sh`, antes de respaldar y cambiar permisos de `~/.ssh`,
  `~/.ssh/authorized_keys` y `~/.config/streamrip/config.toml`, comprobar el
  modo actual con `stat -c '%a'` y omitir backup + `chmod` si ya es correcto.
- Decidir si pasar una opción de sistema puntual (`--power`, `--polkit`, etc.)
  debería requerir `--no-user --no-yazi` documentado en `README.md` o desactivar
  la restauración de usuario implícita cuando se pide solo una pieza de sistema.

---

### H7 — Atajos de `linemode` inalcanzables en Yazi

**Confirmado por lectura de configuración.**

Referencias: `home/.config/yazi/keymap.toml` (L13–L16 y L83–L91).

`on = "l"` (`plugin smart-enter`) ocupa el mismo prefijo que
`on = ["l", "s"]` (`linemode size`) y `on = ["l", "m"]` (`linemode mtime`).
Como `"l"` dispara de inmediato, los acordes `l s` y `l m` no se pueden usar.

**Cambio propuesto:** moverlos a `["m", "s"]` y `["m", "m"]` (el estándar de
Yazi, verificando que `m` no tenga colisión) o a otro prefijo libre.

---

## Prioridad baja / prolijidad

- **B1 — Cancelar con `Esc` devuelve error 1 en dos menús:**
  `home/.local/bin/audio-output-menu` (L56–L61) y
  `home/.local/bin/screenshot-menu` (L113–L115) usan `set -euo pipefail`, pero
  no capturan la salida `1` de `fuzzel --dmenu` al cancelar (a diferencia de
  `clipboard-menu` y `wallpaper-menu`, que hacen `|| exit 0`). En
  `audio-output-menu`, además, `pactl list sinks` se ejecuta una vez por cada
  salida dentro del bucle.
- **B2 — Ventana `disk-unlock` sin regla flotante:**
  `home/.local/bin/disk-manager` (L249) abre `foot --app-id disk-unlock`, pero
  no figura en `home/.config/sway/config.d/50-rules.conf` (L26–L45), así que
  abre en mosaico en lugar de flotante centrada como el resto de las ventanas
  auxiliares (`audio-floating`, `impala-floating`, `bluetui-floating`,
  `battery-floating`).
- **B3 — Polling evitable en Waybar (`custom/dnd` y `custom/disk`):**
  En `home/.config/waybar/config.jsonc` (L53–L69), `custom/dnd` consulta cada
  5 s y `custom/disk` cada 60 s sin `signal`, por lo que activar No molestar o
  conectar/montar un disco tarda en actualizarse en la barra. Con señales
  (`RTMIN+9` desde `notification-mode --toggle`, `RTMIN+10` desde `disk-notify`
  y `disk-manager`) actualiza al instante y reduce wakeups en el Celeron.
- **B4 — Detalles menores en `check.sh` y `40-keybindings.conf`:**
  - `check.sh`: `usage()` (L16–L29) no menciona UPower; `check_power()`
    (L465–L475) no distingue falta de acceso al bus de sistema como `check_iwd`
    y `check_nftables`; `check_samba()` (L488–L498) repite `if [ "$severity" = "warn" ]`
    en vez de usar `report`; el comentario de `check_nightlight()` (L809–L810)
    aún menciona Waybar aunque el módulo ya no existe en la barra.
  - `home/.config/sway/config.d/40-keybindings.conf` (L203–L205): anteponer
    `LC_ALL=C` a `wpctl get-volume` blinda el cálculo con `awk` frente a una
    eventual coma decimal en `es_AR.UTF-8` (verificado: con `0,75`, `gawk`
    imprime `0%`).

---

## Preguntas para la charla con Claude

1. **H1 (`suspend-if-no-audio`):** ¿preferís escribir el PID desde el padre
   (`setsid "$SELF" --wait &` sin `-f`) o usar un archivo/lock sincronizado, y
   cancelar también desde `before-sleep`?
2. **H3 (`cliphist`):** ¿movemos la base a `$XDG_RUNTIME_DIR/cliphist.db`
   (100 % RAM) mediante `environment.d` + `sway-cliphist.service`?
3. **H5 (`waybar-music`):** ¿`mpv` fuera de PyRadio debería mostrarse y
   controlarse en la barra o quedar excluido de `active_source()`?
4. **H6 (`restore.sh`):** cuando se pasa solo una pieza de sistema (p. ej.
   `./restore.sh --power`), ¿conviene dejar el comportamiento actual y aclarar
   `--no-user --no-yazi` en `README.md`, o que los flags de sistema no disparen
   restauración de `$HOME` salvo que se pida explícitamente?
5. **B3 (Waybar):** ¿reemplazamos el polling de `custom/dnd` y aceleramos
   `custom/disk` con señales `RTMIN`, manteniendo un fallback o solo por señal?

## Propuesta de implementación sugerida

1. **Bloque 1 (seguridad y energía):** H1, H2 y H3, con sus tests en
   `tests/test-session-scripts.sh`.
2. **Bloque 2 (discos, música, restaurador y Yazi):** H4, H5, H6 y H7, con
   tests en `tests/test-ui-scripts.sh` y `tests/test-restore.sh`.
3. **Bloque 3 (prolijidad):** B1–B4.

Estado de todas las propuestas: **pendientes de discusión y autorización**.

---

## Estado

Revisión de Claude (2026-11-20): H1-H5, B1 y B2 confirmados en el código;
H6 real pero de riesgo bajo (copias en `600` y `backups/` fuera de Git);
H7 depende de cómo Yazi resuelve prefijos (sin verificar). Orden acordado
con Maxi: H2+B2, H1, H3, H4+H5.1, H6 y el resto.

| Hallazgo | Estado |
| --- | --- |
| H2 «No molestar» y batería crítica | Resuelto en `626bca5`. Aplicado y probado: con `makoctl mode -a do-not-disturb`, la notificación `-u critical` se ve y la `-u normal` no (captura de pantalla). |
| B2 `disk-unlock` flotante | Resuelto en `626bca5`. El test exige regla en Sway para toda ventana con `app-id` propio. |
| H1 carrera en `suspend-if-no-audio` | Resuelto en `11b3c42`. En la Conectar la carrera se daba 1 de cada 200 veces (no 1 de 10). Arreglo con un turno: `--cancel` lo borra antes que nada y la espera solo suspende si sigue vigente; además mata el `sleep` en curso y `before-sleep` cancela. Test determinista con un `setsid` lento (el código viejo falla siempre) y red de seguridad que mata las esperas del test al salir. Medido: 0 esperas vivas en 250 intentos. |
| H3 portapapeles en el disco | Resuelto en `4f357ce`, test aislado en `fa77cb6`. La base va en `%t/cliphist/db` (RAM): la fija `sway-cliphist.service`, `clipboard-menu` usa la misma ruta y fish la exporta (no `environment.d`: Sway arranca desde fish y no lo lee). `check.sh` avisa si queda la base vieja. |
| H4-H7, B1, B3, B4 | Pendientes. |

### Aplicado en la Conectar (2026-11-20)

`./restore.sh --no-yazi -y` (backup `restore-20261120-203743-694918160-32176`),
después `swaymsg reload` y `makoctl reload`. Solo cambiaron
`~/.config/mako/config` y `~/.config/sway/config.d/50-rules.conf` (comparado
contra el backup). `tests/run-all.sh --sway` sin fallas.

**Ojo:** esa restauración se corrió por error como `DRY_RUN=1 ./restore.sh`,
creyendo que era una simulación. `restore.sh` ignora esa variable (la pone en
`0` en la línea 8): el modo de prueba es `./restore.sh --dry-run`.

Para deshacer: `./restore.sh --rollback backups/restore-20261120-203743-694918160-32176`,
`git revert 626bca5` y recargar Sway y mako.

### Aplicado en la Conectar (2026-11-20, H1 y H3)

- **H1:** `./restore.sh --no-yazi -y` (backup `restore-20261120-205212-304561877-142214`)
  y `systemctl --user restart swayidle.service`. Antes, `--dry-run` y comparación
  con `$HOME`: solo cambiaban `start-idle` y `suspend-if-no-audio`. No había
  esperas corriendo.
- **H3:** `./restore.sh --no-yazi -y` (backup `restore-20261120-205830-707774401-207227`),
  `systemctl --user restart sway-cliphist.service` y, con OK de Maxi,
  `rm -rf ~/.cache/cliphist`. Verificado: la base está en `/run/user/1000/cliphist/db`
  y `check.sh` da «historial del portapapeles fuera del disco». En el SSD, lo
  borrado queda en bloques libres hasta el próximo TRIM (`fstrim.timer`, semanal).
  El servicio queda con la variable al instante; Sway y las terminales ya
  abiertas la toman en la próxima sesión (mientras tanto `clipboard-menu` usa
  la misma ruta por su cuenta).

Para deshacer: `./restore.sh --rollback <backup>`, `git revert <commit>` y
reiniciar el servicio correspondiente.
