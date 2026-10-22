#!/bin/sh
# Universal trampoline: ensure execution under bash on Termux, macOS, and Linux.
#
# IMPORTANT: proot-distro inherits Termux's environment ($PREFIX, $PATH, etc.)
# into the Linux container. We must detect this case and strip those vars
# before re-execing, otherwise the script picks up Termux's Android binaries
# (wrong dynamic linker, wrong libraries) and fails inside the Linux container.
if [ -z "$BASH_VERSION" ] || [ -n "$POSIXLY_CORRECT" ]; then
    if [ -n "${PD_CONTAINER}" ] || [ "${container}" = "proot-distro" ]; then
        # Inside proot-distro: clear Termux-specific env pollution and use the
        # native Linux bash. unset PREFIX so 'which' and PATH resolution find
        # the container's own tools, not Termux's Android binaries.
        unset PREFIX TERMUX_VERSION LD_PRELOAD
        export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        exec /bin/bash "$0" "$@"
    elif [ -n "$PREFIX" ] && [ -x "$PREFIX/bin/bash" ]; then
        exec "$PREFIX/bin/bash" "$0" "$@"
    elif command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "Error: bash is required to run this script." >&2
        exit 1
    fi
fi

# Shell-Setup Universal Installer
#
# Auto-detects environment (Termux, macOS, Linux) and sets up:
#   - Zsh as default shell
#   - Essential CLI tools (git, mandoc, neovim, which, tree, openssh)
#   - Modular zsh configs from root zsh/
#   - Unified git aliases & submodule shortcuts
#   - User configurations in ~/.config (Neovim ~/.config/nvim, Git accountList ~/.config/git)
#   - Environment-specific base configs (base.bash -> ~/.zsh/base.zsh)
#   - Termux configuration & styling (Termux/.termux -> ~/.termux)
#   - Global Git configuration (.gitconfig & allowed_signers)
#   - SSH key setup helper (~/.ssh/setup.bash)
#   - Optional extensions (Node.js, PHP, Antigravity CLI)
#
# Usage:
#   ./install.bash                    # Interactive menu
#   ./install.bash --all              # Full setup (zsh + essentials + modules + gitconfig + ssh)
#   ./install.bash --modules          # Copy zsh modules, base.bash, .config, .termux & configure ~/.zshrc
#   ./install.bash --essentials       # Install essential packages
#   ./install.bash --ssh              # Run interactive SSH & Git signing setup
#   ./install.bash --gitconfig        # Configure global Git config & allowed_signers
#   ./install.bash --git-aliases      # Install unified git aliases & submodule shortcuts
#   ./install.bash --extensions       # Interactive extension picker
#   ./install.bash --node             # Install Node.js
#   ./install.bash --php              # Install PHP
#   ./install.bash --antigravity      # Install Antigravity CLI
#   ./install.bash --zsh              # Install zsh & set as default shell
#   ./install.bash --everything       # Install everything including extensions and SSH setup
#   ./install.bash --help             # Show usage help
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Globals & Paths
# ---------------------------------------------------------------------------
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ZSH_DIR="$HOME/.zsh"
ZSHRC="$HOME/.zshrc"

ENV_NAME=""          # termux | mac | linux
ENV_DIR=""           # $REPO_DIR/Termux | $REPO_DIR/Mac | $REPO_DIR/Linux
PKG_MANAGER=""       # pkg | brew | apt

MANAGED_BEGIN="# >>> Shell-Setup managed >>>"
MANAGED_END="# <<< Shell-Setup managed <<<"

# ---------------------------------------------------------------------------
# Formatting Helpers
# ---------------------------------------------------------------------------
bold()   { printf '\033[1m%s\033[0m' "$*"; }
green()  { printf '\033[32m%s\033[0m' "$*"; }
yellow() { printf '\033[33m%s\033[0m' "$*"; }
red()    { printf '\033[31m%s\033[0m' "$*"; }
info()   { echo "  $(green "»") $*"; }
warn()   { echo "  $(yellow "⚠") $*"; }
err()    { echo "  $(red "✗") $*" >&2; }
header() { echo; echo "$(bold "=== $* ===")"; echo; }

