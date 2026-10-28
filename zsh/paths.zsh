# =============================================================================
# Per-user tool directories
#
# Tools installed by their own upstream installers (uv, Bun, Deno, pnpm,
# OpenCode, Antigravity) live outside the system PATH. Add them here so a new
# zsh session — including one started with `exec zsh` right after installation
# — can find them without restarting Termux or proot-distro.
# =============================================================================

typeset -U path 2>/dev/null || true

_shell_setup_path_dirs=(
    "$HOME/.local/bin"
    "$HOME/.opencode/bin"
    "$HOME/.bun/bin"
    "$HOME/.cargo/bin"
    "$HOME/.deno/bin"
    "$HOME/.local/share/pnpm"
    "$HOME/.antigravity/antigravity/bin"
    "$HOME/.antigravity-ide/antigravity-ide/bin"
)

for _shell_setup_dir in "${_shell_setup_path_dirs[@]}"; do
    [[ -d "$_shell_setup_dir" ]] && path=("$_shell_setup_dir" $path)
done

export PATH
unset _shell_setup_dir _shell_setup_path_dirs
