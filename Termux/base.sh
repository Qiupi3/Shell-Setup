# =============================================================================
# Termux Non-Git Configurations & Aliases (Base)
# Sourced via ~/.zsh/base.zsh
# =============================================================================

# Termux storage / Android shortcuts (optional)
alias storage='cd /data/data/com.termux/files/home/storage'
alias sdcard='cd /sdcard'

# Package management convenience shortcuts
alias pkgup='pkg update && pkg upgrade'
alias pkgin='pkg install'
alias pkgrm='pkg uninstall'
alias pkgse='pkg search'

# proot-distro shortcuts (Termux host)
alias pd='proot-distro'            # Manage Linux containers
alias pdls='proot-distro list'     # List available and installed distros
alias pdi='proot-distro install'   # Install a distro (e.g. pdi ubuntu)
alias pdl='proot-distro login'     # Enter a distro (e.g. pdl ubuntu)
alias pdrm='proot-distro remove'   # [DESTRUCTIVE] Remove a distro