# ---------------------------------------------------------------------------
# Environment Detection
# ---------------------------------------------------------------------------
detect_env() {
    # Check for proot-distro Linux container FIRST — proot bind-mounts
    # /data/data/com.termux into the guest, so the Termux directory check
    # below would incorrectly match inside a proot container otherwise.
    if [[ -n "${PD_CONTAINER:-}" ]] || [[ "${container:-}" == "proot-distro" ]]; then
        ENV_NAME="linux"
        ENV_DIR="$REPO_DIR/Linux"
        PKG_MANAGER="apt"
    elif [[ -d /data/data/com.termux ]] || [[ -n "${TERMUX_VERSION:-}" ]]; then
        ENV_NAME="termux"
        ENV_DIR="$REPO_DIR/Termux"
        PKG_MANAGER="pkg"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        ENV_NAME="mac"
        ENV_DIR="$REPO_DIR/Mac"
        PKG_MANAGER="brew"
    elif [[ "$(uname -s)" == "Linux" ]]; then
        ENV_NAME="linux"
        ENV_DIR="$REPO_DIR/Linux"
        PKG_MANAGER="apt"
    else
        err "Unsupported operating system: $(uname -s)"
        exit 1
    fi

    info "Detected environment: $(bold "$ENV_NAME") (Package manager: $(bold "$PKG_MANAGER"))"
}

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------
cmd_exists() { command -v "$1" &>/dev/null; }

# Returns "sudo" when not running as root, empty string when already root.
# Allows the same commands to work both in proot-distro (root, no sudo) and
# on a normal Linux desktop (non-root, needs sudo).
maybe_sudo() { [[ "$(id -u)" -eq 0 ]] || echo "sudo"; }

pkg_install() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        pkg)
            pkg install -y "$pkg"
            ;;
        brew)
            if ! cmd_exists brew; then
                warn "Homebrew not found. Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            brew install "$pkg"
            ;;
        apt)
            DEBIAN_FRONTEND=noninteractive $(maybe_sudo) apt-get update -y \
                && DEBIAN_FRONTEND=noninteractive $(maybe_sudo) apt-get install -y \
                    -o Dpkg::Options::="--force-confold" "$pkg"
            ;;
    esac
}

confirm() {
    local prompt="${1:-Continue?} [Y/n] "
    local answer
    read -r -p "$prompt" answer
    [[ -z "$answer" || "$answer" =~ ^[Yy] ]]
}

# Safe recursive copy: merges contents of src_dir into dst_dir without deleting
# any existing files in dst_dir that are not part of this project.
safe_copy_recursive() {
    local src_dir="$1"
    local dst_dir="$2"

    [[ -d "$src_dir" ]] || return 0
    mkdir -p "$dst_dir"

    (
        cd "$src_dir" || exit 1

        # Recreate directory hierarchy in destination
        find . -mindepth 1 -type d -print0 | while IFS= read -r -d '' dir; do
            local rel="${dir#./}"
            mkdir -p "$dst_dir/$rel"
        done

        # Copy files and symlinks safely
        find . -mindepth 1 \( -type f -o -type l \) -print0 | while IFS= read -r -d '' file; do
            local rel="${file#./}"
            local target="$dst_dir/$rel"

            # Preserve existing user git account list (do not overwrite with repo template)
            if [[ "$rel" == "git/accountList" && -f "$target" ]]; then
                continue
            fi

            mkdir -p "$(dirname "$target")"
            cp -P -f "$file" "$target"
        done
    )
}

# ---------------------------------------------------------------------------
# 1. Zsh Shell Installation & Default Configuration
# ---------------------------------------------------------------------------
install_zsh() {
    header "Zsh Shell Setup"

    if cmd_exists zsh; then
        info "Zsh is already installed: $(zsh --version)"
    else
        info "Installing zsh..."
        pkg_install zsh
    fi

    info "Setting zsh as default shell..."
    case "$ENV_NAME" in
        termux)
            chsh -s zsh
            ;;
        mac)
            local zsh_path
            zsh_path="$(which zsh)"
            if ! grep -qF "$zsh_path" /etc/shells 2>/dev/null; then
                warn "Adding $zsh_path to /etc/shells (requires sudo)"
                echo "$zsh_path" | $(maybe_sudo) tee -a /etc/shells >/dev/null
            fi
            chsh -s "$zsh_path"
            ;;
        linux)
            local zsh_path
            zsh_path="$(which zsh)"
            if ! grep -qF "$zsh_path" /etc/shells 2>/dev/null; then
                echo "$zsh_path" | $(maybe_sudo) tee -a /etc/shells >/dev/null
            fi
            local current_user
            current_user="$(whoami)"
            if cmd_exists chsh; then
                $(maybe_sudo) chsh -s "$zsh_path" "$current_user"
            else
                # In minimal proot containers chsh may be absent — patch /etc/passwd directly
                warn "chsh not found. Patching /etc/passwd directly..."
                $(maybe_sudo) sed -i "s|^\(${current_user}:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\).*|\1${zsh_path}|" /etc/passwd
            fi
            ;;
    esac
    info "Default shell configured to zsh."
}

