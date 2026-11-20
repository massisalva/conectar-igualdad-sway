# Auditoría del proyecto — 2026-11-19

Documento de discusión para Maxi y Claude. Las propuestas están pendientes de
autorización: documentarlas no autoriza implementarlas ni aplicarlas al sistema.

## Alcance y estado revisado

Revisión de `conectar-igualdad-sway`, sobre HEAD
`9b3f3360955d1d3985a229e9d46ebd9ca1d4a5b5`, incluyendo los cambios locales
presentes durante la auditoría. Se revisaron el restaurador, el verificador,
scripts de sesión e interfaz, unidades de usuario, configuraciones de sistema,
documentación y pruebas.

La auditoría no certifica el estado efectivo del equipo, las reglas activas del
firewall, SMART, actualizaciones o servicios privilegiados. No se ejecutó una
restauración sobre el HOME real ni se aplicaron configuraciones del sistema.
Las reproducciones que escriben archivos se hicieron en directorios temporales.

Había cambios locales previos en `check.sh`, `restore.sh`, scripts y pruebas.
Al preparar este documento aparecieron también modificaciones adicionales en
las pruebas y `tests/test-session-scripts.sh` sin seguimiento. No fueron creadas
por esta auditoría ni deben sobreescribirse. Los resultados de pruebas que se
indican abajo corresponden a la ejecución durante la auditoría; hay que repetirlos
sobre el estado final que se acuerde implementar.

## Resultado de las verificaciones

| Comprobación | Resultado observado |
| --- | --- |
| `bash tests/test-restore.sh` | OK |
| `bash tests/test-ui-scripts.sh` | OK |
| `bash tests/test-check.sh` | OK |
| Sintaxis Bash de scripts y pruebas existentes al revisar | OK |
| Parseo con `tomllib` de los cinco archivos TOML de `home/` | OK |
| Enlaces Markdown locales de README y documentos directamente en `docs/` | Sin destinos ausentes |
| `git diff --check` | OK |
| `python tests/test-wallpaper-sway.py` | No pudo completar: Sway no abrió el socket Wayland en este entorno |
| ShellCheck | No disponible; no ejecutado |

La prueba de Sway emitió `Unable to open wayland socket`, seguida de una
aserción del backend. Esto limita la validación gráfica: no prueba por sí solo
que el selector de fondos tenga un defecto.

## H1 — Permisos modificados a través de enlaces, sin recuperación efectiva

**Prioridad alta. Confirmado con reproducción aislada.**

Referencias: `restore.sh`, funciones `restore_user_files`, `backup_target` y
`validate_user_parent`; ajustes de permisos de `~/.ssh/authorized_keys` y
`~/.config/streamrip/config.toml`.

El restaurador usa `chmod 600` sobre esos destinos si son archivos. Esa prueba
acepta enlaces a archivos y `chmod` sigue el enlace final. El respaldo con
`cp -a` conserva el enlace, pero no los permisos originales del archivo al que
apunta. La validación de los padres de los archivos copiados desde `home/` no
cubre todos estos destinos adicionales.

**Reproducción:** en un HOME temporal, crear ambos destinos como enlaces a dos
archivos externos al HOME, con modo `644`. Ejecutar el restaurador con los
comandos externos simulados mediante `tests/fixtures/mock-bin`, `--no-yazi -y`,
y backups temporales. Ambos archivos externos pasan a `600`. Ejecutar rollback
del respaldo generado: finaliza correctamente, pero ambos siguen en `600`.

**Cambio propuesto:** definir la política para enlaces en archivos cuyo modo se
endurece, validar todos esos destinos antes de empezar y evitar cambios fuera
del ámbito admitido. Si se permite seguir enlaces, respaldar y recuperar también
el estado del destino real; la alternativa más simple es rechazarlos con un
mensaje claro antes de modificar archivos.

**Aceptación:** pruebas con enlace final externo, directorio padre enlazado,
enlace roto y archivo normal. Un rechazo no debe dejar cambios parciales; un
rollback admitido debe recuperar los modos originales.

