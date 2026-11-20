# Auditoría profunda — 2026-11-19 (Claude)

Revisión de solo lectura sobre `69e5e93`, complementaria a
`auditoria-proyecto-2026-11-19.md` (que cubrió `restore.sh` y `check.sh`).
Foco: configuraciones de sistema, los 25 scripts de `~/.local/bin`, Sway,
Waybar, servicios de usuario y el repo público. Se leyó todo el código de
esas áreas y se verificó en el equipo con comandos de diagnóstico, sin
cambiar nada. Lo que no se pudo comprobar está marcado **(sin verificar)**.

## Prioridad alta

### A1 — Con batería crítica no pasa nada: la Conectar se apaga de golpe

UPower está instalado y configurado (`PercentageAction=2.0`,
`CriticalPowerAction=Auto`), pero es un servicio que arranca solo cuando
alguien lo pide por D-Bus, y en esta sesión nadie lo pide: Waybar usa un
módulo propio que lee `/sys`. Verificado: `upower.service` *disabled* e
*inactive (dead)*, sin entradas en el journal del arranque. `waybar-battery`
solo pinta la clase `critical`; no avisa ni actúa.

Efecto: al agotarse la batería, corte de energía sin aviso ni apagado
ordenado (riesgo de perder trabajo sin guardar y de dañar archivos abiertos).

Propuesta: habilitar UPower al arranque (`sudo systemctl enable --now
upower`, lo corre Maxi) y que `check.sh` lo verifique. Sumar una
notificación al 10 % y otra crítica al 5 % (un servicio de usuario liviano o
desde `waybar-battery`, recordando el último aviso para no repetirlo). Qué hace
`Auto` sin swap en disco (solo zram, sin hibernación): según UPower, apaga
**(sin verificar)**.

### A2 — La suspensión automática puede no llegar nunca

`start-idle` usa `timeout 1800 suspend-if-no-audio`. swayidle ejecuta ese
comando **una sola vez** por período de inactividad (man swayidle,
verificado). Si a los 30 minutos suena música, no suspende; si la música
termina a los 31, no hay otro intento hasta que alguien toque el equipo: la
Conectar queda encendida con la pantalla apagada (toda la noche si fue una
radio antes de dormir).

Propuesta: que `suspend-if-no-audio` espere en un bucle (por ejemplo, cada
60 s) mientras haya audio y suspenda cuando termine, y que el `resume` de ese
mismo timeout corte la espera si el usuario vuelve. Test con `pactl`
simulado: audio que termina → suspende; actividad → no suspende.

## Prioridad media

### M1 — `disk-notify` puede morir sin que nadie lo note

Si `udevadm monitor` termina, el bucle de lectura ve fin de archivo y el
script sale con código 0. La unidad tiene `Restart=on-failure`, que no
relanza una salida "exitosa": los avisos de discos dejan de funcionar hasta
el próximo inicio de sesión. Propuesta: terminar con error cuando el monitor
se corta (o `Restart=always` con `RestartSec`), con un test.

### M2 — "Expulsar" falla en discos con varias particiones montadas

`disk-manager` desmonta solo la partición elegida y después pide
`udisksctl power-off` del disco entero; si otra partición sigue montada, la
operación falla y el aviso no dice por qué **(sin verificar: no había un
disco de varias particiones para probar)**. Propuesta: desmontar todas las
particiones montadas del disco antes de apagarlo y nombrar la que impida
hacerlo.

### M3 — Datos sensibles en claro en el disco

El disco (`sda2`, ext4) no está cifrado y el historial del portapapeles
(`~/.cache/cliphist/db`, 34 entradas al revisar) sobrevive a los reinicios:
lo que se copió alguna vez (contraseñas incluidas) queda en el disco. Para
una netbook que sale de casa, es lo que más expone si se pierde.
Propuestas, de menor a mayor: limitar el historial (`cliphist -max-items`) y
vaciarlo al iniciar sesión; no guardar lo que un gestor de contraseñas marca
como sensible (soporte en cliphist 0.7 **(sin verificar)**). Cifrar el disco
implica reinstalar: es una decisión aparte.

### M4 — El repo es público y el historial contiene tu email personal

GitHub `massisalva/conectar-igualdad-sway` es **público**. Los commits
`769e72e` y `5b2140f` (2026-06) versionaron `home/.ssh/authorized_keys`; las
claves son públicas (no es una filtración de credenciales), pero una lleva
como comentario el email personal. Hoy el archivo ya no está y los commits
nuevos usan el email noreply. Sacarlo del historial exige reescribirlo y
forzar el push en Forgejo y GitHub; la alternativa es aceptarlo. Decide Maxi.

