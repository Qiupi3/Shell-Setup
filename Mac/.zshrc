# =============================================================================
# macOS Zsh Configuration
# Modular setup — aliases, prompt, and git tools are sourced from ~/.zsh/
# =============================================================================

# This file is zsh-only. Sourcing it from bash produces confusing
# "setopt: command not found" and "parse error near '('" messages, so stop
# early with a useful hint instead.
if [ -n "${BASH_VERSION:-}" ]; then
    echo "~/.zshrc is a zsh configuration. Start zsh with: exec zsh" >&2
    return 1 2>/dev/null || exit 1
fi

# >>> PATH Configuration >>>
path_dirs=(
  /opt/homebrew/bin       # Homebrew (Apple Silicon)
  /opt/homebrew/sbin      # Homebrew system binaries
  /usr/local/bin          # User-installed tools
  /usr/bin                # macOS system binaries
  /bin                    # Core Unix binaries
  /usr/sbin               # System admin tools
  /sbin                   # Essential system admin tools
)
export PATH=$(IFS=:; echo "${path_dirs[*]}")

# Android Studio SDK
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools

# Antigravity CLI & IDE (if installed)
[[ -d "$HOME/.antigravity/antigravity/bin" ]] && export PATH="$HOME/.antigravity/antigravity/bin:$PATH"
[[ -d "$HOME/.antigravity-ide/antigravity-ide/bin" ]] && export PATH="$HOME/.antigravity-ide/antigravity-ide/bin:$PATH"
[[ -d "/opt/homebrew/opt/libpq/bin" ]] && export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

# >>> History >>>
HISTFILE=$HOME/.zsh_history
HISTSIZE=50000
SAVEHIST=50000

setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY

# >>> Completion >>>
fpath=(
    "$(brew --prefix 2>/dev/null)/share/zsh/site-functions"
    /usr/local/share/zsh-completions
    $fpath
)

autoload -Uz compinit
compinit

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'

# >>> Exports >>>
# EDITOR / VISUAL are managed by the Neovim module (Option 2).

# >>> Source configs from ~/.zsh/ >>>
for f in ~/.zsh/*.zsh(N); do
    source "$f"
done

# Plugins (must be last)
if [[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
elif command -v brew &>/dev/null && [[ -f "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
    source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
