# Firefox - fluidez en Conectar Igualdad SF20GM7

Fecha de revision: 2026-07-07.

## Diagnostico local

- Perfil activo: `~/.config/mozilla/firefox/krm5yfi5.default-release`.
- Firefox instalado: `152.0.5-1`.
- Equipo: Intel Celeron N4020, 2 nucleos, Intel UHD Graphics 600, 8 GiB RAM.
- RAM disponible durante la revision: alrededor de 6.8 GiB; el cuello de botella probable es CPU/GPU, no memoria.
- Cache de Firefox: `~/.cache/mozilla/firefox/krm5yfi5.default-release`, alrededor de 439 MiB.
- Datos persistentes del perfil: `storage`, alrededor de 76 MiB.
- Extensiones activas relevantes: uBlock Origin, 1Password, Dark Reader, Plasma Integration.
- No se detectaron ajustes personalizados agresivos de GPU, procesos, cache o sessionstore en `prefs.js`.
- Estan desactivados `network.dns.disablePrefetch`, `network.http.speculative-parallel-limit` y `network.prefetch-next`; esto baja trabajo en segundo plano, pero puede hacer que algunas navegaciones parezcan menos inmediatas.
- Al inicio no estaban instalados `intel-media-driver` ni `libva-utils`; se instalaron durante esta revision.
- `vainfo` valida VA-API sobre Wayland con driver Intel iHD 26.1.5.
- Perfiles de decodificacion disponibles: H264, VP8, VP9 y HEVC, entre otros.

## Cambios recomendados

1. Instalar soporte VA-API para Intel:

   ```sh
   sudo pacman -S --needed intel-media-driver libva-utils
   ```

   Estado: aplicado.

2. Cerrar Firefox y verificar VA-API:

   ```sh
   vainfo
   ```

   En este equipo deberia listar perfiles de decodificacion por hardware para Intel iHD.

   Estado: validado.

3. En Firefox, revisar `about:support`:

   - `Window Protocol`: `wayland`.
   - `Compositing`: `WebRender`.
   - En video, probar YouTube u otro sitio y mirar CPU con `btop`.

4. Probar sin Dark Reader durante un dia. En este hardware suele ser la extension con mas costo perceptible, sobre todo en paginas largas o dinamicas. Si hace falta conservar modo oscuro, preferir el modo oscuro nativo del sitio o activar Dark Reader solo por sitio.

   Estado: aplicado. Dark Reader quedo deshabilitado en `extensions.json` con backup del perfil en `~/.config/mozilla/firefox/krm5yfi5.default-release/codex-backups/firefox-darkreader-disable-20260707-202848`.

5. Mantener uBlock Origin activo. En notebooks chicas generalmente mejora fluidez porque evita scripts, publicidad y trackers.

6. Si la carga de paginas se siente lenta, probar revertir los bloqueos de prefetch desde `about:config`:

   ```text
   network.dns.disablePrefetch = false
   network.http.speculative-parallel-limit = 6
   network.prefetch-next = true
   ```

   Si se prioriza menor consumo en segundo plano, dejar los valores actuales.

## Ajustes que no conviene forzar de entrada

- No fijar manualmente cantidad de procesos de contenido salvo que haya un problema claro de RAM. Con 8 GiB y el uso actual, Firefox puede gestionarlo mejor que un valor estatico.
- No desactivar WebRender en Intel UHD 600 sin una falla concreta; normalmente ayuda mas de lo que perjudica.
- No limpiar `places.sqlite` ni bases del perfil a mano. Si hiciera falta, usar opciones internas de Firefox o crear un perfil nuevo de prueba.
