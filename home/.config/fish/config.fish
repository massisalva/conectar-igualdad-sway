if status is-interactive
    # Commands to run in interactive sessions can go here
end

# Antigravity CLI y ejecutables de usuario
if test -d "$HOME/.local/bin"
    fish_add_path "$HOME/.local/bin"
end

# Historial del portapapeles en RAM, como sway-cliphist.service: lo heredan Sway
# y lo que se corre a mano (auditoría 2026-11-20, H3).
if set -q XDG_RUNTIME_DIR
    set -gx CLIPHIST_DB_PATH "$XDG_RUNTIME_DIR/cliphist/db"
end

# Arranca Sway si estamos en TTY1
if status is-interactive
    if test -z "$WAYLAND_DISPLAY" -a "$XDG_VTNR" = "1"
        exec sway
    end
end

# Starship prompt
if status is-interactive
    if type -q starship
        starship init fish | source
    end
end