## Prioridad baja

- **B1** — Un pendrive cifrado (LUKS) aparece con "Montar", que siempre
  falla: ocultarlo o sumar "Desbloquear" (`udisksctl unlock`).
- **B2** — `screenshot-menu` usa `set -e`: si `grim` falla, sale sin avisar.
- **B3** — `waybar-music` manda todos sus errores a `/dev/null`
  (`exec 2>/dev/null`): si falla, no queda rastro para diagnosticar.
- **B4** — `disk-notify` recuerda los discos ya avisados en
  `$XDG_RUNTIME_DIR`; si se perdió el evento de desconexión (servicio caído),
  ese disco no vuelve a avisar en la sesión.
- **B5** — El firewall confía en `192.168.1.0/24` en cualquier red: en un
  Wi-Fi ajeno con el mismo rango, el puerto 22 queda abierto a esa red
  (mitigado: SSH solo acepta clave, sin contraseña).
- **B6** — `.git` ocupa 18 MB con 249 KB empaquetados: objetos sueltos;
  `git gc` lo compacta.

## Lo que está bien

- Firewall con política *drop* en entrada y reenvío; SSH solo por clave, sin
  root, con `AllowUsers`; polkit acotado a usuario activo y grupo
  `storage`; `kptr_restrict`; bootloader sin editor.
- Los scripts citan bien sus argumentos y validan lo que eligen en los menús
  (índices numéricos, enlaces de Deezer, nombres de fondos con caracteres
  raros); los menús de energía piden confirmación.
- Waybar es liviana para un Celeron: `waybar-music` cuesta ~40 ms de CPU
  cada 5 s (<1 % de un núcleo) y escapa el marcado Pango (`"escape": true`).
- La ayuda de atajos (`shortcut-help`) está al día con `40-keybindings.conf`.
- `tests/run-all.sh` en verde, ShellCheck incluido; la prueba de Sway sin
  pantalla también pasa.

## Propuesta de trabajo

1. A1 y A2 (batería y suspensión), con tests. A1 necesita un `sudo` de Maxi.
2. M1 y M2 (discos), con tests.
3. M3: decidir alcance (historial limitado/vaciado al iniciar).
4. M4: decidir si se reescribe el historial público.
5. Bajas, en un solo bloque.

Nada de esto está aplicado.

## Estado

| Hallazgo | Estado |
| --- | --- |
| A1 batería crítica | Resuelto en `9b40e49`. Maxi corrió `./restore.sh --power`: UPower habilitado y activo (`check.sh` lo confirma). Avisos al 10 % y 5 % en `waybar-battery`. |
| A2 suspensión | Resuelto en `9b40e49`. Instalado con `./restore.sh --no-yazi -y` (backup `restore-20261119-215351-424547933-233652`); `swayidle.service` reiniciado para que tome el `resume` que cancela la espera (sin él, la espera podía suspender con el usuario presente). |
| M1 avisos de discos | Resuelto en `b45516e`: disk-notify sale con error si se corta el monitor (`RestartSec=5`). |
| M2 expulsar | Resuelto en el mismo commit: desmonta todas las particiones y nombra la que lo impide. |
| M1 y M2 aplicados | `./restore.sh --no-yazi -y` (backup `restore-20261119-215858-224039899-253456`) y `disk-notify.service` reiniciado: activo, una instancia, `RestartSec=5`. |
| M3 portapapeles | Resuelto en `b925ac0`: se vacía al iniciar sesión y guarda hasta 100 entradas. Lo marcado como sensible ya no se guardaba (cliphist 0.7, verificado en una base temporal). |
| M4 email en el historial público | **Aceptado** por Maxi: reescribir no lo borra de verdad (GitHub conserva los commits por su hash y puede haber clones), cambia todos los hashes que citan las auditorías y obliga a forzar el push en Forgejo y GitHub. Es una clave pública con el email como comentario; los commits nuevos usan el email noreply. |
| B1-B4 | Resueltos en `da912a0`, con tests. |
| B5 SSH en redes ajenas | **Aceptado**: SSH solo admite clave; restringirlo según la red complica el firewall a cambio de poco. |
| B6 `.git` | `git gc`: de 18M a 11M; `git fsck` sin errores. |
