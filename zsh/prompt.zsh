# Git-aware prompt
git_prompt() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return

    local branch
    local staged="" unstaged="" untracked="" stash="" ahead="" behind=""

    # Branch
    branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)
    [[ -z "$branch" ]] && branch=$(git describe --tags --exact-match 2>/dev/null)
    [[ -z "$branch" ]] && branch=$(git rev-parse --short HEAD)

    # Staged count
    local staged_count
    staged_count=$(git diff --cached --name-only | wc -l | tr -d ' ')
    (( staged_count )) && staged="+${staged_count}"

    # Modified (unstaged)
    local unstaged_count
    unstaged_count=$(git diff --name-only | wc -l | tr -d ' ')
    (( unstaged_count )) && unstaged="~${unstaged_count}"

    # Untracked
    local untracked_count
    untracked_count=$(git ls-files --others --exclude-standard | wc -l | tr -d ' ')
    (( untracked_count )) && untracked="?${untracked_count}"

    # Stash
    local stash_count
    stash_count=$(git stash list | wc -l | tr -d ' ')
    (( stash_count )) && stash="\$${stash_count}"

    # Ahead / Behind
    if git rev-parse @{upstream} >/dev/null 2>&1; then
        local counts
        counts=$(git rev-list --left-right --count @{upstream}...HEAD)
        local behind_count ahead_count
        read -r behind_count ahead_count <<< "$counts"
        (( ahead_count )) && ahead="⇡${ahead_count}"
        (( behind_count )) && behind="⇣${behind_count}"
    fi

    echo " %F{220}(${branch} ${ahead} ${behind} ${staged} ${unstaged} ${untracked} ${stash})%f"
}

autoload -Uz colors
colors

setopt PROMPT_SUBST

PROMPT='
%B%F{39}▸%f %F{39}%n%f%F{196}@%f%F{82}%m%f %F{39}%40<..<%~%<<%f%b%F{220}$(git_prompt)%f
%B%F{196}$%f%b '
