"""Prueba opcional con Sway headless: usa solo HOME, sockets y archivos temporales."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='sway-wallpaper-regression-') as temp:
    base = Path(temp)
    runtime = base / 'runtime'
    runtime.mkdir(mode=0o700)
    home = base / 'home'
    pictures = home / 'Imágenes'
    pictures.mkdir(parents=True)
    mock = base / 'bin'
    mock.mkdir()
    for name, body in [('fuzzel', 'cat >/dev/null\nprintf "001  elegido\\n"\n'), ('notify-send', 'exit 0\n')]:
        file = mock / name
        file.write_text('#!/usr/bin/env bash\n' + body)
        file.chmod(0o755)
    config = base / 'sway.conf'
    config.write_text('xwayland disable\noutput HEADLESS-1 mode 64x64\ninclude ~/.config/sway/config.d/*.conf\n')
    env = os.environ.copy()
    for key in ['SWAYSOCK', 'I3SOCK', 'WAYLAND_DISPLAY', 'DISPLAY', 'DBUS_SESSION_BUS_ADDRESS']:
        env.pop(key, None)
    env.update(HOME=str(home), XDG_RUNTIME_DIR=str(runtime), WLR_BACKENDS='headless', WLR_RENDERER='pixman', WLR_LIBINPUT_NO_DEVICES='1')
    with (base / 'sway.log').open('w+') as log:
        proc = subprocess.Popen(['sway', '--unsupported-gpu', '-c', str(config)], env=env, cwd=base, stdout=log, stderr=log)
        sock = None
        try:
            deadline = time.monotonic() + 6
            while proc.poll() is None and time.monotonic() < deadline:
                sockets = list(runtime.glob('sway-ipc.*.sock'))
                if sockets:
                    sock = str(sockets[0])
                    break
                time.sleep(0.05)
            if not sock:
                log.seek(0)
                raise RuntimeError('No arrancó el compositor aislado:\n' + log.read()[-4000:])
            menu_env = env | {'SWAYSOCK': sock, 'XDG_PICTURES_DIR': str(pictures), 'PATH': str(mock) + ':' + env['PATH']}
            for i, name in enumerate(['fondo con espacios.png', 'fondo "doble", con\\barra; exec touch MARCA.png', 'fondo $(touch MARCA2.png) $mod.png']):
                case_pictures = pictures / str(i)
                case_pictures.mkdir()
                menu_env['XDG_PICTURES_DIR'] = str(case_pictures)
                image = case_pictures / name
                shutil.copyfile(root / 'home/Imágenes/wallpaper-1qowj1.png', image)
                result = subprocess.run(['bash', str(root / 'home/.local/bin/wallpaper-menu')], env=menu_env, cwd=base, capture_output=True, text=True, timeout=5)
                if result.returncode:
                    log.seek(0)
                    raise AssertionError(f'Falló el fondo {name!r}: {result.stderr}\n' + log.read()[-3000:])
                subprocess.run(['swaymsg', '-s', sock, 'reload'], env=env, capture_output=True, timeout=3, check=True)
                assert not any((base / marker).exists() for marker in ['MARCA.png', 'MARCA2.png']), 'Se interpretó un comando del nombre'
                print(f'OK Sway real aislado: {name!r}', flush=True)
        finally:
            try:
                if sock and proc.poll() is None:
                    subprocess.run(['swaymsg', '-s', sock, 'exit'], env=env, capture_output=True, timeout=3)
            finally:
                if proc.poll() is None:
                    proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
