# =============================================================================
# Linux (proot-distro / Ubuntu / Debian) Non-Git Configurations & Aliases (Base)
# Sourced via ~/.zsh/base.zsh
# =============================================================================

# Run a command as root when needed. proot-distro containers run as root and
# usually have no sudo; normal desktops run as a user and do have it.
_apt_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        "$@"
    fi
}

# Package management convenience shortcuts (apt/apt-get)
aptup() { _apt_root apt update && _apt_root apt upgrade; }
aptin() { _apt_root apt install "$@"; }
aptrm() { _apt_root apt remove "$@"; }
aptse() { apt search "$@"; }
aptls() { apt list --installed; }

# proot-distro Termux host path shortcuts (accessible via proot bind mounts)
alias termux-home='cd /data/data/com.termux/files/home'
alias termux-prefix='cd /data/data/com.termux/files/usr'
