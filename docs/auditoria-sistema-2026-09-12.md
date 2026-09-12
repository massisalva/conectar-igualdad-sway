# Auditoría integral del sistema - 2026-09-12

## Cierre posterior al reinicio

El equipo se reinició y ya ejecuta `7.2.4-zen2-1-zen`. Desde una terminal de
la sesión real se completó `./check.sh --system --sudo`.

## Estado comprobado antes del reinicio

- Raíz ext4 de 468 GB: 25 GB usados (6 %); `/boot`: 54 MB usados (6 %).
- 7.6 GiB de RAM, 5.8 GiB disponibles; zram de 3.8 GiB sin uso.
- Base de datos de pacman íntegra.
- Configuración de usuario idéntica a la versionada en el repositorio.
- Listas de paquetes pacman y AUR completas.
- Pruebas `test-restore.sh` y `test-ui-scripts.sh` correctas.
- JSON de Waybar y scripts Bash válidos.
- Repositorio limpio y sincronizado con `origin/main`.
- Sin secretos, contraseñas, tokens ni claves privadas versionadas.

La configuración versionada de SSH deshabilita root y autenticación por
contraseña. El firewall versionado usa política `drop` para la entrada y limita
SSH y LocalSend a la LAN de confianza.

## Resultado del chequeo posterior al reinicio

El resultado inicial fue de 1 fallo y 8 advertencias, sin problemas operativos
en Sway, servicios, red, almacenamiento o configuraciones de sistema:

- No hay unidades de sistema fallidas. SMART de `/dev/sda` es saludable.
- SSH, nftables, iwd, systemd-resolved, sysctl, systemd-boot y las unidades de
  sesión están activos y coinciden con la configuración versionada.
- Los cuatro eventos de prioridad `err` del journal corresponden a avisos
  conocidos al iniciar: SGX no soportado por BIOS, TDX no soportado por la
  plataforma, un certificado X.509 no cargado y el aviso de región de memoria
  reservada de i915. No hay síntomas ni servicios afectados, por lo que no
  requieren acción.
- `python-keyutils` sigue siendo un paquete huérfano de aproximadamente 100
  KiB. No se retiró; si no se usa manualmente, se puede quitar de forma
  opcional:

   ```sh
   sudo pacman -Rns python-keyutils
   ```

- El fallo y las cinco advertencias de Yazi eran falsos positivos:
  `yazi --debug` necesita una TTY aun cuando `check.sh` se lanzó desde una
  terminal, porque su salida se captura. El tema y las cinco dependencias
  (`pdftoppm`, `magick`, `fzf`, `chafa` y `zoxide`) están presentes. El
  verificador ahora consulta directamente `theme.toml` y los ejecutables.
- La advertencia restante se debe a que este informe aún no está agregado a
  Git. Es esperable hasta versionarlo.

## Estado final

La auditoría queda cerrada una vez que se ejecute nuevamente el verificador
con este ajuste. La única decisión funcional opcional restante es retirar
`python-keyutils`.