# ---------------------------------------------------------------------------
# 2. Essential Packages
# ---------------------------------------------------------------------------
install_essentials() {
    header "Essential Packages"

    local -a essentials

    case "$ENV_NAME" in
        termux)
            essentials=(git mandoc neovim which tree openssh)
            ;;
        mac)
            essentials=(git mandoc neovim which tree)
            ;;
        linux)
            # Ubuntu/Debian package names differ from Termux:
            #   openssh → openssh-client   (ssh client tools)
            #   mandoc  → man-db           (man page viewer)
            essentials=(git man-db neovim which tree openssh-client)
            ;;
    esac

    for pkg in "${essentials[@]}"; do
        local is_installed=false
        if [[ "$PKG_MANAGER" == "apt" ]]; then
            dpkg -s "$pkg" &>/dev/null 2>&1 && is_installed=true
        else
            cmd_exists "$pkg" 2>/dev/null && is_installed=true
        fi

        if $is_installed; then
            info "$pkg — $(green "already installed")"
        else
            info "Installing $pkg..."
            pkg_install "$pkg"
        fi
    done
}

# ---------------------------------------------------------------------------
# 3. Zsh Modules & Configuration Files
# ---------------------------------------------------------------------------
install_modules() {
    header "Zsh Modules & Configurations"

    mkdir -p "$ZSH_DIR"

    # Copy modular *.zsh configs from root zsh folder
    if [[ -d "$REPO_DIR/zsh" ]]; then
        info "Copying zsh modules from $(bold "$REPO_DIR/zsh/") → ~/.zsh/"
        cp "$REPO_DIR/zsh/"*.zsh "$ZSH_DIR/"
        # Clean up legacy standalone git-submodule.zsh if it exists from previous versions
        rm -f "$ZSH_DIR/git-submodule.zsh"
        if [[ -f "$REPO_DIR/zsh/customizeGit.bash" ]]; then
            info "Installing Git account customizer → ~/.zsh/customizeGit.bash"
            cp "$REPO_DIR/zsh/customizeGit.bash" "$ZSH_DIR/customizeGit.bash"
            chmod 755 "$ZSH_DIR/customizeGit.bash"
        fi
    fi

    # Copy environment-specific base configs (base.bash -> base.zsh)
    if [[ -f "$ENV_DIR/base.bash" ]]; then
        info "Copying base config from $(bold "$ENV_DIR/base.bash") → ~/.zsh/base.zsh"
        cp "$ENV_DIR/base.bash" "$ZSH_DIR/base.zsh"
        # Clean up legacy no-git.zsh
        rm -f "$ZSH_DIR/no-git.zsh"
    elif [[ -f "$ENV_DIR/no-git" ]]; then
        info "Copying legacy non-git config from $(bold "$ENV_DIR/no-git") → ~/.zsh/base.zsh"
        cp "$ENV_DIR/no-git" "$ZSH_DIR/base.zsh"
        rm -f "$ZSH_DIR/no-git.zsh"
    fi

    # Install zsh-syntax-highlighting plugin
    local plugin_dir="$ZSH_DIR/plugins/zsh-syntax-highlighting"
    if [[ ! -d "$plugin_dir" ]]; then
        info "Installing zsh-syntax-highlighting plugin..."
        mkdir -p "$ZSH_DIR/plugins"
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$plugin_dir"
    else
        info "zsh-syntax-highlighting plugin already installed, skipping."
    fi

    # Copy shared configurations from root .config (e.g. nvim, git accountList)
    if [[ -d "$REPO_DIR/.config" ]]; then
        info "Copying shared configurations from $(bold "$REPO_DIR/.config/") → ~/.config/"
        safe_copy_recursive "$REPO_DIR/.config" "$HOME/.config"
    fi

    # Fallback: copy legacy root nvim directory if present and not in .config/nvim
    if [[ -d "$REPO_DIR/nvim" && ! -d "$REPO_DIR/.config/nvim" ]]; then
        info "Copying legacy Neovim configuration from $(bold "$REPO_DIR/nvim/") → ~/.config/nvim/"
        safe_copy_recursive "$REPO_DIR/nvim" "$HOME/.config/nvim"
    fi

    # Copy environment-specific .config directory if present
    if [[ -d "$ENV_DIR/.config" ]]; then
        info "Copying environment-specific .config/ from $(bold "$ENV_DIR/.config/") → ~/.config/"
        safe_copy_recursive "$ENV_DIR/.config" "$HOME/.config"
    fi

    # Copy .termux directory if present (Termux only)
    if [[ -d "$ENV_DIR/.termux" ]]; then
        info "Copying Termux configuration from $(bold "$ENV_DIR/.termux/") → ~/.termux/"
        safe_copy_recursive "$ENV_DIR/.termux" "$HOME/.termux"
        if cmd_exists termux-reload-settings; then
            info "Reloading Termux settings (termux-reload-settings)..."
            termux-reload-settings 2>/dev/null || true
        fi
    fi

    # Ensure SSH setup script is installed to ~/.ssh/setup.bash
    if [[ -f "$REPO_DIR/.ssh/setup.bash" ]]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        info "Installing SSH setup helper → ~/.ssh/setup.bash"
        cp "$REPO_DIR/.ssh/setup.bash" "$HOME/.ssh/setup.bash"
        chmod 755 "$HOME/.ssh/setup.bash"
    fi

    # Setup global Git configuration (.gitconfig & allowed_signers)
    setup_gitconfig

    # Configure ~/.zshrc
    patch_zshrc
}