## H2 — El rollback admite destinos de sistema ajenos al proyecto

**Prioridad alta. Confirmado mediante simulación sin cambios de sistema.**

Referencia: `restore.sh`, `is_allowed_target` y `validate_rollback`.

La validación admite cualquier ruta bajo `/etc/` y `/boot/`, además de HOME.
No comprueba que una ruta de sistema pertenezca al conjunto administrado por
este proyecto.

**Reproducción segura:** un manifiesto temporal con la línea
`missing<TAB>/etc/audit-demostracion-no-existe`, pasado a
`restore.sh --rollback DIR --dry-run -y`, fue aceptado y mostró
`sudo rm -f /etc/audit-demostracion-no-existe`.

Esto requiere que el usuario ejecute ese rollback; para modificar rutas
privilegiadas también requiere sudo. No demuestra ejecución remota ni una
elevación autónoma de privilegios. Un backup confiable sigue siendo necesario.

**Cambio propuesto:** enumerar los destinos de sistema administrados y rechazar
los demás antes de cualquier acción. Revisar también los directorios padre
enlazados de destinos de sistema. Acordar cómo tratar backups antiguos si cambia
la lista de archivos administrados.

**Aceptación:** un manifiesto con una entrada válida seguida de una ruta de
sistema no admitida debe rechazarse entero, sin cambios. Mantener las pruebas
existentes contra traversal y escapes mediante enlaces en HOME.

## H3 — Limpieza de binarios basada en ausencia, no en procedencia

**Prioridad media. Comportamiento confirmado por lectura del código.**

Referencia: `restore.sh`, `prune_user_bin`; `docs/local-bin-keep.txt`.

`--prune` considera eliminables los archivos y enlaces de `~/.local/bin` que
no están en el repositorio ni en la lista manual de excepciones. Una herramienta
personal nueva puede ser legítima aunque no figure allí. Hay confirmación y
respaldo: no es una eliminación silenciosa ni irrecuperable.

**Cambio propuesto:** retirar automáticamente solo archivos cuya instalación
previa por el proyecto pueda acreditarse mediante un inventario. Mostrar los
archivos desconocidos para revisión y conservarlos por defecto. No eliminar las
excepciones actuales durante la transición.

**Aceptación:** una herramienta externa nueva sobrevive a `--prune`; un archivo
antes administrado y ahora retirado puede limpiarse con respaldo y rollback.

## H4 — SSH inválido queda instalado si falla la validación

**Prioridad media. Ruta de fallo identificada por lectura; no aplicada al SSH real.**

Referencia: `restore.sh`, `install_sshd_config`.

Primero se instala el archivo y después se ejecuta `sshd -t`. Si falla, el
script se detiene antes de recargar el servicio, pero el archivo inválido queda
en disco. Existe backup para recuperarlo manualmente; falta recuperación
automática en esa ruta de fallo.

**Cambio propuesto:** recuperar los archivos anteriores si falla `sshd -t`,
mantener el diagnóstico y devolver error. Evaluar por separado qué hacer si la
validación pasa pero falla la recarga.

**Aceptación:** con `sudo`, `sshd` y `systemctl` simulados, forzar validación
fallida y verificar que no hay recarga y que se recupera el archivo anterior,
incluyendo el caso en que antes no existía.

## H5 — Alcance del rollback y efectos que no son archivos

**Prioridad media. Mejora de contrato y documentación; no todo es un error.**

Referencias: `restore.sh`, `restore_user_files`, instaladores de sistema y
`rollback_backup`; README, sección «Volver atrás».

La restauración también habilita/inicia MPD, cambia preferencias con gsettings,
crea directorios y, según los flags, instala paquetes o altera servicios.
El rollback recupera los archivos registrados y ciertos permisos, pero no
todos estos efectos. El README ya dice que el rollback restaura archivos y que
puede requerir recargar servicios: no debe presentarse como una promesa explícita
de reversión completa incumplida.

