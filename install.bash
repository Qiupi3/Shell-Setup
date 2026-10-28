#!/bin/sh
# Universal trampoline: ensure execution under bash on Termux, macOS, and Linux.
#
# IMPORTANT: proot-distro inherits Termux's environment ($PREFIX, $PATH, etc.)
# into the Linux container. We must detect this case and strip those vars,
# otherwise the script picks up Termux's Android binaries (wrong dynamic
# linker, wrong libraries) and fails inside the Linux container.
#
# Cleanup runs before the bash check on purpose: a fresh `proot-distro login`
# already starts a bash shell, so testing BASH_VERSION alone would skip the
# cleanup in exactly the case that needs it.
SHELL_SETUP_IN_PROOT=0
if [ -n "${PD_CONTAINER:-}" ] || [ "${container:-}" = "proot-distro" ]; then
    SHELL_SETUP_IN_PROOT=1
    # Proot bind-mounts the Termux prefix and leaks Android/Termux variables
    # (PREFIX, BOOTCLASSPATH, PATH, ...) into the guest. Remove them and use
    # the container's native Linux search path instead. TMPDIR and the TLS
    # variables can also point at Termux paths that do not exist in guest
    # tooling, so clear those as well.
    unset PREFIX TERMUX_VERSION TERMUX__HOME TERMUX__PREFIX
    unset TERMUX_APP__PACKAGE_NAME TERMUX_APP__PID TERMUX_APP__UID
    unset ANDROID_ROOT ANDROID_DATA ANDROID_ART_ROOT ANDROID_I18N_ROOT
    unset ANDROID_TZDATA_ROOT EXTERNAL_STORAGE
    unset BOOTCLASSPATH DEX2OATBOOTCLASSPATH LD_PRELOAD LD_LIBRARY_PATH
    unset TMPDIR SSL_CERT_FILE SSL_CERT_DIR CURL_CA_BUNDLE GIT_SSL_CAINFO
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
fi

