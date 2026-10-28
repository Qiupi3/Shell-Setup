# General Aliases
alias grep='grep --color=auto'

# Go up through folder shortcut
alias ..='cd ..'
alias u='cd ..'
alias uu='cd ../..'
alias uuu='cd ../../..'
alias uuuu='cd ../../../..'
# Back to Android Project's root from app code
alias androot='cd ../../../../../../../..'

alias clist='ls -FGlAhp' # complete list
alias ll='ls -l' # list file with detailed attributes (permissions, owner, size, date)
alias la='ls -a' # list all file (including hidden)
alias lla='ls -la'
alias lao='ls -a1' # list all file in one column (1 row each)
alias lc='ls -1 | wc -l' # count number of file
alias lca='ls -a1 | wc -l' # count number of file (including hidden)

alias trd='tree -d' # list directory in tree view
alias tra='tree -a' # list all file in tree view
alias trin='tree -I "node_modules|.git|cache|vendor"' # list file excluding node_modules, .git, cache, and vendor folders
alias train='tree -a -I "node_modules|.git|cache|vendor"'
alias trdain='tree -da -I "node_modules|.git|cache|vendor"'
alias trda='tree -da'
alias trdl='tree -d -L' # list directory with level depth in tree view
alias trdal='tree -da -L'
alias trview="tree -a -L 2 -h -I 'node_modules|.git|cache'"
alias trp='tree -P' # match pattern

# SSH Setup Helper
alias ssh-setup='bash ~/.ssh/setup.bash'
alias setup-ssh='bash ~/.ssh/setup.bash'

# Git Account Customizer Helper
alias git-accounts='bash ~/.zsh/customizeGit.bash'
alias custom-git='bash ~/.zsh/customizeGit.bash'

# OpenCode
alias opc='opencode'
