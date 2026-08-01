# Headroom con Codex

Headroom se ejecuta como proxy de usuario en `127.0.0.1:8787`. Codex conserva
su autenticación de OpenAI y envía las solicitudes del proveedor integrado a
ese endpoint mediante la clave global `openai_base_url`.

La configuración del proveedor pertenece a `~/.codex/config.toml` y no se
versiona: Codex ignora claves de proveedor dentro de `.codex/config.toml` de un
proyecto y el archivo global puede contener preferencias personales.

## Instalación

Se usa `uv` para aislar Headroom de Python y de los paquetes del sistema:

```sh
uv tool install --python 3.13 'headroom-ai[proxy,code]'
headroom install apply \
  --preset persistent-service \
  --runtime python \
  --scope user \
  --providers manual \
  --target codex \
  --backend openai \
  --mode cache \
  --code-aware \
  --no-telemetry
```

Agregar al nivel raíz de `~/.codex/config.toml`, antes de cualquier tabla:

```toml
openai_base_url = "http://127.0.0.1:8787/v1"
```

El perfil evita los extras `all`, porque incorporan PyTorch y bibliotecas CUDA
innecesarias para la GPU Intel de este equipo.

## Operación

```sh
headroom install status
headroom doctor
headroom perf --hours 24
systemctl --user status headroom-default.service
```

`headroom doctor` 0.33.0 puede advertir que Codex no está enrutado cuando se usa
la clave oficial `openai_base_url`: su detector busca una tabla de proveedor con
nombre Headroom. La comprobación real es ejecutar una sesión nueva de Codex y
confirmar que aparezca en `headroom perf`.

## Actualización

```sh
uv tool upgrade headroom-ai
headroom install restart
headroom doctor
```

## Desactivación

```sh
headroom install remove
```

Después hay que retirar manualmente `openai_base_url` de
`~/.codex/config.toml`. Ningún token, clave, log o estado de Headroom debe
agregarse al repositorio.
