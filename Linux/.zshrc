# =============================================================================
# Linux (Debian / Ubuntu / proot-distro) Zsh Configuration
# Modular setup — aliases, prompt, and git tools are sourced from ~/.zsh/
# =============================================================================

# >>> Shell-Setup managed >>>
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
# Debian and Ubuntu keep packaged completions in different directories.
# Keeping $fpath at the end preserves zsh's compiled-in defaults.
fpath=(
    /usr/local/share/zsh/site-functions
    /usr/share/zsh/site-functions
    /usr/share/zsh/vendor-functions
    /usr/share/zsh/vendor-completions
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
# <<< Shell-Setup managed <<<
