# Auditoría integral del sistema - 2026-10-25

## Resultado

La auditoría confirmó que el sistema Arch Linux + Sway de la netbook Conectar
Igualdad SF20GM7 se mantiene saludable. No se detectaron paquetes huérfanos ni
errores de software durante el arranque. Los mensajes `i915` sobre la región
reservada y `integrity` al cargar un certificado X.509 son avisos inocuos de
firmware/UEFI conocidos en este equipo Gemini Lake.

## Acciones aplicadas

- Se eliminó `~/.local/bin/agy.1792966503187175717.old` (207 MiB), respaldo
  obsoleto dejado por una actualización de Antigravity.
- Se limpió `~/.cache/yay` (413 MiB de fuentes y árboles de compilación AUR).
- Se eliminaron residuos de navegadores desinstalados: configuraciones de
  Vivaldi y Vivaldi Snapshot, y cachés/datos de Qutebrowser (unos 7.3 MiB).

La recuperación total aproximada fue de **627 MiB**. Estos elementos fueron
eliminados por ruta explícita; no afectan la configuración de los navegadores
actualmente instalados.

## Paquetes y caché de Pacman

- No hay paquetes huérfanos.
- `docs/pkglist-aur.txt` coincide con los paquetes AUR explícitos.
- `libnotify`, `nftables`, `playerctl` y `python` deben conservarse como
  explícitos para que `pacman -Qqe` coincida con
  `docs/pkglist-pacman.txt`.
- La caché de Pacman conserva tres versiones. Pasar a dos con `paccache -rk2`
  libera aproximadamente 1.33 GiB (158 paquetes antiguos).

Las acciones administrativas se ejecutaron desde la sesión gráfica local:

```sh
sudo pacman -D --asexplicit libnotify nftables playerctl python
sudo paccache -rk2
./check.sh --system --sudo
```

Los cuatro paquetes quedaron marcados como explícitos. `paccache` retiró 158
versiones antiguas y liberó **1.33 GiB**.

## Archivos `.pacnew`

Se revisaron los cinco archivos pendientes. No se reemplazó ningún archivo de
forma automática para preservar la configuración activa.

| Archivo | Decisión recomendada |
|---|---|
| `/etc/pacman.d/mirrorlist.pacnew` | Actualizar mediante `pacdiff` o regenerar una lista de espejos; conservar los servidores elegidos manualmente. |
| `/etc/bluetooth/main.conf.pacnew` | Integrar las nuevas opciones comentadas de `ChannelSounding`; preservar `AutoEnable=true` si se desea mantener el comportamiento actual. |
| `/etc/locale.gen.pacnew` | Conservar `es_AR.UTF-8 UTF-8` descomentado e incorporar solamente la nueva entrada `hrx_BR.UTF-8` si hiciera falta. |
| Perfiles `tpm2-tss` ECC y RSA | Adoptar la versión nueva tras revisar con `pacdiff`: moderniza la sintaxis y agrega `noda` al SRK. |

Para resolverlos interactivamente:

```sh
sudo DIFFPROG='diff -u' pacdiff
```

## Repositorio

Al inicio de la auditoría, `main` estaba dos commits por delante de
`origin/main`:

- `2e56737 fix(pyradio): update Catppuccin theme format`
- `db611f4 fix(check): distinguish nftables permission errors`

La publicación se completó en `origin/main` junto con los commits pendientes.

## Validación administrativa final

`./check.sh --system --sudo` finalizó con **0 fallos y 2 advertencias**:

- Las cinco entradas de error del journal de arranque son los avisos inocuos
  de `i915` e `integrity` ya identificados durante la auditoría.
- La diferencia temporal respecto de `origin/main` se informó antes del
  `git push`, que posteriormente terminó correctamente.

Se validaron sin incidencias SMART en `/dev/sda`, configuración efectiva de
SSHD, ruleset vivo de nftables, servicios de usuario y sistema, ZRAM e
integridad del repositorio.
