# This file is zsh-only. Sourcing it from bash produces confusing
# "setopt: command not found" and "parse error near '('" messages, so stop
# early with a useful hint instead.
if [ -n "${BASH_VERSION:-}" ]; then
    echo "~/.zshrc is a zsh configuration. Start zsh with: exec zsh" >&2
    return 1 2>/dev/null || exit 1
fi

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
    $PREFIX/share/zsh/site-functions
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
[[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
    source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
