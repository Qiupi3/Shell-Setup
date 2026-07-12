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
export EDITOR=nvim
export VISUAL=nvim

# >>> Source configs from ~/.zsh/ >>>
for f in ~/.zsh/*.zsh(N); do
    source "$f"
done

# Plugins (must be last)
[[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
    source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