# ---------------------------------------------------------------------------
# Global Git Configuration & Allowed Signers
# ---------------------------------------------------------------------------
setup_gitconfig() {
    header "Global Git Configuration"

    local global_gitconfig="$HOME/.gitconfig"
    local repo_gitconfig="$REPO_DIR/.gitconfig"
    local git_config_dir="$HOME/.config/git"
    local allowed_signers="$git_config_dir/allowed_signers"

    # Ensure ~/.config/git/allowed_signers exists
    mkdir -p "$git_config_dir"
    if [[ ! -f "$allowed_signers" ]]; then
        touch "$allowed_signers"
        info "Created $allowed_signers"
    fi

    # Ensure ~/.config/git/accountList exists
    local account_list="$git_config_dir/accountList"
    if [[ ! -f "$account_list" && -f "$REPO_DIR/.config/git/accountList" ]]; then
        info "Installing initial account list → $account_list"
        cp "$REPO_DIR/.config/git/accountList" "$account_list"
    fi

    if [[ ! -f "$global_gitconfig" && -f "$repo_gitconfig" ]]; then
        info "Copying default .gitconfig from $(bold "$repo_gitconfig") → ~/.gitconfig"
        cp "$repo_gitconfig" "$global_gitconfig"
    else
        info "Configuring global git settings in ~/.gitconfig..."
        git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers 2>/dev/null || true
        git config --global core.editor nvim 2>/dev/null || true
    fi
    info "Global Git configuration setup completed."
}