**Cambio propuesto:** mostrar en la vista previa y al terminar los efectos
reversibles mediante manifiesto y los que quedan fuera. Considerar registrar
los valores previos de preferencias y el estado de MPD si resulta útil, sin
prometer desinstalaciones automáticas de paquetes.

**Aceptación:** documentación y salida describen el mismo contrato. Si se amplía
la reversión, probar estados previos activo/inactivo y habilitado/deshabilitado,
y evitar perder cambios posteriores del usuario sin una decisión explícita.

## H6 — Luz nocturna apagada voluntariamente se informa como fallo

**Prioridad media. Inconsistencia identificada por lectura.**

Referencias: `home/.local/bin/nightlight-mode`, `check.sh`,
`check_session_processes`.

El menú permite detener `wlsunset.service`, pero el verificador exige que esté
activo junto con el resto de servicios de sesión. Por eso una preferencia válida
produce un fallo de salud.

**Cambio propuesto:** admitir el estado inactivo cuando es una elección del
usuario y distinguirlo de `failed` o de una unidad ausente. Acordar si hace falta
persistir la elección: actualmente el target vuelve a solicitar el servicio en
una nueva sesión.

**Aceptación:** estados activo, apagado voluntario, fallido y unidad ausente
producen diagnósticos diferentes y coherentes.

## H7 — Precisión de las verificaciones de Git y nftables

**Prioridad media. Confirmado por lectura; son dos ajustes independientes.**

### H7a — «Sincronizado» significa comparación con una referencia local

Referencia: `check.sh`, `check_repo_state`.

Compara HEAD con la referencia upstream almacenada localmente y puede imprimir
«repo sincronizado» sin consultar el servidor. Eso no verifica el estado remoto
actual.

**Cambio propuesto:** decir «HEAD coincide con la referencia upstream local» y
ofrecer, si interesa, una consulta remota explícita. No incorporar acceso de red
obligatorio a una comprobación local.

**Aceptación:** la salida no afirma sincronización remota cuando no se consultó
el servidor; una eventual consulta informa claramente errores de conexión.

### H7b — El modo estricto puede conservar advertencias por falta de acceso

Referencia: `check.sh`, `check_nftables`, ramas de consulta de systemd sin salida
o con errores de permisos.

Algunas ramas llaman a `warn` y retornan incluso con `STRICT_SYSTEM=1`, en lugar
de aplicar la severidad calculada. Hay pruebas existentes que toleran restricciones
del entorno: endurecer esto requiere revisar su contrato, no cambiarlas a ciegas.

**Cambio propuesto:** acordar una regla uniforme: en modo normal, «no verificado»
puede ser advertencia; en modo estricto, un control obligatorio no verificable
debe impedir certificar el resultado como completo. El texto debe diferenciar
falta de evidencia de evidencia de un firewall incorrecto.

**Aceptación:** pruebas de consulta correcta, consulta denegada, unidad ausente y
ruleset incorrecto, tanto en modo normal como estricto.

## H8 — Validación repetible y automatización

**Prioridad media/baja. Propuesta de mantenimiento.**

Las suites actuales pasan, pero H1 y H2 muestran huecos de cobertura. Además,
`check.sh` mezcla comprobaciones del repositorio con el estado de una máquina
personal, lo que complica usarlo como validación portable.

**Cambios propuestos:**

- Un comando único para sintaxis, configuraciones y pruebas aisladas del repo.
- Añadir regresiones para H1–H7, evitando pruebas que solo busquen texto del código.
- Integrar ShellCheck con una política explícita para avisos y excepciones.
- Ejecutar las comprobaciones portables en CI. Elegir la plataforma con el dueño;
  no asumir si la fuente principal será GitHub o Forgejo.
- Mantener la prueba con Sway real como integración identificable y distinguir
  dependencias o restricciones del entorno de un fallo funcional.
- Revisar e integrar la nueva suite local `test-session-scripts.sh` después de
  leerla y ejecutarla; no se certificó en la primera tanda de esta auditoría.

**Aceptación:** una máquina sin sesión gráfica puede validar el repositorio sin
alterar su HOME real, acceder a servicios de producción ni necesitar sudo.