# Re-run this script under the right bash. When the script arrives on stdin
# (`curl ... | sh`), $0 is a bare shell name and cannot be passed to bash as a
# filename; `-s` makes bash read the same stdin instead.
shell_setup_reexec_bash() {
    _bash_bin="$1"
    shift

    _script=""
    case "$0" in
        */*)  _script="$0" ;;
        bash|sh|dash|ash|zsh) _script="" ;;
        *)    _script="$(command -v "$0" 2>/dev/null || true)" ;;
    esac

    if [ -n "$_script" ] && [ -f "$_script" ]; then
        exec "$_bash_bin" "$_script" "$@"
    fi
    exec "$_bash_bin" -s -- "$@"
}

# A proot-distro session can inherit Termux's Android bash. It sometimes starts,
# but its dynamic linker and libraries are the wrong ones for guest tooling, so
# switch to the container's native bash before doing any work.
if [ "$SHELL_SETUP_IN_PROOT" -eq 1 ] \
    && [ -n "${BASH_VERSION:-}" ] \
    && [ -x /bin/bash ] \
    && [ "${BASH:-}" != "/bin/bash" ] \
    && [ "${BASH:-}" != "/usr/bin/bash" ]; then
    shell_setup_reexec_bash /bin/bash "$@"
fi

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
    # Do not let the re-exec inherit POSIX mode, otherwise bash would come
    # back with POSIXLY_CORRECT set and this block would loop forever.
    unset POSIXLY_CORRECT

    if [ -n "${PREFIX:-}" ] && [ -x "$PREFIX/bin/bash" ]; then
        shell_setup_reexec_bash "$PREFIX/bin/bash" "$@"
    elif [ -x /bin/bash ]; then
        shell_setup_reexec_bash /bin/bash "$@"
    elif command -v bash >/dev/null 2>&1; then
        shell_setup_reexec_bash "$(command -v bash)" "$@"
    else
        echo "Error: bash is required to run this script." >&2
        exit 1
    fi
fi

# Shell-Setup Universal Installer
#
# Auto-detects the environment (Termux, macOS, Debian/Ubuntu Linux, including
# proot-distro containers) and installs one or more selectable modules:
#
#   Option 1  Shell environment  — Zsh as default shell, modular aliases,
#                                  git aliases, zsh-syntax-highlighting, ~/.zshrc
#   Option 2  Neovim editor      — ~/.config/nvim, EDITOR/VISUAL, core.editor
#   Option 3  Git accounts & SSH — key audit, key creation, commit signing,
#                                  account-specific clone wrappers
#   Option 4  Extensions         — pick languages and CLI tooling individually
#
# User data is always written under $HOME. The repository is never modified.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Qiupi3/Shell-Setup/main/install.bash | bash
#   ./install.bash                    # Interactive menu
#   ./install.bash --shell            # Option 1 (offers Option 2 at the end)
#   ./install.bash --nvim             # Option 2
#   ./install.bash --git              # Option 3
#   ./install.bash --ext              # Option 4 (interactive picker)
#   ./install.bash --ext python,node  # Option 4 (non-interactive)
#   ./install.bash --all              # Options 1 + 2 + 3
#   ./install.bash --everything       # Options 1 + 2 + 3 + 4
#
# Legacy flags (still supported):
#   --modules        Copy shell configs only (no package install, no chsh)
#   --essentials     Install the union of module dependencies + QoL tools
#   --zsh            Install zsh and set it as the default shell
#   --ssh            Alias for --git
#   --gitconfig      Only write ~/.gitconfig and allowed_signers
#   --git-accounts   Only run customizeGit.bash
#   --git-aliases    Only install/update unified git aliases
#   --extensions     Alias for --ext
#   --node --php --antigravity
#   --help, -h       Show usage help
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
LINUX_ID=""          # debian | ubuntu | ... (from /etc/os-release)
LINUX_VERSION=""     # 13 | 24.04 | ...
APT_UPDATED=0        # run apt-get update at most once per installer run
IS_PROOT_DISTRO=0    # 1 when running inside a proot-distro container

MANAGED_BEGIN="# >>> Shell-Setup managed >>>"
MANAGED_END="# <<< Shell-Setup managed <<<"
EDITOR_BEGIN="# >>> Shell-Setup editor >>>"
EDITOR_END="# <<< Shell-Setup editor <<<"

# When 1, Option 1 offers to run Option 2 right after finishing. Disabled for
# --all/--everything so Neovim runs exactly once.
SHELL_OFFER_NVIM=1

# ---------------------------------------------------------------------------
# Self-bootstrap (curl | bash)
# ---------------------------------------------------------------------------
# Running `curl .../install.bash | bash` leaves us without the rest of the
# repository. Download the current main tarball to a temporary directory,
# re-run the real installer from it, then remove the temporary copy.
# The `zsh/` directory is the marker: it is required by every module.
if [[ ! -d "$REPO_DIR/zsh" || ! -f "$REPO_DIR/install.bash" ]]; then
    set -o pipefail
    BOOTSTRAP_RC=0
    BOOTSTRAP_DIR=""

    # A proot-distro guest often has no curl of its own, while Termux's curl
    # is reachable through the bind mount. Use it as a fallback instead of
    # failing with "curl is required" after the trampoline sanitised PATH.
    BOOTSTRAP_CURL=""
    if command -v curl >/dev/null 2>&1; then
        BOOTSTRAP_CURL="$(command -v curl)"
    elif [[ -x /data/data/com.termux/files/usr/bin/curl ]]; then
        BOOTSTRAP_CURL="/data/data/com.termux/files/usr/bin/curl"
    fi

    BOOTSTRAP_TAR=""
    if command -v tar >/dev/null 2>&1; then
        BOOTSTRAP_TAR="$(command -v tar)"
    elif [[ -x /data/data/com.termux/files/usr/bin/tar ]]; then
        BOOTSTRAP_TAR="/data/data/com.termux/files/usr/bin/tar"
    fi

    if [[ -z "$BOOTSTRAP_CURL" ]]; then
        echo "  ✗ curl is required to bootstrap Shell-Setup." >&2
        echo "  Install it first (e.g. apt-get install -y curl) or clone the repository." >&2
        exit 1
    fi
    if [[ -z "$BOOTSTRAP_TAR" ]]; then
        echo "  ✗ tar is required to bootstrap Shell-Setup." >&2
        exit 1
    fi

    BOOTSTRAP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t shell-setup)"
    trap 'rm -rf "$BOOTSTRAP_DIR"' EXIT

    echo "  » Downloading Shell-Setup..."
    BOOTSTRAP_ARCHIVE="$BOOTSTRAP_DIR/shell-setup.tar.gz"
    if ! "$BOOTSTRAP_CURL" -fsSL --retry 2 \
        -o "$BOOTSTRAP_ARCHIVE" \
        https://github.com/Qiupi3/Shell-Setup/archive/refs/heads/main.tar.gz; then
        echo "  ✗ Failed to download Shell-Setup." >&2
        exit 1
    fi
    if ! "$BOOTSTRAP_TAR" -xzf "$BOOTSTRAP_ARCHIVE" -C "$BOOTSTRAP_DIR"; then
        echo "  ✗ Failed to extract Shell-Setup." >&2
        exit 1
    fi
    rm -f "$BOOTSTRAP_ARCHIVE"

    BOOTSTRAP_REPO="$BOOTSTRAP_DIR/Shell-Setup-main"
    if [[ ! -f "$BOOTSTRAP_REPO/install.bash" ]]; then
        echo "  ✗ Downloaded archive is missing install.bash." >&2
        exit 1
    fi

    # A piped script has no usable stdin. Prefer the controlling terminal so
    # the interactive menu and the extension picker still work. Without a
    # terminal, use /dev/null so a prompt cannot consume the remaining bytes
    # of this very script from the pipe.
    if [[ -t 0 ]]; then
        bash "$BOOTSTRAP_REPO/install.bash" "$@" || BOOTSTRAP_RC=$?
    elif (exec </dev/tty) 2>/dev/null; then
        bash "$BOOTSTRAP_REPO/install.bash" "$@" </dev/tty || BOOTSTRAP_RC=$?
    else
        bash "$BOOTSTRAP_REPO/install.bash" "$@" </dev/null || BOOTSTRAP_RC=$?
    fi

    # The parent `curl` may still be writing the rest of this script into our
    # stdin. Read it to EOF before exiting; otherwise curl reports
    # "(23) Failure writing output to destination" on an otherwise successful
    # installation.
    if [[ ! -t 0 ]]; then
        cat >/dev/null 2>&1 || true
    fi

    exit "$BOOTSTRAP_RC"
fi

# ---------------------------------------------------------------------------
# Formatting Helpers
# ---------------------------------------------------------------------------
bold()   { printf '\033[1m%s\033[0m' "$*"; }
green()  { printf '\033[32m%s\033[0m' "$*"; }
yellow() { printf '\033[33m%s\033[0m' "$*"; }
red()    { printf '\033[31m%s\033[0m' "$*"; }
cyan()   { printf '\033[36m%s\033[0m' "$*"; }
dim()    { printf '\033[2m%s\033[0m' "$*"; }
info()   { echo "  $(green "»") $*"; }
warn()   { echo "  $(yellow "⚠") $*"; }
err()    { echo "  $(red "✗") $*" >&2; }
header() { echo; echo "$(bold "=== $* ===")"; echo; }

# ---------------------------------------------------------------------------
# Environment Detection
# ---------------------------------------------------------------------------
# Read a field from /etc/os-release without sourcing it.
linux_field() {
    local key="$1" file="${2:-/etc/os-release}"
    [[ -r "$file" ]] || return 0
    sed -n "s/^${key}=//p" "$file" | head -n1 | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

detect_linux_distro() {
    LINUX_ID="$(linux_field ID)"
    LINUX_VERSION="$(linux_field VERSION_ID)"

    if [[ -z "$LINUX_ID" && -r /etc/debian_version ]]; then
        LINUX_ID="debian"
        LINUX_VERSION="$(cat /etc/debian_version 2>/dev/null || true)"
    fi

    LINUX_ID="${LINUX_ID:-linux}"
}

detect_env() {
    # Check for proot-distro Linux container FIRST — proot bind-mounts
    # /data/data/com.termux into the guest, so the Termux directory check
    # below would incorrectly match inside a proot container otherwise.
    if [[ -n "${PD_CONTAINER:-}" ]] || [[ "${container:-}" == "proot-distro" ]]; then
        IS_PROOT_DISTRO=1
        ENV_NAME="linux"
        ENV_DIR="$REPO_DIR/Linux"
        detect_linux_distro
        if cmd_exists apt-get && cmd_exists dpkg; then
            PKG_MANAGER="apt"
        else
            err "Unsupported proot-distro image: ${LINUX_ID} ${LINUX_VERSION} (apt/dpkg not found)"
            err "Supported images: ubuntu, debian"
            exit 1
        fi
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
        detect_linux_distro
        # Prefer system apt-get over Termux-wrapped ones
        if [[ -x /usr/bin/apt-get && -x /usr/bin/dpkg ]]; then
            PKG_MANAGER="apt"
            export PATH="/usr/bin:/usr/sbin:/bin:/sbin:$PATH"
        elif cmd_exists apt-get && cmd_exists dpkg; then
            local _apt="$(command -v apt-get)"
            if [[ "$_apt" == *termux/* ]]; then
                if [[ -x /usr/bin/apt-get ]]; then
                    PKG_MANAGER="apt"
                    export PATH="/usr/bin:/usr/sbin:/bin:/sbin:$PATH"
                else
                    err "Unsupported Linux distribution: ${LINUX_ID} ${LINUX_VERSION}"
                    exit 1
                fi
            else
                PKG_MANAGER="apt"
            fi
        else
            err "Unsupported Linux distribution: ${LINUX_ID} ${LINUX_VERSION}"
            err "This installer supports Debian/Ubuntu-based systems (apt/dpkg)."
            exit 1
        fi
    else
        err "Unsupported operating system: $(uname -s)"
        exit 1
    fi

    if [[ "$ENV_NAME" == "linux" ]]; then
        info "Detected environment: $(bold "$ENV_NAME") — $(bold "$LINUX_ID ${LINUX_VERSION:-}") (Package manager: $(bold "$PKG_MANAGER"))"
    else
        info "Detected environment: $(bold "$ENV_NAME") (Package manager: $(bold "$PKG_MANAGER"))"
    fi
}

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------
cmd_exists() { command -v "$1" &>/dev/null; }
http_get() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$url"
    else
        return 1
    fi
}
http_get_pipe() {
    local url="$1"
    shift
    if command -v curl >/dev/null 2>&1 || [ -x /data/data/com.termux/files/usr/bin/curl ]; then
        local c="/data/data/com.termux/files/usr/bin/curl"
        command -v curl >/dev/null 2>&1 && c="$(command -v curl)"
        if (($# == 0)); then
            "$c" -fsSL "$url"
        elif (($# == 1)); then
            "$c" -fsSL "$url" | "$1"
        else
            "$c" -fsSL "$url" | "$@"
        fi
        return $?
    elif command -v wget >/dev/null 2>&1 || [ -x /data/data/com.termux/files/usr/bin/wget ]; then
        local w="/data/data/com.termux/files/usr/bin/wget"
        command -v wget >/dev/null 2>&1 && w="$(command -v wget)"
        if (($# == 0)); then
            "$w" -qO- "$url"
        elif (($# == 1)); then
            "$w" -qO- "$url" | "$1"
        else
            "$w" -qO- "$url" | "$@"
        fi
        return $?
    else
        return 1
    fi
}

# Run a command as root: directly when already root (proot-distro, containers),
# through sudo on a normal Linux desktop.
as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif cmd_exists sudo; then
        sudo "$@"
    else
        "$@"
    fi
}

# Command shipped by a package whose name differs from the executable.
pkg_command() {
    case "$1" in
        man-db)          echo "man" ;;
        openssh-client)  echo "ssh" ;;
        gnu-which|which) echo "which" ;;
        neovim)          echo "nvim" ;;
        nodejs|node)     echo "node" ;;
        npm)             echo "npm" ;;
        ca-certificates) echo "update-ca-certificates" ;;
        python3-pip)     echo "pip3" ;;
        golang)          echo "go" ;;
        default-jdk|openjdk-17|openjdk) echo "java" ;;
        build-essential) echo "cc" ;;
        ripgrep)         echo "rg" ;;
        fd-find)         echo "fdfind" ;;
        imagemagick)     echo "convert" ;;
        *)               echo "$1" ;;
    esac
}

pkg_install() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        pkg)
            if [[ -x /data/data/com.termux/files/usr/bin/pkg ]]; then
                env PATH=/data/data/com.termux/files/usr/bin:$PATH /data/data/com.termux/files/usr/bin/pkg install -y "$pkg"
            elif command -v pkg >/dev/null 2>&1; then
                pkg install -y "$pkg"
            else
                err "pkg not found"
                return 1
            fi
            ;;
        brew)
            if ! cmd_exists brew; then
                warn "Homebrew not found. Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            brew install "$pkg"
            ;;
        apt)
            local aptg="/usr/bin/apt-get"
            [[ -x "$aptg" ]] || aptg="$(command -v apt-get 2>/dev/null || echo apt-get)"
            if [[ "$aptg" == *termux/* ]]; then
                aptg="/usr/bin/apt-get"
            fi
            if [[ "$APT_UPDATED" -eq 0 ]]; then
                as_root env DEBIAN_FRONTEND=noninteractive "$aptg" update -y
                APT_UPDATED=1
            fi
            as_root env DEBIAN_FRONTEND=noninteractive "$aptg" install -y \
                -o Dpkg::Options::="--force-confold" "$pkg"
            ;;
    esac
}

confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-y}"
    local hint=" [Y/n] "
    [[ "$default" == "n" ]] && hint=" [y/N] "

    local answer
    # EOF (non-interactive run, e.g. installer invoked from a script) must not
    # be treated as "yes", otherwise console-driven setup steps would run blind.
    if ! read -r -p "${prompt}${hint}" answer; then
        echo
        return 1
    fi

    if [[ -z "$answer" ]]; then
        [[ "$default" == "y" ]]
        return
    fi
    [[ "$answer" =~ ^[Yy] ]]
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
set_passwd_shell() {
    local user="$1"
    local shell_path="$2"

    if ! grep -q "^${user}:" /etc/passwd 2>/dev/null; then
        warn "User '${user}' not found in /etc/passwd; cannot set default shell."
        return 1
    fi

    as_root sed -i "s|^\(${user}:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\).*|\1${shell_path}|" /etc/passwd
}

install_zsh() {
    header "Zsh Shell Setup"

    if cmd_exists zsh; then
        info "Zsh is already installed: $(zsh --version)"
    else
        info "Installing zsh..."
        pkg_install zsh
    fi

    local zsh_path
    zsh_path="$(command -v zsh || true)"
    if [[ -z "$zsh_path" ]]; then
        for candidate in /usr/bin/zsh /bin/zsh /usr/local/bin/zsh; do
            if [[ -x "$candidate" ]]; then
                zsh_path="$candidate"
                break
            fi
        done
    fi
    if [[ -z "$zsh_path" ]]; then
        err "zsh was installed but its executable could not be found."
        exit 1
    fi

    info "Setting zsh as default shell ($zsh_path)..."
    case "$ENV_NAME" in
        termux)
            chsh -s zsh
            ;;
        mac)
            if ! grep -qF "$zsh_path" /etc/shells 2>/dev/null; then
                warn "Adding $zsh_path to /etc/shells (requires sudo)"
                echo "$zsh_path" | as_root tee -a /etc/shells >/dev/null
            fi
            as_root chsh -s "$zsh_path" "$(whoami)"
            ;;
        linux)
            if ! grep -qF "$zsh_path" /etc/shells 2>/dev/null; then
                echo "$zsh_path" | as_root tee -a /etc/shells >/dev/null
            fi
            local current_user
            current_user="$(id -un)"
            if cmd_exists chsh; then
                if ! as_root chsh -s "$zsh_path" "$current_user"; then
                    # Minimal proot-distro images (notably Debian) can ship chsh
                    # but still fail under proot/PAM. Patch /etc/passwd directly.
                    warn "chsh failed. Patching /etc/passwd directly..."
                    set_passwd_shell "$current_user" "$zsh_path"
                fi
            else
                # In minimal proot containers chsh may be absent — patch /etc/passwd directly
                warn "chsh not found. Patching /etc/passwd directly..."
                set_passwd_shell "$current_user" "$zsh_path"
            fi
            ;;
    esac
    info "Default shell configured to zsh."
}

# ---------------------------------------------------------------------------
# 2. Package helpers & module dependencies
# ---------------------------------------------------------------------------
# A package counts as installed when dpkg knows it (apt) or when its executable
# exists. The executable fallback covers virtual packages such as "which".
pkg_installed() {
    local pkg="$1"
    if [[ "$PKG_MANAGER" == "apt" ]] && dpkg -s "$pkg" &>/dev/null 2>&1; then
        return 0
    fi
    local cmd
    cmd="$(pkg_command "$pkg")"
    [[ -n "$cmd" ]] && cmd_exists "$cmd"
}

pkg_ensure() {
    local pkg="$1"
    if pkg_installed "$pkg"; then
        info "$pkg — $(green "already installed")"
    else
        info "Installing $pkg..."
        pkg_install "$pkg"
    fi
}

# Packages each module needs in order to work on its own.
shell_dep_pkgs() {
    case "$ENV_NAME" in
        linux)  echo "git ca-certificates" ;;
        termux) echo "git" ;;
        mac)    echo "git" ;;
    esac
}

nvim_dep_pkgs() {
    case "$ENV_NAME" in
        linux|termux|mac) echo "neovim" ;;
    esac
}

ssh_dep_pkgs() {
    case "$ENV_NAME" in
        linux)  echo "openssh-client" ;;
        termux) echo "openssh" ;;
        mac)    echo "" ;;
    esac
}

ensure_pkgs() {
    local pkg
    for pkg in "$@"; do
        pkg_ensure "$pkg"
    done
}

# ---------------------------------------------------------------------------
# 2b. Optional quality-of-life CLI tools
# ---------------------------------------------------------------------------
qol_specs() {
    case "$ENV_NAME" in
        linux)
            QOL_SPECS=(
                "tree|tree|trd / tra / trview aliases"
                "gnu-which|which|'which' lookups in scripts"
                "man-db|man|man pages and 'git help'"
                "less|less|pagers (git log, man)"
                "curl|curl|downloading installers"
                "wget|wget|downloading files"
                "unzip|unzip|.zip extraction"
                "file|file|file type detection"
                "procps|ps|process tools (ps, top)"
            )
            ;;
        termux)
            QOL_SPECS=(
                "tree|tree|trd / tra / trview aliases"
                "which|which|'which' lookups in scripts"
                "mandoc|man|man pages and 'git help'"
                "less|less|pagers (git log, man)"
                "curl|curl|downloading installers"
                "wget|wget|downloading files"
                "unzip|unzip|.zip extraction"
                "file|file|file type detection"
                "procps|ps|process tools (ps, top)"
            )
            ;;
        mac)
            QOL_SPECS=(
                "tree|tree|trd / tra / trview aliases"
                "which|which|'which' lookups in scripts"
                "mandoc|man|man pages and 'git help'"
                "less|less|pagers (git log, man)"
                "curl|curl|downloading installers"
                "wget|wget|downloading files"
                "unzip|unzip|.zip extraction"
                "file|file|file type detection"
            )
            ;;
    esac
}

# Optional, defaults to "no": show exactly which features break when skipped.
install_qol_tools() {
    header "Recommended CLI Tools (optional)"

    qol_specs
    local -a missing=()
    local spec pkg label purpose
    for spec in "${QOL_SPECS[@]}"; do
        IFS='|' read -r pkg label purpose <<< "$spec"
        pkg_installed "$pkg" || missing+=("$spec")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        info "All recommended CLI tools are already installed."
        return 0
    fi

    echo "  Not required, but skipping them disables these features:"
    echo
    for spec in "${missing[@]}"; do
        IFS='|' read -r pkg label purpose <<< "$spec"
        printf "    %-12s → %s\n" "$label" "$purpose"
    done
    echo

    if ! confirm "  Install them now?" n; then
        local -a names=()
        for spec in "${missing[@]}"; do
            IFS='|' read -r pkg label purpose <<< "$spec"
            names+=("$label")
        done
        warn "Skipped: ${names[*]}"
        warn "The features listed above will not work until those tools are installed."
        return 0
    fi

    for spec in "${missing[@]}"; do
        IFS='|' read -r pkg label purpose <<< "$spec"
        pkg_ensure "$pkg"
    done
}

# Legacy entry point for --essentials: the union of all module dependencies.
install_essentials() {
    header "Essential Packages"

    ensure_pkgs $(shell_dep_pkgs) zsh $(nvim_dep_pkgs) $(ssh_dep_pkgs)

    qol_specs
    local spec pkg label purpose
    for spec in "${QOL_SPECS[@]}"; do
        IFS='|' read -r pkg label purpose <<< "$spec"
        pkg_ensure "$pkg"
    done
}

# ---------------------------------------------------------------------------
# 3. Shell environment (Option 1)
# ---------------------------------------------------------------------------
install_shell_configs() {
    header "Shell Configuration Files"

    mkdir -p "$ZSH_DIR"

    # git is needed to clone the syntax-highlighting plugin.
    cmd_exists git || pkg_ensure git

    if [[ -d "$REPO_DIR/zsh" ]]; then
        info "Copying zsh modules from $(bold "$REPO_DIR/zsh/") → ~/.zsh/"
        local f base
        for f in "$REPO_DIR/zsh"/*.zsh; do
            [[ -e "$f" ]] || continue
            base="$(basename "$f")"
            cp "$f" "$ZSH_DIR/$base"
        done

        if [[ -f "$REPO_DIR/zsh/customizeGit.bash" ]]; then
            info "Installing Git account customizer → ~/.zsh/customizeGit.bash"
            cp "$REPO_DIR/zsh/customizeGit.bash" "$ZSH_DIR/customizeGit.bash"
            chmod 755 "$ZSH_DIR/customizeGit.bash"
        fi

        # Legacy cleanups only. Never touch ~/.zsh/git-custom.zsh: it holds
        # account wrappers generated locally by the Git module.
        rm -f "$ZSH_DIR/git-submodule.zsh"
        rm -f "$ZSH_DIR/no-git.zsh"
    fi

    if [[ -f "$ENV_DIR/base.bash" ]]; then
        info "Copying base config from $(bold "$ENV_DIR/base.bash") → ~/.zsh/base.zsh"
        cp "$ENV_DIR/base.bash" "$ZSH_DIR/base.zsh"
    elif [[ -f "$ENV_DIR/no-git" ]]; then
        info "Copying legacy non-git config from $(bold "$ENV_DIR/no-git") → ~/.zsh/base.zsh"
        cp "$ENV_DIR/no-git" "$ZSH_DIR/base.zsh"
    fi

    local plugin_dir="$ZSH_DIR/plugins/zsh-syntax-highlighting"
    if [[ ! -d "$plugin_dir" ]]; then
        info "Installing zsh-syntax-highlighting plugin..."
        mkdir -p "$ZSH_DIR/plugins"
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$plugin_dir"
    else
        info "zsh-syntax-highlighting plugin already installed, skipping."
    fi

    if [[ -d "$ENV_DIR/.termux" ]]; then
        info "Copying Termux configuration from $(bold "$ENV_DIR/.termux/") → ~/.termux/"
        safe_copy_recursive "$ENV_DIR/.termux" "$HOME/.termux"
        if cmd_exists termux-reload-settings; then
            info "Reloading Termux settings (termux-reload-settings)..."
            termux-reload-settings 2>/dev/null || true
        fi
    fi

    patch_zshrc
}

install_shell() {
    header "Shell Environment (Zsh)"

    ensure_pkgs $(shell_dep_pkgs)
    install_zsh
    install_qol_tools
    install_shell_configs

    if [[ "${SHELL_OFFER_NVIM:-1}" -eq 1 ]]; then
        echo
        if confirm "  Also set up Neovim as the default editor (same as Option 2)?" y; then
            install_nvim
        fi
    fi
}

# ---------------------------------------------------------------------------
# 3b. Neovim (Option 2)
# ---------------------------------------------------------------------------
install_nvim_config() {
    header "Neovim Configuration"

    local src="$REPO_DIR/.config/nvim"
    if [[ -d "$src" ]]; then
        info "Copying Neovim config from $(bold "$src/") → ~/.config/nvim/"
        safe_copy_recursive "$src" "$HOME/.config/nvim"
    elif [[ -d "$REPO_DIR/nvim" ]]; then
        info "Copying legacy Neovim config from $(bold "$REPO_DIR/nvim/") → ~/.config/nvim/"
        safe_copy_recursive "$REPO_DIR/nvim" "$HOME/.config/nvim"
    else
        warn "No Neovim configuration found in the repository."
    fi

    if cmd_exists git; then
        git config --global core.editor nvim 2>/dev/null || true
    fi

    if [[ -f "$ZSHRC" ]]; then
        patch_zshrc_editor
    else
        warn "~/.zshrc not found; skipped the EDITOR/VISUAL block."
        warn "Run Option 1 (Shell environment) to finish the zsh setup."
    fi
}

install_nvim() {
    header "Neovim Editor"

    ensure_pkgs $(nvim_dep_pkgs)
    install_nvim_config

    if cmd_exists nvim; then
        if confirm "  Pre-install Neovim plugins now (lazy.nvim sync)?" y; then
            info "Running lazy.nvim sync (this may take a while)..."
            if nvim --headless "+Lazy! sync" +qa 2>/dev/null; then
                info "Neovim plugins installed."
            else
                warn "Plugin sync failed (offline?). Plugins install on first launch."
            fi
        fi
    fi
}

# ---------------------------------------------------------------------------
# 3c. Git accounts & SSH (Option 3)
# ---------------------------------------------------------------------------
install_git_helpers() {
    mkdir -p "$ZSH_DIR"

    if [[ -f "$REPO_DIR/zsh/git-functions.zsh" ]]; then
        info "Installing generic git helpers → ~/.zsh/git-functions.zsh"
        cp "$REPO_DIR/zsh/git-functions.zsh" "$ZSH_DIR/git-functions.zsh"
    fi

    if [[ -f "$REPO_DIR/zsh/customizeGit.bash" ]]; then
        info "Installing Git account customizer → ~/.zsh/customizeGit.bash"
        cp "$REPO_DIR/zsh/customizeGit.bash" "$ZSH_DIR/customizeGit.bash"
        chmod 755 "$ZSH_DIR/customizeGit.bash"
    fi

    # The generated account wrappers only exist inside a zsh session. Make
    # sure ~/.zshrc loads ~/.zsh/*.zsh even when the Git module is run on its
    # own, instead of silently installing functions that never get sourced.
    patch_zshrc
}

# Old installs may contain HTML-style comments copied from the template.
# OpenSSH rejects "<!--" with "Bad configuration option", so strip them.
repair_ssh_config() {
    local cfg="$HOME/.ssh/config"
    [[ -f "$cfg" ]] || return 0

    if grep -qE '^[[:space:]]*(<!--|-->)' "$cfg"; then
        warn "~/.ssh/config contains HTML-style comments (<!-- -->), which OpenSSH rejects."
        local backup="$cfg.bak.$(date +%Y%m%d%H%M%S)"
        cp "$cfg" "$backup"
        sed -i -E '/^[[:space:]]*<!--/d; /^[[:space:]]*-->[[:space:]]*$/d' "$cfg"
        info "Removed invalid comment markers (backup: $(bold "$backup"))"
    fi
}

install_ssh_files() {
    local ssh_dir="$HOME/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    if [[ -f "$REPO_DIR/.ssh/config" && ! -f "$ssh_dir/config" ]]; then
        info "Installing initial SSH config → ~/.ssh/config"
        cp "$REPO_DIR/.ssh/config" "$ssh_dir/config"
        chmod 600 "$ssh_dir/config"
    fi

    repair_ssh_config

    if [[ -f "$REPO_DIR/.ssh/setup.bash" ]]; then
        info "Installing SSH setup helper → ~/.ssh/setup.bash"
        cp "$REPO_DIR/.ssh/setup.bash" "$ssh_dir/setup.bash"
        chmod 755 "$ssh_dir/setup.bash"
    fi

    # Make sure OpenSSH can actually parse the resulting config.
    if cmd_exists ssh && ! ssh -G github.com >/dev/null 2>&1; then
        warn "OpenSSH still cannot parse ~/.ssh/config; please inspect it manually."
    fi
}

install_git_ssh() {
    header "Git Accounts & SSH"

    ensure_pkgs $(ssh_dep_pkgs)
    setup_gitconfig
    install_git_helpers
    install_ssh_files

    # Accounts must exist before keys are created: setup.bash names keys,
    # SSH hosts, and signing entries after the account list. Doing SSH first
    # (the old order) created keys that were not attached to any account and
    # made the account manager ask for the same information again.
    local count
    count="$(account_entry_count)"

    echo
    info "$(bold "Step 1 of 2") — Git accounts and clone wrappers"
    if (( count > 0 )); then
        info "Found $(bold "$count") configured account(s)."
    fi

    local account_default="y"
    (( count > 0 )) && account_default="n"
    if confirm "  Open the Git account manager now?" "$account_default"; then
        SHELL_SETUP_NO_SSH_PROMPT=1 setup_git_accounts
    else
        info "Skipped the account manager."
    fi

    count="$(account_entry_count)"
    if (( count > 0 )); then
        sync_git_wrappers
    fi

    echo
    info "$(bold "Step 2 of 2") — SSH keys and commit signing"
    if (( count == 0 )); then
        warn "No Git accounts are configured yet, so keys would have nothing to attach to."
        info "Add accounts with $(bold "git-accounts"), then run $(bold "ssh-setup")."
        return 0
    fi

    if confirm "  Set up SSH keys for your ${count} account(s) now?" y; then
        run_ssh_setup
    else
        info "Skipped. Run it anytime with: $(bold "bash ~/.ssh/setup.bash")"
    fi
}

# Number of real (non-comment, non-blank) entries in the account list.
account_entry_count() {
    local file="$HOME/.config/git/accountList"
    [[ -f "$file" ]] || { echo 0; return 0; }
    awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        { count++ }
        END { print count + 0 }
    ' "$file"
}

# Regenerate ~/.zsh/git-custom.zsh from the account list without opening the
# interactive manager. Keeps clone wrappers available when Option 3 is run on
# an existing account list (for example after a fresh install or an update).
sync_git_wrappers() {
    local customizer="$HOME/.zsh/customizeGit.bash"
    [[ -f "$customizer" ]] || return 0
    SHELL_SETUP_NO_SSH_PROMPT=1 bash "$customizer" --sync >/dev/null 2>&1 || return 0
}

# Run the SSH helper once, with a consistent success/failure message.
run_ssh_setup() {
    if [[ ! -f "$HOME/.ssh/setup.bash" ]]; then
        install_ssh_files
    fi
    if [[ ! -f "$HOME/.ssh/setup.bash" ]]; then
        err "~/.ssh/setup.bash not found."
        return 1
    fi

    if bash "$HOME/.ssh/setup.bash"; then
        info "SSH setup finished."
    else
        warn "SSH setup ended without completing."
        warn "Re-run it anytime with: $(bold "bash ~/.ssh/setup.bash")"
        return 1
    fi
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
    fi

    if cmd_exists delta; then
        info "Configuring git-delta as the pager..."
        git config --global core.pager delta 2>/dev/null || true
        git config --global interactive.diffFilter "delta --color-only" 2>/dev/null || true
        git config --global delta.navigate true 2>/dev/null || true
        git config --global delta.line-numbers true 2>/dev/null || true
        git config --global delta.side-by-side false 2>/dev/null || true
        git config --global merge.conflictstyle diff3 2>/dev/null || true
        git config --global diff.colorMoved default 2>/dev/null || true
    fi

    info "Global Git configuration setup completed."
}

# ---------------------------------------------------------------------------
# Patch or Create ~/.zshrc
# ---------------------------------------------------------------------------
# Return the managed block for the current environment. When the environment
# ships its own .zshrc with managed markers (e.g. Linux/.zshrc), use that so the
# config lives in the repo instead of in this script. Termux/macOS .zshrc files
# have no markers, so they keep the generic fallback block for compatibility.
managed_zshrc_block() {
    local env_zshrc="$ENV_DIR/.zshrc"

    if [[ -f "$env_zshrc" ]] \
        && grep -qF "$MANAGED_BEGIN" "$env_zshrc" \
        && grep -qF "$MANAGED_END" "$env_zshrc"; then
        awk -v begin="$MANAGED_BEGIN" -v end="$MANAGED_END" '
            $0 == begin { in_block = 1 }
            in_block    { print }
            $0 == end   { in_block = 0 }
        ' "$env_zshrc"
        return
    fi

    cat <<BLOCK
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
}

# ~/.zshrc is zsh syntax. A guard at the top turns the confusing bash errors
# ("setopt: command not found", "parse error near '('") into a clear hint when
# someone runs `source ~/.zshrc` from bash. Applied to newly created files and
# to existing files during an update.
ensure_zshrc_guard() {
    [[ -f "$ZSHRC" ]] || return 0
    grep -qF '~/.zshrc is a zsh configuration' "$ZSHRC" && return 0

    local tmp
    tmp="$(mktemp)"
    {
        cat <<'GUARD'
# This file is zsh-only. Sourcing it from bash produces confusing
# "setopt: command not found" and "parse error near '('" messages, so stop
# early with a useful hint instead.
if [ -n "${BASH_VERSION:-}" ]; then
    echo "~/.zshrc is a zsh configuration. Start zsh with: exec zsh" >&2
    return 1 2>/dev/null || exit 1
fi

GUARD
        cat "$ZSHRC"
    } > "$tmp"
    mv "$tmp" "$ZSHRC"
}

patch_zshrc() {
    info "Checking ~/.zshrc configuration..."

    local source_block
    source_block="$(managed_zshrc_block)"

    # Case 1: ~/.zshrc doesn't exist yet
    if [[ ! -f "$ZSHRC" ]]; then
        if [[ -f "$ENV_DIR/.zshrc" ]]; then
            info "Copying preconfigured .zshrc from $(bold "$ENV_DIR/.zshrc") → ~/.zshrc"
            cp "$ENV_DIR/.zshrc" "$ZSHRC"
        else
            info "Creating new ~/.zshrc with module sourcing block"
            echo "$source_block" > "$ZSHRC"
        fi
        ensure_zshrc_guard
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
        # Drop blank lines left behind by the removed block so repeated runs
        # do not keep adding whitespace, then separate with exactly one blank.
        awk 'NF { last = NR } { line[NR] = $0 } END { for (i = 1; i <= last; i++) print line[i] }' \
            "$tmp" > "$tmp.clean"
        [[ -s "$tmp.clean" ]] && echo "" >> "$tmp.clean"
        echo "$source_block" >> "$tmp.clean"
        mv "$tmp.clean" "$ZSHRC"
        rm -f "$tmp"
        ensure_zshrc_guard
        return
    fi

    # Case 3: ~/.zshrc already sources ~/.zsh/*.zsh (custom or pre-existing loop)
    if grep -qE '(~/\.zsh/\*\.zsh|\$HOME/\.zsh/\*\.zsh|\$ZSH_DIR/\*\.zsh)' "$ZSHRC"; then
        info "~/.zshrc is already configured to source ~/.zsh/*.zsh modules. No changes needed."
        ensure_zshrc_guard
        return
    fi

    # Case 4: ~/.zshrc exists but does not source ~/.zsh modules yet
    info "Appending module sourcing block to ~/.zshrc"
    local tmp
    tmp=$(mktemp)
    awk 'NF { last = NR } { line[NR] = $0 } END { for (i = 1; i <= last; i++) print line[i] }' \
        "$ZSHRC" > "$tmp"
    [[ -s "$tmp" ]] && echo "" >> "$tmp"
    echo "$source_block" >> "$tmp"
    mv "$tmp" "$ZSHRC"
    ensure_zshrc_guard
}

# ---------------------------------------------------------------------------
# Neovim editor block in ~/.zshrc (owned by Option 2)
# ---------------------------------------------------------------------------
# Kept in a separate managed block so re-running Option 1 (which rewrites its
# own block) never removes the editor settings.
patch_zshrc_editor() {
    info "Configuring EDITOR/VISUAL in ~/.zshrc..."

    local block
    block="$(printf '%s\n%s\n%s\n%s' \
        "$EDITOR_BEGIN" \
        'export EDITOR=nvim' \
        'export VISUAL=nvim' \
        "$EDITOR_END")"

    local tmp
    tmp="$(mktemp)"

    if grep -qF "$EDITOR_BEGIN" "$ZSHRC"; then
        awk -v begin="$EDITOR_BEGIN" -v end="$EDITOR_END" '
            $0 == begin { skip = 1; next }
            $0 == end   { skip = 0; next }
            !skip
        ' "$ZSHRC" > "$tmp"
    else
        cp "$ZSHRC" "$tmp"
    fi

    # Drop trailing blank lines, then append exactly one blank line + block.
    awk 'NF { last = NR } { line[NR] = $0 } END { for (i = 1; i <= last; i++) print line[i] }' \
        "$tmp" > "$tmp.clean"
    [[ -s "$tmp.clean" ]] && echo "" >> "$tmp.clean"
    echo "$block" >> "$tmp.clean"

    mv "$tmp.clean" "$ZSHRC"
    rm -f "$tmp"
    ensure_zshrc_guard

    info "EDITOR/VISUAL block written to ~/.zshrc"
}

# ---------------------------------------------------------------------------
# 4. Extensions (Option 4)
# ---------------------------------------------------------------------------
# Direct installers kept for the legacy --node / --php / --antigravity flags.
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

install_antigravity_ext() {
    header "Installing Antigravity CLI"

    if cmd_exists agy; then
        info "Antigravity CLI — $(green "already installed") ($(agy --version 2>/dev/null || echo "installed"))"
        return 0
    fi

    case "$ENV_NAME" in
        termux)
            info "Installing via wallentx/antigravity-cli-termux (Termux native)..."
            info "Verifying glibc-repo and glibc dependencies..."

            if ! pkg list-installed 2>/dev/null | grep -q glibc-repo; then
                info "Installing glibc-repo..."
                pkg_install glibc-repo
            fi

            if ! pkg list-installed 2>/dev/null | grep -q "^glibc "; then
                info "Installing glibc..."
                pkg_install glibc
            fi

            if ! http_get_pipe https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh bash; then
                err "Antigravity CLI installation failed."
                return 1
            fi
            ;;
        mac|linux)
            # The wallentx installer is Termux-only. Linux (including
            # proot-distro) and macOS use Google's official installer.
            info "Installing via the official Antigravity CLI installer..."
            if ! http_get_pipe https://antigravity.google/cli/install.sh bash; then
                err "Antigravity CLI installation failed."
                return 1
            fi
            # The official installer writes to ~/.local/bin but does not add it
            # to PATH. Make it usable for the rest of this run as well.
            export PATH="$HOME/.local/bin:$PATH"
            ;;
    esac

    if cmd_exists agy; then
        info "Antigravity CLI installed: $(agy --version 2>/dev/null || echo "agy")"
    else
        warn "agy is not on PATH yet."
        warn "Add ~/.local/bin to PATH (Linux/macOS) or open a new shell."
    fi
}

install_opencode_ext() {
    header "Installing OpenCode"

    if [[ "$IS_PROOT_DISTRO" -ne 1 ]]; then
        err "OpenCode is only supported inside a proot-distro container."
        err "On Android, log in first: $(bold "proot-distro login <distro>")"
        return 1
    fi

    export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
    mkdir -p "$HOME/.opencode/bin" 2>/dev/null || true

    if cmd_exists opencode; then
        info "OpenCode — $(green "already installed") ($(opencode --version 2>/dev/null || echo "installed"))"
        configure_extension_post opencode
        return 0
    fi

    info "Installing OpenCode v2 from the official installer..."
    if ! http_get_pipe https://opencode.ai/v2/install bash; then
        err "OpenCode installation failed."
        return 1
    fi

    export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
    if cmd_exists opencode; then
        info "OpenCode installed: $(opencode --version 2>/dev/null || echo "opencode")"
    else
        warn "OpenCode was installed to ~/.opencode/bin but is not on PATH yet."
        warn "Run $(bold "exec zsh") (or restart your shell) to pick up the updated PATH."
    fi
    configure_extension_post opencode
}

# Direct installer kept for the legacy --antigravity flag.
install_antigravity() {
    install_paths_module
    install_antigravity_ext || warn "Antigravity CLI installation did not complete."
}

# Each entry maps a friendly id to the package(s) that provide it. Package
# names differ per environment, which is why the catalog is per-OS.
ext_catalog() {
    EXT_IDS=()
    EXT_NAMES=()
    EXT_DESCS=()
    EXT_PKGS=()
    EXT_GROUPS=()
    EXT_SELECTED=()
    EXT_INSTALLED=()
    EXT_CUR=0
    EXT_SCROLL=0

    case "$ENV_NAME" in
        linux)
            EXT_IDS=(python uv ruby node bun pnpm deno php go rust java build bat eza httpie zoxide git-delta rg fd fzf jq tmux direnv gitlfs sqlite gh ffmpeg imagemagick)
            EXT_NAMES=("Python" "uv (Python pkg mgr)" "Ruby" "Node.js" "Bun (JS runtime)" "pnpm (JS pkg mgr)" "Deno (JS/TS runtime)" "PHP" "Go" "Rust" "Java (JDK)" "Build tools" "bat (cat with syntax)" "eza (ls replacement)" "HTTPie (HTTP client)" "zoxide (smarter cd)" "git-delta (better diffs)" "ripgrep" "fd" "fzf" "jq" "tmux" "direnv" "Git LFS" "SQLite" "GitHub CLI" "FFmpeg" "ImageMagick")
            EXT_DESCS=("Python 3 + pip + venv" "Fast Python package/dependency manager" "Ruby runtime" "Node.js + npm" "Fast JS runtime/bundler/package manager" "Fast disk-efficient package manager" "Secure JS/TS runtime" "PHP runtime" "Go toolchain" "rustc + cargo" "Default JDK" "gcc, make, headers" "Syntax-highlighted cat" "Modern ls with icons/git" "User-friendly curl/wget alternative" "Learns and jumps to frequent dirs" "Syntax-highlighted git diffs" "Fast recursive grep" "Fast file finder" "Fuzzy finder" "JSON processor" "Terminal multiplexer" "Per-directory environment" "Large file support" "SQLite database" "GitHub CLI" "Audio/video conversion" "Image conversion")
            EXT_PKGS=("python3 python3-pip python3-venv" "" "ruby" "nodejs npm" "" "" "" "php" "golang" "rustc cargo" "default-jdk" "build-essential" "bat" "eza" "httpie" "zoxide" "git-delta" "ripgrep" "fd-find" "fzf" "jq" "tmux" "direnv" "git-lfs" "sqlite3" "gh" "ffmpeg" "imagemagick")
            EXT_GROUPS=("Runtimes" "Runtimes" "Runtimes" "JS Tooling" "JS Tooling" "JS Tooling" "JS Tooling" "Runtimes" "Runtimes" "Runtimes" "Runtimes" "Compilers & build" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "Multimedia" "Multimedia")
            ;;
        termux)
            EXT_IDS=(python uv ruby node bun pnpm deno php go rust java build bat eza httpie zoxide git-delta rg fd fzf jq tmux direnv gitlfs sqlite gh ffmpeg imagemagick)
            EXT_NAMES=("Python" "uv (Python pkg mgr)" "Ruby" "Node.js" "Bun (JS runtime)" "pnpm (JS pkg mgr)" "Deno (JS/TS runtime)" "PHP" "Go" "Rust" "Java (JDK)" "Build tools" "bat (cat with syntax)" "eza (ls replacement)" "HTTPie (HTTP client)" "zoxide (smarter cd)" "git-delta (better diffs)" "ripgrep" "fd" "fzf" "jq" "tmux" "direnv" "Git LFS" "SQLite" "GitHub CLI" "FFmpeg" "ImageMagick")
            EXT_DESCS=("Python + pip" "Fast Python package/dependency manager" "Ruby runtime" "Node.js + npm" "Fast JS runtime/bundler/package manager" "Fast disk-efficient package manager" "Secure JS/TS runtime" "PHP runtime" "Go toolchain" "Rust toolchain" "OpenJDK 17" "clang + make" "Syntax-highlighted cat" "Modern ls with icons/git" "User-friendly curl/wget alternative" "Learns and jumps to frequent dirs" "Syntax-highlighted git diffs" "Fast recursive grep" "Fast file finder" "Fuzzy finder" "JSON processor" "Terminal multiplexer" "Per-directory environment" "Large file support" "SQLite database" "GitHub CLI" "Audio/video conversion" "Image conversion")
            EXT_PKGS=("python" "" "ruby" "nodejs" "" "" "" "php" "golang" "rust" "openjdk-17" "clang make" "bat" "eza" "httpie" "zoxide" "git-delta" "ripgrep" "fd" "fzf" "jq" "tmux" "direnv" "git-lfs" "sqlite" "gh" "ffmpeg" "imagemagick")
            EXT_GROUPS=("Runtimes" "Runtimes" "Runtimes" "JS Tooling" "JS Tooling" "JS Tooling" "JS Tooling" "Runtimes" "Runtimes" "Runtimes" "Runtimes" "Compilers & build" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "Multimedia" "Multimedia")
            ;;
        mac)
            EXT_IDS=(python uv ruby node bun pnpm deno php go rust java build bat eza httpie zoxide git-delta rg fd fzf jq tmux direnv gitlfs sqlite gh ffmpeg imagemagick)
            EXT_NAMES=("Python" "uv (Python pkg mgr)" "Ruby" "Node.js" "Bun (JS runtime)" "pnpm (JS pkg mgr)" "Deno (JS/TS runtime)" "PHP" "Go" "Rust" "Java (JDK)" "Build tools" "bat (cat with syntax)" "eza (ls replacement)" "HTTPie (HTTP client)" "zoxide (smarter cd)" "git-delta (better diffs)" "ripgrep" "fd" "fzf" "jq" "tmux" "direnv" "Git LFS" "SQLite" "GitHub CLI" "FFmpeg" "ImageMagick")
            EXT_DESCS=("Python + pip" "Fast Python package/dependency manager" "Ruby runtime" "Node.js + npm" "Fast JS runtime/bundler/package manager" "Fast disk-efficient package manager" "Secure JS/TS runtime" "PHP runtime" "Go toolchain" "Rust toolchain" "OpenJDK" "make" "Syntax-highlighted cat" "Modern ls with icons/git" "User-friendly curl/wget alternative" "Learns and jumps to frequent dirs" "Syntax-highlighted git diffs" "Fast recursive grep" "Fast file finder" "Fuzzy finder" "JSON processor" "Terminal multiplexer" "Per-directory environment" "Large file support" "SQLite database" "GitHub CLI" "Audio/video conversion" "Image conversion")
            EXT_PKGS=("python" "" "ruby" "node" "" "" "" "php" "go" "rust" "openjdk" "make" "bat" "eza" "httpie" "zoxide" "git-delta" "ripgrep" "fd" "fzf" "jq" "tmux" "direnv" "git-lfs" "sqlite" "gh" "ffmpeg" "imagemagick")
            EXT_GROUPS=("Runtimes" "Runtimes" "Runtimes" "JS Tooling" "JS Tooling" "JS Tooling" "JS Tooling" "Runtimes" "Runtimes" "Runtimes" "Runtimes" "Compilers & build" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "CLI & dev tools" "Multimedia" "Multimedia")
    esac

    ext_catalog_ai_tools
}

# Tools installed by their own upstream installer instead of an OS package.
# They still use empty EXT_PKGS entries so all catalog arrays stay aligned.
ext_catalog_ai_tools() {
    EXT_IDS+=(antigravity)
    EXT_NAMES+=("Antigravity CLI")
    EXT_DESCS+=("Google Antigravity coding agent")
    EXT_PKGS+=("")
    EXT_GROUPS+=("AI coding tools")

    # OpenCode is only supported inside the Linux proot-distro container.
    if [[ "$ENV_NAME" == "linux" ]]; then
        EXT_IDS+=(opencode)
        EXT_NAMES+=("OpenCode")
        EXT_DESCS+=("AI coding agent (proot-distro only)")
        EXT_PKGS+=("")
        EXT_GROUPS+=("AI coding tools")
    fi
}

install_uv_ext() {
    header "Installing uv (Astral)"

    if cmd_exists uv; then
        info "uv — $(green "already installed") ($(uv --version 2>/dev/null || echo "installed"))"
        return 0
    fi

    info "Installing via the official uv installer..."
    if ! http_get_pipe https://astral.sh/uv/install.sh sh; then
        err "uv installation failed."
        return 1
    fi

    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    if cmd_exists uv; then
        info "uv installed: $(uv --version 2>/dev/null || echo "uv")"
    else
        warn "uv was installed but not on PATH yet."
        warn "Run $(bold "exec zsh") (or restart your shell) to pick up ~/.local/bin."
    fi
}

install_bun_ext() {
    header "Installing Bun"

    if cmd_exists bun; then
        info "Bun — $(green "already installed") ($(bun --version 2>/dev/null || echo "installed"))"
        return 0
    fi

    info "Installing via the official Bun installer..."
    if ! http_get_pipe https://bun.sh/install bash; then
        err "Bun installation failed."
        return 1
    fi

    export PATH="$HOME/.bun/bin:$PATH"
    if cmd_exists bun; then
        info "Bun installed: $(bun --version 2>/dev/null || echo "bun")"
    else
        warn "Bun was installed to ~/.bun/bin but not on PATH yet."
        warn "Run $(bold "exec zsh") (or restart your shell) to pick up ~/.bun/bin."
    fi
}

install_pnpm_ext() {
    header "Installing pnpm"

    if cmd_exists pnpm; then
        info "pnpm — $(green "already installed") ($(pnpm --version 2>/dev/null || echo "installed"))"
        return 0
    fi

    if cmd_exists corepack; then
        info "Enabling pnpm via corepack..."
        corepack enable 2>/dev/null || true
        corepack prepare pnpm@latest --activate 2>/dev/null || true
    fi

    if cmd_exists pnpm; then
        info "pnpm installed: $(pnpm --version 2>/dev/null || echo "pnpm")"
        return 0
    fi

    info "Installing via official pnpm installer..."
    if ! http_get_pipe https://get.pnpm.io/install.sh sh -; then
        err "pnpm installation failed."
        return 1
    fi

    export PATH="$HOME/.local/share/pnpm:$PATH"
    if cmd_exists pnpm; then
        info "pnpm installed: $(pnpm --version 2>/dev/null || echo "pnpm")"
    else
        warn "pnpm installed but not on PATH yet. Run $(bold "exec zsh") (or restart your shell)."
    fi
}

install_deno_ext() {
    header "Installing Deno"

    if cmd_exists deno; then
        info "Deno — $(green "already installed") ($(deno --version 2>/dev/null | head -n1 || echo "installed"))"
        return 0
    fi

    info "Installing via the official Deno installer..."
    if ! http_get_pipe https://deno.land/install.sh sh; then
        err "Deno installation failed."
        return 1
    fi

    export PATH="$HOME/.deno/bin:$PATH"
    if cmd_exists deno; then
        info "Deno installed: $(deno --version 2>/dev/null | head -n1 || echo "deno")"
    else
        warn "Deno installed to ~/.deno/bin but not on PATH yet. Run $(bold "exec zsh") (or restart your shell)."
    fi
}

# Return the custom installer function for an extension, or nothing.
ext_installer_fn() {
    case "$1" in
        antigravity) echo "install_antigravity_ext" ;;
        opencode)    echo "install_opencode_ext" ;;
        uv)          echo "install_uv_ext" ;;
        bun)         echo "install_bun_ext" ;;
        pnpm)        echo "install_pnpm_ext" ;;
        deno)        echo "install_deno_ext" ;;
        *)           echo "" ;;
    esac
}

# Executable that proves a custom extension is already installed.
ext_command() {
    case "$1" in
        antigravity) echo "agy" ;;
        opencode)    echo "opencode" ;;
        uv)          echo "uv" ;;
        bun)         echo "bun" ;;
        pnpm)        echo "pnpm" ;;
        deno)        echo "deno" ;;
        *)           echo "" ;;
    esac
}

ext_index() {
    local id="$1" i
    for i in "${!EXT_IDS[@]}"; do
        if [[ "${EXT_IDS[$i]}" == "$id" ]]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

ext_installed() {
    local idx="$1" pkg cmd
    # OpenCode is unsupported outside proot-distro, even if a binary happens
    # to exist on PATH; don't advertise it as an available extension there.
    if [[ "${EXT_IDS[$idx]}" == "opencode" && "$IS_PROOT_DISTRO" -ne 1 ]]; then
        return 1
    fi
    cmd="$(ext_command "${EXT_IDS[$idx]}")"
    if [[ -n "$cmd" ]]; then
        cmd_exists "$cmd"
        return
    fi
    [[ -n "${EXT_PKGS[$idx]}" ]] || return 1
    for pkg in ${EXT_PKGS[$idx]}; do
        pkg_installed "$pkg" || return 1
    done
    return 0
}

# Install the persistent PATH module and make sure ~/.zshrc sources ~/.zsh/.
# Extension-only runs (--ext ...) do not call install_shell_configs, so tools
# installed into ~/.local/bin, ~/.bun/bin, etc. would otherwise vanish after
# `exec zsh`.
install_paths_module() {
    mkdir -p "$ZSH_DIR"
    if [[ -f "$REPO_DIR/zsh/paths.zsh" ]]; then
        if [[ ! -f "$ZSH_DIR/paths.zsh" ]] \
            || ! cmp -s "$REPO_DIR/zsh/paths.zsh" "$ZSH_DIR/paths.zsh"; then
            cp "$REPO_DIR/zsh/paths.zsh" "$ZSH_DIR/paths.zsh"
        fi
    fi
    patch_zshrc
}

configure_extension_post() {
    local id="$1"
    # Ensure common bin dirs are on PATH
    export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/.local/share/pnpm:$PATH"
    mkdir -p "$HOME/.local/bin" "$HOME/.opencode/bin" 2>/dev/null || true

    case "$id" in
        git-delta)
            if cmd_exists delta; then
                info "Configuring git-delta as the pager..."
                git config --global core.pager delta 2>/dev/null || true
                git config --global interactive.diffFilter "delta --color-only" 2>/dev/null || true
                git config --global delta.navigate true 2>/dev/null || true
                git config --global delta.line-numbers true 2>/dev/null || true
                git config --global delta.side-by-side false 2>/dev/null || true
                git config --global merge.conflictstyle diff3 2>/dev/null || true
                git config --global diff.colorMoved default 2>/dev/null || true
            fi
            ;;
        zoxide)
            if cmd_exists zoxide; then
                info "zoxide installed. Add 'eval \"\$(zoxide init zsh)\"' to your shell config (already handled in this setup if using provided zshrc)."
            fi
            ;;
        fzf)
            if cmd_exists fzf; then
                info "fzf installed. Keybindings/completions can be set up via shell config."
            fi
            ;;
        eza)
            if cmd_exists eza; then
                info "eza installed. You can use 'eza' as a modern 'ls' replacement."
            fi
            ;;
        bat)
            if cmd_exists bat || cmd_exists batcat; then
                if ! cmd_exists bat && cmd_exists batcat; then
                    ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat" 2>/dev/null || ln -sf "$(command -v batcat)" /usr/local/bin/bat 2>/dev/null || true
                fi
                info "bat installed. Use 'bat' for syntax-highlighted cat output."
            fi
            ;;
        direnv)
            if cmd_exists direnv; then
                info "direnv installed. Add 'eval \"\$(direnv hook zsh)\"' to your shell config."
            fi
            ;;
        gh)
            if cmd_exists gh; then
                info "GitHub CLI installed. Run 'gh auth login' to authenticate."
            fi
            ;;
        opencode)
            if cmd_exists opencode || [ -x "$HOME/.opencode/bin/opencode" ]; then
                export PATH="$HOME/.opencode/bin:$PATH"
                info "OpenCode installed and PATH updated for this session."
            fi
            ;;
        antigravity)
            if cmd_exists agy; then
                export PATH="$HOME/.local/bin:$PATH"
                info "Antigravity CLI installed and PATH updated for this session."
            fi
            ;;
        uv)
            export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
            ;;
        bun)
            export PATH="$HOME/.bun/bin:$PATH"
            ;;
        pnpm)
            export PATH="$HOME/.local/share/pnpm:$PATH"
            ;;
        deno)
            export PATH="$HOME/.deno/bin:$PATH"
            ;;
        *)
            ;;
    esac
}

install_ext_ids() {
    local id idx pkg fn
    install_paths_module
    for id in "$@"; do
        if ! idx="$(ext_index "$id")"; then
            warn "Unknown extension: $id"
            continue
        fi

        fn="$(ext_installer_fn "$id")"
        if [[ -n "$fn" ]]; then
            if ! "$fn"; then
                return 1
            fi
            configure_extension_post "$id"
            continue
        fi

        if ext_installed "$idx"; then
            info "${EXT_NAMES[$idx]} — $(green "already installed")"
            configure_extension_post "$id"
            continue
        fi

        header "Extension: ${EXT_NAMES[$idx]}"
        for pkg in ${EXT_PKGS[$idx]}; do
            pkg_ensure "$pkg"
        done
        configure_extension_post "$id"
    done
}

# ---------------------------------------------------------------------------
# Extension picker
# ---------------------------------------------------------------------------
# Interactive multi-select TUI, modeled on the clean-up scripts:
#   ↑/↓ or j/k move · Space toggle · a all/none · i invert · Enter install · q skip
# When stdin/stdout is not a terminal (pipes, CI, `</dev/null`) it falls back to
# a numbered prompt so automation keeps working.
ext_tui_cleanup() {
    printf '\033[?25h'
    printf '\033[?1049l'
    stty echo 2>/dev/null || true
}

ext_selected_count() {
    local i count=0
    for i in "${!EXT_IDS[@]}"; do
        [[ "${EXT_SELECTED[$i]:-0}" -eq 1 ]] && count=$((count + 1))
    done
    echo "$count"
}

ext_draw_tui() {
    local lines max_rows i start end last_group mark state count group out prev_group

    lines="$(tput lines 2>/dev/null || echo 24)"
    max_rows=$((lines - 16))
    (( max_rows < 4 )) && max_rows=4
    (( max_rows > ${#EXT_IDS[@]} )) && max_rows=${#EXT_IDS[@]}

    if (( EXT_CUR < EXT_SCROLL )); then
        EXT_SCROLL=$EXT_CUR
    elif (( EXT_CUR >= EXT_SCROLL + max_rows )); then
        EXT_SCROLL=$((EXT_CUR - max_rows + 1))
    fi
    local lines max_rows i start end last_group mark state count group out prev_group

    lines="$(tput lines 2>/dev/null || echo 24)"
    max_rows=$((lines - 16))
    (( max_rows < 4 )) && max_rows=4
    (( max_rows > ${#EXT_IDS[@]} )) && max_rows=${#EXT_IDS[@]}

    if (( EXT_CUR < EXT_SCROLL )); then
        EXT_SCROLL=$EXT_CUR
    elif (( EXT_CUR >= EXT_SCROLL + max_rows )); then
        EXT_SCROLL=$((EXT_CUR - max_rows + 1))
    fi

    out=""
    out+=$'\033[H'
    out+=$'\033[2K'"  $(bold "Shell-Setup Extensions")"$'\n'
    out+=$'\033[2K'"  $(dim "Space toggles selections, Enter installs the selected tools.")"$'\n'
    out+=$'\033[2K\n'

    start=$EXT_SCROLL
    end=$((EXT_SCROLL + max_rows - 1))
    (( end >= ${#EXT_IDS[@]} )) && end=$(( ${#EXT_IDS[@]} - 1 ))

    last_group=""
    for ((i = start; i <= end; i++)); do
        group="${EXT_GROUPS[$i]:-}"
        if (( i == start )); then
            prev_group="${EXT_GROUPS[$((start - 1))]:-}"
            if [[ -n "$group" && "$group" != "$prev_group" ]]; then
                last_group="$group"
                out+=$'\033[2K'"      $(bold "$group")"$'\n'
            else
                last_group="$group"
            fi
        else
            if [[ -n "$group" && "$group" != "$last_group" ]]; then
                last_group="$group"
                out+=$'\033[2K'"      $(bold "$group")"$'\n'
            fi
        fi

        mark="[ ]"
        [[ "${EXT_SELECTED[$i]:-0}" -eq 1 ]] && mark="$(green "[x]")"

        state=""
        [[ "${EXT_INSTALLED[$i]:-0}" -eq 1 ]] && state=" $(dim "[installed]")"

        if (( i == EXT_CUR )); then
            out+=$'\033[2K'"  $(cyan "❯") $mark $(printf '%-14s' "${EXT_NAMES[$i]:-}") $(dim "${EXT_DESCS[$i]:-}")$state"$'\n'
        else
            out+=$'\033[2K'"    $mark $(printf '%-14s' "${EXT_NAMES[$i]:-}") $(dim "${EXT_DESCS[$i]:-}")$state"$'\n'
        fi
    done

    out+=$'\033[2K\n'
    count="$(ext_selected_count)"
    out+=$'\033[2K'"  $(bold "$count") selected"
    if (( ${#EXT_IDS[@]} > max_rows )); then
        out+="   $(dim "[$((EXT_SCROLL + 1))-$((end + 1)) of ${#EXT_IDS[@]}]")"
    fi
    out+=$'\n'
    out+=$'\033[2K'"  $(dim "↑/↓ move · Space toggle · a all/none · i invert · Enter install · q skip")"$'\n'
    out+=$'\033[J'

    printf '%s' "$out"
}

# Returns 0 when the user confirmed, 1 when they cancelled or hit EOF.
ext_select_tui() {
    local key c1 c2 i any rc=0

    stty -echo 2>/dev/null || true
    printf '\033[?1049h'
    printf '\033[?25l'
    ext_draw_tui
    trap 'ext_tui_cleanup; exit 130' INT TERM

    while :; do
        if ! IFS= read -rsn1 key 2>/dev/null; then
            break
        fi
        [[ -z "$key" ]] && break

        if [[ "$key" == $'\033' ]]; then
            read -rsn1 -t 0.05 c1 2>/dev/null || c1=""
            if [[ "$c1" == "[" || "$c1" == "O" ]]; then
                read -rsn1 -t 0.05 c2 2>/dev/null || c2=""
                key="$key$c1$c2"
            elif [[ -n "$c1" ]]; then
                key="$key$c1"
            fi
        fi

        case "$key" in
            $'\033[A'|$'\033OA'|k|K)
                EXT_CUR=$((EXT_CUR - 1))
                (( EXT_CUR < 0 )) && EXT_CUR=$(( ${#EXT_IDS[@]} - 1 ))
                ext_draw_tui
                ;;
            $'\033[B'|$'\033OB'|j|J)
                EXT_CUR=$((EXT_CUR + 1))
                (( EXT_CUR >= ${#EXT_IDS[@]} )) && EXT_CUR=0
                ext_draw_tui
                ;;
            ' ')
                if [[ "${EXT_SELECTED[$EXT_CUR]:-0}" -eq 1 ]]; then
                    EXT_SELECTED[$EXT_CUR]=0
                else
                    EXT_SELECTED[$EXT_CUR]=1
                fi
                ext_draw_tui
                ;;
            a|A)
                # Select all when anything is unselected, otherwise clear all.
                any=0
                for i in "${!EXT_IDS[@]}"; do
                    [[ "${EXT_SELECTED[$i]:-0}" -eq 0 ]] && any=1
                done
                for i in "${!EXT_IDS[@]}"; do
                    EXT_SELECTED[$i]=$any
                done
                ext_draw_tui
                ;;
            i|I)
                for i in "${!EXT_IDS[@]}"; do
                    if [[ "${EXT_SELECTED[$i]:-0}" -eq 1 ]]; then
                        EXT_SELECTED[$i]=0
                    else
                        EXT_SELECTED[$i]=1
                    fi
                done
                ext_draw_tui
                ;;
            q|Q|$'\033')
                rc=1
                break
                ;;
            ''|$'\n'|$'\r')
                break
                ;;
        esac
    done

    ext_tui_cleanup
    trap - INT TERM
    return "$rc"
}

# Line-based picker used when stdin/stdout is not a terminal.
ext_select_prompt() {
    echo "  Select what to install (space-separated numbers, 'a' for all, 'n' to skip):"
    echo

    local last_group="" i state
    for i in "${!EXT_IDS[@]}"; do
        if [[ "${EXT_GROUPS[$i]:-}" != "$last_group" ]]; then
            last_group="${EXT_GROUPS[$i]:-}"
            echo "  $(bold "$last_group")"
        fi
        state=""
        [[ "${EXT_INSTALLED[$i]:-0}" -eq 1 ]] && state=" $(dim "[installed]")"
        printf "    %2d) %-14s — %s%s\n" "$((i + 1))" "${EXT_NAMES[$i]:-}" "${EXT_DESCS[$i]:-}" "$state"
    done
    echo

    local selection
    if ! read -r -p "  Choose: " selection; then
        return 1
    fi
    if [[ -z "$selection" ]]; then
        return 1
    fi
    if [[ "$selection" == [nN] ]]; then
        return 1
    fi

    if [[ "$selection" == [aA] ]]; then
        for i in "${!EXT_IDS[@]}"; do
            EXT_SELECTED[$i]=1
        done
        return 0
    fi

    local s
    for s in $selection; do
        if [[ ! "$s" =~ ^[0-9]+$ ]]; then
            warn "Ignoring invalid choice: $s"
            continue
        fi
        if ((s >= 1 && s <= ${#EXT_IDS[@]})); then
            EXT_SELECTED[$((s - 1))]=1
        else
            warn "Ignoring out-of-range choice: $s"
        fi
    done
    return 0
}

install_extensions_menu() {
    header "Extensions"

    ext_catalog

    # Cache installed state once: drawing must not shell out to dpkg per keypress.
    local i
    for i in "${!EXT_IDS[@]}"; do
        EXT_SELECTED[$i]=0
        if ext_installed "$i"; then
            EXT_INSTALLED[$i]=1
        else
            EXT_INSTALLED[$i]=0
        fi
    done

    if [[ -t 0 && -t 1 ]]; then
        if ! ext_select_tui; then
            info "Skipping extensions."
            return 0
        fi
    else
        if ! ext_select_prompt; then
            info "Skipping extensions."
            return 0
        fi
    fi

    local -a chosen=()
    for i in "${!EXT_IDS[@]}"; do
        [[ "${EXT_SELECTED[$i]}" -eq 1 ]] && chosen+=("${EXT_IDS[$i]}")
    done

    if [[ ${#chosen[@]} -eq 0 ]]; then
        info "Nothing selected."
        return 0
    fi

    echo
    info "Selected: $(bold "${chosen[*]}")"

    install_ext_ids "${chosen[@]}"
}

# Backward-compatible entry point used by --extensions.
install_extensions() {
    install_extensions_menu
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

    local custom_script="$HOME/.zsh/customizeGit.bash"
    if [[ ! -f "$custom_script" ]]; then
        custom_script="$REPO_DIR/zsh/customizeGit.bash"
    fi

    if [[ -f "$custom_script" ]]; then
        bash "$custom_script"
    else
        warn "customizeGit.bash not found. Run Option 3 (Git accounts & SSH) first."
    fi
}

# ---------------------------------------------------------------------------
# 6. SSH Key & Git Signing Setup
# ---------------------------------------------------------------------------
# Files are installed by install_ssh_files(); this function only runs the
# interactive helper, which now starts with an audit of existing keys.
setup_ssh() {
    header "SSH Key & Git Signing Setup"

    install_ssh_files

    if confirm "  Run the interactive SSH key setup now?" y; then
        run_ssh_setup
    else
        info "Skipped SSH key generation."
        info "You can run it anytime with: $(bold "bash ~/.ssh/setup.bash")"
    fi
}

# ---------------------------------------------------------------------------
# Interactive Menu
# ---------------------------------------------------------------------------
interactive_menu() {
    header "Shell-Setup Installer ($ENV_NAME)"

    echo "  What would you like to set up?"
    echo
    echo "    1) Shell environment   — Zsh, aliases, plugins, ~/.zshrc"
    echo "    2) Neovim editor       — config, EDITOR/VISUAL, git core.editor"
    echo "    3) Git accounts & SSH  — accounts, SSH keys, clone wrappers"
    echo "    4) Extensions          — multi-select languages and CLI tools"
    echo "    5) Everything          — run 1 → 2 → 3 → 4"
    echo "    q) Quit"
    echo

    local choice
    if ! read -r -p "  Choose [1-5/q]: " choice; then
        echo "  Exiting."
        exit 0
    fi

    case "$choice" in
        1)
            SHELL_OFFER_NVIM=1
            install_shell
            ;;
        2)
            install_nvim
            ;;
        3)
            install_git_ssh
            ;;
        4)
            install_extensions_menu
            ;;
        5)
            SHELL_OFFER_NVIM=0
            install_shell
            install_nvim
            install_git_ssh
            install_extensions_menu
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
       curl -fsSL https://raw.githubusercontent.com/Qiupi3/Shell-Setup/main/install.bash | bash

Modules:
  --shell         Option 1 — Zsh, aliases, git aliases, plugin, ~/.zshrc
  --nvim          Option 2 — Neovim config, EDITOR/VISUAL, core.editor
  --git           Option 3 — Git accounts, SSH key audit/setup, wrappers
  --ext [LIST]    Option 4 — multi-select picker, or comma-separated ids
                  (e.g. --ext python,node,antigravity)
                  AI tools: antigravity (agy), opencode (proot-distro only)
  --all           Options 1 + 2 + 3
  --everything    Options 1 + 2 + 3 + 4

Extension picker keys (Option 4 / --ext without a list):
  ↑/↓ or j/k move · Space toggle · a all/none · i invert · Enter install · q skip
  (pipes and </dev/null fall back to a numbered prompt)

Legacy options (still supported):
  --modules       Copy shell configs only (no packages, no default-shell change)
  --essentials    Install the union of module dependencies + recommended tools
  --zsh           Install zsh and set it as the default shell
  --ssh           Alias for --git
  --gitconfig     Only write ~/.gitconfig and allowed_signers
  --git-accounts  Only run customizeGit.bash
  --git-aliases   Install or update unified git aliases (alias: --submodules)
  --extensions    Alias for --ext (interactive)
  --node          Install Node.js
  --php           Install PHP
  --antigravity   Install Antigravity CLI
  --help, -h      Show this help message

When run without arguments, launches the interactive menu.

Recommended CLI tools (tree, which, man, less, curl, wget, unzip, file) are
optional: Option 1 lists what breaks without them and defaults to "no".

Supported environments:
  • Termux (Android)
  • macOS (Homebrew)
  • Linux — Debian / Ubuntu (apt), including proot-distro containers
EOF
}

# ---------------------------------------------------------------------------
# Main Entrypoint
# ---------------------------------------------------------------------------
main() {
    # Ensure common package manager paths are available (Termux/Android)
    if [[ -d /data/data/com.termux/files/usr/bin ]]; then
        export PATH="/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/sbin:$PATH"
    fi
    export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/.deno/bin:$HOME/.local/share/pnpm:$PATH"
    mkdir -p "$HOME/.local/bin" "$HOME/.opencode/bin" 2>/dev/null || true
    detect_env

    if [[ $# -eq 0 ]]; then
        interactive_menu
    else
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --shell)
                    SHELL_OFFER_NVIM=1
                    install_shell
                    shift
                    ;;
                --nvim)
                    install_nvim
                    shift
                    ;;
                --git)
                    install_git_ssh
                    shift
                    ;;
                --ext)
                    shift
                    if [[ $# -gt 0 && "$1" != -* ]]; then
                        local ext_list
                        ext_list="$(echo "$1" | tr ',' ' ')"
                        ext_catalog
                        # shellcheck disable=SC2086
                        install_ext_ids $ext_list
                        shift
                    else
                        install_extensions_menu
                    fi
                    ;;
                --all)
                    SHELL_OFFER_NVIM=0
                    install_shell
                    install_nvim
                    install_git_ssh
                    shift
                    ;;
                --everything)
                    SHELL_OFFER_NVIM=0
                    install_shell
                    install_nvim
                    install_git_ssh
                    install_extensions_menu
                    shift
                    ;;
                --modules)
                    install_shell_configs
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
                    install_git_ssh
                    shift
                    ;;
                --gitconfig)
                    setup_gitconfig
                    shift
                    ;;
                --git-accounts)
                    setup_git_accounts
                    patch_zshrc
                    shift
                    ;;
                --git-aliases|--submodules)
                    setup_git_aliases
                    patch_zshrc
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
    if cmd_exists zsh; then
        info "Load the new configuration now: $(bold "exec zsh")"
        info "or restart your terminal. $(dim "(Do not run 'source ~/.zshrc' from bash.)")"
    else
        info "Restart your terminal to load the new configuration."
    fi
}

main "$@"