# ---------------------------------------------------------------------------
# Patch or Create ~/.zshrc
# ---------------------------------------------------------------------------
patch_zshrc() {
    info "Checking ~/.zshrc configuration..."

    local source_block
    source_block=$(cat <<BLOCK
$MANAGED_BEGIN
# Source all modular configs from ~/.zsh/
for f in ~/.zsh/*.zsh(N); do
    source "\$f"
done

# Syntax highlighting plugin (must be last)
[[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \\
    source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
$MANAGED_END
BLOCK
)

    # Case 1: ~/.zshrc doesn't exist yet
    if [[ ! -f "$ZSHRC" ]]; then
        if [[ -f "$ENV_DIR/.zshrc" ]]; then
            info "Copying preconfigured .zshrc from $(bold "$ENV_DIR/.zshrc") → ~/.zshrc"
            cp "$ENV_DIR/.zshrc" "$ZSHRC"
        else
            info "Creating new ~/.zshrc with module sourcing block"
            echo "$source_block" > "$ZSHRC"
        fi
        return
    fi

    # Case 2: ~/.zshrc already contains the managed block
    if grep -qF "$MANAGED_BEGIN" "$ZSHRC"; then
        info "Updating existing Shell-Setup managed block in ~/.zshrc"
        local tmp
        tmp=$(mktemp)
        awk -v begin="$MANAGED_BEGIN" -v end="$MANAGED_END" '
            $0 == begin { skip=1; next }
            $0 == end   { skip=0; next }
            !skip
        ' "$ZSHRC" > "$tmp"
        echo "" >> "$tmp"
        echo "$source_block" >> "$tmp"
        mv "$tmp" "$ZSHRC"
        return
    fi

    # Case 3: ~/.zshrc already sources ~/.zsh/*.zsh (custom or pre-existing loop)
    if grep -qE '(~/\.zsh/\*\.zsh|\$HOME/\.zsh/\*\.zsh|\$ZSH_DIR/\*\.zsh)' "$ZSHRC"; then
        info "~/.zshrc is already configured to source ~/.zsh/*.zsh modules. No changes needed."
        return
    fi

    # Case 4: ~/.zshrc exists but does not source ~/.zsh modules yet
    info "Appending module sourcing block to ~/.zshrc"
    echo "" >> "$ZSHRC"
    echo "$source_block" >> "$ZSHRC"
}

# ---------------------------------------------------------------------------
# 4. Extensions
# ---------------------------------------------------------------------------
install_node() {
    header "Installing Node.js"
    case "$ENV_NAME" in
        termux) pkg_install nodejs ;;
        mac)    pkg_install node ;;
        linux)  pkg_install nodejs ;;
    esac
    info "Node.js installation completed: $(node --version 2>/dev/null || echo 'installed')"
}

install_php() {
    header "Installing PHP"
    pkg_install php
    info "PHP installation completed: $(php --version 2>/dev/null | head -n1 || echo 'installed')"
}

install_antigravity() {
    header "Installing Antigravity CLI"

    case "$ENV_NAME" in
        termux)
            info "Setting up Antigravity CLI for Termux (via wallentx/antigravity-cli-termux)..."
            info "Verifying glibc-repo and glibc dependencies..."

            if ! pkg list-installed 2>/dev/null | grep -q glibc-repo; then
                info "Installing glibc-repo..."
                pkg_install glibc-repo
            fi

            if ! pkg list-installed 2>/dev/null | grep -q "^glibc "; then
                info "Installing glibc..."
                pkg_install glibc
            fi

            info "Running wallentx Antigravity installer..."
            curl -fsSL https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh | bash
            ;;
        mac)
            info "Checking Antigravity CLI for macOS..."
            if cmd_exists agy; then
                info "agy is already installed: $(agy --version 2>/dev/null || echo 'installed')"
            else
                info "Follow the official Antigravity CLI installation for macOS:"
                info "Visit: https://github.com/google-deepmind/antigravity"
            fi
            ;;
        linux)
            info "Checking Antigravity CLI for Linux..."
            if cmd_exists agy; then
                info "agy is already installed."
            else
                info "Please install Antigravity CLI via standard package / binary release."
            fi
            ;;
    esac
}

install_extensions_menu() {
    header "Extensions Selection"

    local -a ext_ids ext_names ext_descs

    case "$ENV_NAME" in
        termux)
            ext_ids=(node php antigravity)
            ext_names=("Node.js" "PHP" "Antigravity CLI")
            ext_descs=(
                "Node.js JavaScript runtime (via pkg)"
                "PHP scripting engine (via pkg)"
                "Antigravity CLI (wallentx/antigravity-cli-termux with glibc)"
            )
            ;;
        mac)
            ext_ids=(node php antigravity)
            ext_names=("Node.js" "PHP" "Antigravity CLI")
            ext_descs=(
                "Node.js JavaScript runtime (via brew)"
                "PHP scripting engine (via brew)"
                "Antigravity CLI for macOS"
            )
            ;;
        linux)
            ext_ids=(node php antigravity)
            ext_names=("Node.js" "PHP" "Antigravity CLI")
            ext_descs=(
                "Node.js JavaScript runtime"
                "PHP scripting engine"
                "Antigravity CLI"
            )
            ;;
    esac

    echo "  Select extensions to install (space-separated numbers, 'a' for all, 'n' to skip):"
    echo
    for i in "${!ext_ids[@]}"; do
        printf "    %d) %-18s — %s\n" "$((i+1))" "${ext_names[$i]}" "${ext_descs[$i]}"
    done
    echo

    local selection
    read -r -p "  Choose: " selection

    [[ "$selection" == "n" || -z "$selection" ]] && { info "Skipping extensions."; return; }

    local -a selected_indices=()
    if [[ "$selection" == "a" ]]; then
        selected_indices=("${!ext_ids[@]}")
    else
        for s in $selection; do
            selected_indices+=("$((s-1))")
        done
    fi

    for idx in "${selected_indices[@]}"; do
        local ext="${ext_ids[$idx]}"
        case "$ext" in
            node)        install_node ;;
            php)         install_php ;;
            antigravity) install_antigravity ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 5. Unified Git Aliases & Submodule Shortcuts
# ---------------------------------------------------------------------------
setup_git_aliases() {
    header "Unified Git Aliases & Submodule Shortcuts"

    local dest="$ZSH_DIR/git-aliases.zsh"
    local src="$REPO_DIR/zsh/git-aliases.zsh"

    mkdir -p "$ZSH_DIR"

    if [[ -f "$dest" ]]; then
        info "Git aliases already exist at ~/.zsh/git-aliases.zsh"
        if ! confirm "  Overwrite with latest unified version?"; then
            return
        fi
    fi

    info "Installing git-aliases.zsh → ~/.zsh/"
    cp "$src" "$dest"
    # Clean up legacy separate git-submodule.zsh if it exists
    rm -f "$ZSH_DIR/git-submodule.zsh"
    info "Unified Git aliases and submodule shortcuts installed."
}

# Backward compatibility alias for setup_git_submodule_aliases
setup_git_submodule_aliases() {
    info "Note: Git submodule aliases are now integrated into git-aliases.zsh."
    setup_git_aliases "$@"
}

# ---------------------------------------------------------------------------
# 5b. Git Account Customizer
# ---------------------------------------------------------------------------
setup_git_accounts() {
    header "Git Multi-Account Setup"

    local custom_script="$REPO_DIR/zsh/customizeGit.bash"
    if [[ ! -f "$custom_script" ]]; then
        custom_script="$HOME/.zsh/customizeGit.bash"
    fi

    if [[ -f "$custom_script" ]]; then
        bash "$custom_script"
    else
        warn "customizeGit.bash not found."
    fi
}

# ---------------------------------------------------------------------------
# 6. SSH Key & Git Signing Setup
# ---------------------------------------------------------------------------
setup_ssh() {
    header "SSH Key & Git Signing Setup"

    local ssh_dir="$HOME/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    # Copy setup helper script to ~/.ssh/setup.bash
    if [[ -f "$REPO_DIR/.ssh/setup.bash" ]]; then
        info "Installing SSH setup helper → ~/.ssh/setup.bash"
        cp "$REPO_DIR/.ssh/setup.bash" "$ssh_dir/setup.bash"
        chmod 755 "$ssh_dir/setup.bash"
    fi

    # Copy initial ~/.ssh/config if not already present
    if [[ -f "$REPO_DIR/.ssh/config" && ! -f "$ssh_dir/config" ]]; then
        info "Installing initial SSH config → ~/.ssh/config"
        cp "$REPO_DIR/.ssh/config" "$ssh_dir/config"
        chmod 600 "$ssh_dir/config"
    fi

    if confirm "  Would you like to manage/configure Git accounts first (customizeGit)?"; then
        setup_git_accounts
    fi

    if confirm "  Would you like to run the interactive SSH key setup now?"; then
        bash "$ssh_dir/setup.bash"
    else
        info "Skipped SSH key generation."
        info "You can run it anytime with: $(bold "ssh-setup") (or $(bold "bash ~/.ssh/setup.bash"))"
    fi
}

# ---------------------------------------------------------------------------
# Interactive Menu
# ---------------------------------------------------------------------------
interactive_menu() {
    header "Shell-Setup Installer ($ENV_NAME)"

    echo "  What would you like to do?"
    echo
    echo "    1) Full install      — zsh + essentials + modules + gitconfig + ssh setup"
    echo "    2) Install zsh       — install zsh & set as default shell"
    echo "    3) Essentials        — install essentials (git, neovim, which, etc.)"
    echo "    4) Modules only      — copy modular configs, base config & configure ~/.zshrc"
    echo "    5) Git & SSH Setup   — configure ~/.gitconfig and setup SSH keys / signing"
    echo "    6) Git Accounts      — manage multi-account Git functions & wrappers (customizeGit.bash)"
    echo "    7) Extensions        — install optional extras (Node.js, PHP, Antigravity)"
    echo "    8) Git aliases       — install or update unified git aliases & submodule shortcuts"
    echo "    9) Everything        — full install + all extensions + SSH setup"
    echo "    q) Quit"
    echo

    local choice
    read -r -p "  Choose [1-9/q]: " choice

    case "$choice" in
        1)
            install_zsh
            install_essentials
            install_modules
            setup_ssh
            ;;
        2)
            install_zsh
            ;;
        3)
            install_essentials
            ;;
        4)
            install_modules
            ;;
        5)
            setup_gitconfig
            setup_ssh
            ;;
        6)
            setup_git_accounts
            ;;
        7)
            install_extensions_menu
            ;;
        8)
            setup_git_aliases
            ;;
        9)
            install_zsh
            install_essentials
            install_modules
            install_extensions_menu
            setup_ssh
            ;;
        q|Q)
            echo "  Exiting."
            exit 0
            ;;
        *)
            err "Invalid choice: $choice"
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Usage Help
# ---------------------------------------------------------------------------
show_help() {
    cat <<EOF
$(bold "Shell-Setup Universal Installer")

Usage: ./install.bash [OPTIONS]

Workflow options:
  --all           Full install (zsh + essentials + modules + gitconfig + ssh)
  --modules       Copy zsh modules, base.bash, .config, .termux & patch ~/.zshrc
  --essentials    Install essential packages (git, neovim, mandoc, which, tree)
  --zsh           Install zsh & set as default shell
  --ssh           Run interactive SSH & Git commit signing setup
  --gitconfig     Configure global Git config (~/.gitconfig & allowed_signers)
  --git-accounts  Manage multi-account Git configurations (customizeGit.bash)
  --git-aliases   Install or update unified git aliases & submodule shortcuts
  --submodules    Alias for --git-aliases (integrated)
  --extensions    Interactive picker for extensions (Node, PHP, Antigravity)
  --everything    Install all components including extensions and SSH setup
  --help, -h      Show this help message

Direct extension flags:
  --node          Install Node.js runtime
  --php           Install PHP engine
  --antigravity   Install Antigravity CLI

When run without arguments, launches the interactive selection menu.

Supported Environments:
  • Termux (Android)
  • macOS (Homebrew)
  • Linux (apt)
EOF
}

# ---------------------------------------------------------------------------
# Main Entrypoint
# ---------------------------------------------------------------------------
main() {
    detect_env

    if [[ $# -eq 0 ]]; then
        interactive_menu
    else
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --all)
                    install_zsh
                    install_essentials
                    install_modules
                    setup_ssh
                    shift
                    ;;
                --modules)
                    install_modules
                    shift
                    ;;
                --essentials)
                    install_essentials
                    shift
                    ;;
                --zsh)
                    install_zsh
                    shift
                    ;;
                --ssh)
                    setup_ssh
                    shift
                    ;;
                --gitconfig)
                    setup_gitconfig
                    shift
                    ;;
                --git-accounts)
                    setup_git_accounts
                    shift
                    ;;
                --git-aliases|--submodules)
                    setup_git_aliases
                    shift
                    ;;
                --extensions)
                    install_extensions_menu
                    shift
                    ;;
                --node)
                    install_node
                    shift
                    ;;
                --php)
                    install_php
                    shift
                    ;;
                --antigravity)
                    install_antigravity
                    shift
                    ;;
                --everything)
                    install_zsh
                    install_essentials
                    install_modules
                    install_extensions_menu
                    setup_ssh
                    shift
                    ;;
                --help|-h)
                    show_help
                    exit 0
                    ;;
                *)
                    err "Unknown option: $1"
                    show_help
                    exit 1
                    ;;
            esac
        done
    fi

    echo
    info "$(green "Done!")"
    info "Restart your terminal or run: $(bold "source ~/.zshrc")"
}

main "$@"
