# =============================================================================
# Linux (proot-distro / Ubuntu) Non-Git Configurations & Aliases (Base)
# Sourced via ~/.zsh/base.zsh
# =============================================================================

# Package management convenience shortcuts (apt/apt-get)
alias aptup='sudo apt update && sudo apt upgrade'
alias aptin='sudo apt install'
alias aptrm='sudo apt remove'
alias aptse='apt search'
alias aptls='apt list --installed'

# proot-distro Termux host path shortcuts (accessible via proot bind mounts)
alias termux-home='cd /data/data/com.termux/files/home'
alias termux-prefix='cd /data/data/com.termux/files/usr'