## Limpieza: qué hacer y qué preservar

La limpieza propuesta se centra en comportamientos ambiguos, validación común y
documentación coherente. No se identificó una razón suficiente para borrar
fondos, auditorías históricas o respaldos.

Tamaños observados como contexto, no como diagnóstico: `.git` aproximadamente
17 MiB, `backups/` 32 MiB y `home/Imágenes/` 7,6 MiB. Los respaldos ya están
excluidos por `.gitignore`. No se propone reescribir el historial Git ni purgar
backups automáticamente.

Preservar los cambios locales existentes. Antes de implementar, comparar de nuevo
el árbol de trabajo: puede haber trabajo simultáneo de Claude u otra sesión.

## Propuesta de implementación para acordar

1. **Restauración segura:** H1 y H2, con reproducciones convertidas en pruebas.
2. **Recuperación y limpieza:** H3, H4 y contrato de H5.
3. **Diagnósticos precisos:** H6 y H7.
4. **Mantenimiento:** H8 y documentación final del comportamiento aprobado.

Cada bloque debe poder revisarse por separado y tener validación pertinente.
No hace falta instalar nada en el sistema real para revisar las correcciones de
código y las pruebas. Aplicar configuraciones activas, reiniciar servicios,
eliminar archivos, publicar cambios o hacer push no está autorizado por este
documento.

## Preguntas para la conversación con Claude

- ¿Rechazar enlaces en los archivos sensibles o soportarlos registrando su destino?
- ¿Cómo mantener compatibilidad con backups antiguos al restringir el rollback?
- ¿Limitar `--prune` a archivos instalados por el proyecto y preservar desconocidos?
- ¿Mantener rollback de archivos con límites explícitos o ampliar efectos recuperables?
- ¿La luz nocturna apagada debe persistir entre sesiones?
- ¿El modo estricto debe fallar si no puede verificar un requisito obligatorio?
- ¿Dónde ejecutar CI y qué validaciones gráficas pueden correr allí?

Estado de todas las propuestas: **pendientes de discusión y autorización**.

## Estado al 2026-11-19 (Claude, con el OK de Maxi)

Respuestas de Maxi a las preguntas: rechazar enlaces; backups viejos válidos
si sus rutas están en la lista; `--prune` conserva lo desconocido; rollback
solo de archivos, con el límite explicado; la luz nocturna apagada no
persiste; `--system` falla si no puede verificar; sin CI.

| Hallazgo | Estado | Commit |
| --- | --- | --- |
| Cambios locales previos (origen sin confirmar) | Revisados y commiteados tal cual; `clipboard-menu` corregido (historial recién creado) y test de luz nocturna arreglado (probaba una opción inexistente) | `efd45d3`, `894e97e` |
| H4 sshd inválido instalado | Resuelto. Subido a prioridad alta: sshd no arrancaría en el próximo reinicio | `cd6b115` |
| H2 rollback con rutas de sistema ajenas | Resuelto (`is_managed_system_target`); cubre las rutas de todos los backups existentes | `cd6b115` |
| H1 chmod a través de enlaces | Resuelto: restore se niega a empezar | `cd6b115` |
| H3 `--prune` por ausencia | Resuelto: `docs/local-bin-retired.txt`, test contra el historial | `579a8fd` |
| H6 luz nocturna apagada como falla | Resuelto: cuatro estados distintos | `579a8fd` |
| H5 alcance del rollback | Resuelto en ayuda, cierre y README | `649d1eb` |
| H7a "sincronizado" | Resuelto | `649d1eb` |
| H7b modo estricto sin acceso | Resuelto con `report()` | `649d1eb` |
| H8 validación repetible | `tests/run-all.sh`. CI descartado. ShellCheck pendiente de instalar (pide sudo) | `649d1eb` |

Cada arreglo tiene un test que falla si se desactiva el arreglo. Ninguno se
aplicó al sistema en vivo: los scripts de `~/.local/bin` se actualizan con la
próxima restauración.
