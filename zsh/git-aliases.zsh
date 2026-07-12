# =============================================================================
# Unified Git Aliases & Utilities (zsh/git-aliases.zsh)
#
# Complete, cross-platform Git shortcuts and workflow helpers.
# Includes submodule shortcuts, commit author override, commit signing,
# stashing, worktrees, branching, and safety indicators.
#
# Legend:
#   [DESTRUCTIVE] : Modifies/deletes history, uncommitted work, or remote refs.
#   [NON-DESTRUCTIVE] : Safe inspection, staging, or non-destructive operation.
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Setup & Configuration
# -----------------------------------------------------------------------------
alias g='git'                                   # Shortcut to run git
alias gi='git init'                             # Initialize a new local Git repository

alias gcf='git config'                          # Get and set repository or global options
alias gcfg='git config --global'                # Set or view global Git configuration options
alias gcfgl='git config --global --list'        # List all global Git configurations
alias gcl='git config list'                     # List all configurations (local, global, system)
alias gcg='git config get'                      # Get value for a specific configuration key
alias gcs='git config set'                      # Set value for a specific configuration key
alias gcu='git config unset'                    # Unset a configuration key

# -----------------------------------------------------------------------------
# 2. Remote Repositories
# -----------------------------------------------------------------------------
alias go='git remote'                           # Manage set of tracked repositories
alias gov='git remote -v'                       # List remotes with URLs
alias gos='git remote show'                     # Show detailed info about a specific remote
alias goa='git remote add'                      # Add a new remote connection
alias goan='git remote add origin'              # Add 'origin' as the default remote name
alias gorn='git remote rename'                  # Rename an existing remote connection
alias gorm='git remote remove'                  # [DESTRUCTIVE] Remove a remote connection

alias gosh='git remote set-head'                # Set HEAD to a remote connection (use -a for auto)
alias goshoa='git remote set-head origin -a'    # Fetch HEAD from origin and set automatically
alias gosb='git remote set-branches'            # Set branches tracked by remote
alias gosba='git remote set-branches --add'     # Add branch to be tracked by remote

# -----------------------------------------------------------------------------
# 3. Git Submodule Shortcuts (Unified in one file)
# -----------------------------------------------------------------------------
alias gsm='git submodule'                                   # Base git submodule command
alias gsmi='git submodule init'                             # Initialize submodules in .git/config
alias gsmu='git submodule update'                           # Update registered submodules
alias gsmui='git submodule update --init'                   # Initialize and update submodules in one step
alias gsmuir='git submodule update --init --recursive'      # Recursively initialize and update all submodules
alias gsmur='git submodule update --remote'                 # Update submodules to latest remote HEAD
alias gsmurm='git submodule update --remote --merge'        # Update submodules to latest remote HEAD and merge

alias gsma='git submodule add'                              # Add a new repository as a submodule
alias gsmd='git submodule deinit'                           # Unregister a submodule from .git/config
alias gsmdf='git submodule deinit -f'                       # [DESTRUCTIVE] Force unregister and discard submodule changes

# Fully remove a submodule (deinit + git rm + clean .git/modules)
# usage: gsmrm <submodule-path>
gsmrm() {
    if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gsmrm <submodule-path>"
        echo "Example: gsmrm vendor/my-plugin"
        echo "[!] DESTRUCTIVE: Permanently deinitializes, removes submodule files, and deletes .git/modules/<path>"
        return 1
    fi
    local path="$1"
    echo "[DESTRUCTIVE] Removing submodule: $path"
    git submodule deinit -f "$path"
    git rm -f "$path"
    rm -rf ".git/modules/$path"
    echo "Submodule '$path' removed."
}

alias gsms='git submodule status'                           # Show status and commit SHA of all submodules
alias gsmsr='git submodule status --recursive'              # Show status of all submodules recursively
alias gsmsm='git submodule summary'                         # Show commit summary between index and submodule HEAD

alias gsmfe='git submodule foreach'                         # Run command in each submodule
alias gsmfer='git submodule foreach --recursive'            # Recursively run command in each submodule

alias gsmsync='git submodule sync'                          # Sync submodule URLs from .gitmodules to .git/config
alias gsmsyncr='git submodule sync --recursive'             # Recursively sync submodule URLs

# Pull latest commits for all submodules on main or master
alias gsmpl='git submodule foreach "git pull origin main || git pull origin master || true"'

# Checkout specific branch across all submodules
# usage: gsmch <branch>
gsmch() {
    if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gsmch <branch-name>"
        echo "Example: gsmch main"
        echo "Description: Switches all submodules to the specified branch."
        return 1
    fi
    git submodule foreach "git checkout $1 || true"
}

alias gsmdiff='git diff --submodule'                        # Show differences in submodule commits
alias gsmdiffs='git diff --cached --submodule'              # Show differences in staged submodule commits

# -----------------------------------------------------------------------------
# 4. Fetching, Pulling & Pushing
# -----------------------------------------------------------------------------
alias gl='git pull'                                         # Fetch from and integrate with remote branch
alias glf='git pull --ff-only'                              # Pull only if fast-forward is possible (avoids merge commits)
alias glr='git pull --rebase'                               # Pull and replay local commits on top of upstream branch
alias gln='git pull --no-rebase'                            # Pull and create a merge commit if diverging
alias gls='git pull --squash'                               # Pull and squash upstream changes into working tree
alias glfh='git fetch origin && git reset --hard origin/main' # [DESTRUCTIVE] Discard local commits and reset to origin/main
alias glfs='git stash -u && git pull origin main'           # Safely stash unstaged/untracked changes before pulling

alias gh='git push'                                         # Push committed changes to remote repository
alias ghom='git push origin main'                           # Push current branch to origin main
alias ghf='git push --force'                                # [DESTRUCTIVE] Force push to remote, overwriting remote history
alias ghu='git push --set-upstream'                         # Push and set upstream tracking reference
alias ghuo='git push -u origin'                             # Push and set tracking to origin
alias ghuom='git push -u origin main'                       # Push and set tracking to origin main

alias gf='git fetch'                                        # Download objects and refs from remote repository
alias gfo='git fetch origin'                                # Fetch latest refs from origin
alias gfp='git fetch -p'                                    # Fetch and prune deleted remote-tracking branches

# -----------------------------------------------------------------------------
# 5. Snapshotting & Staging
# -----------------------------------------------------------------------------
alias ga='git add'                                          # Add file contents to the staging area
alias gap='git add -p'                                      # Interactively choose hunks of changes to stage
alias gal='git add .'                                       # Stage all changes in the current directory

alias gr='git restore'                                      # [DESTRUCTIVE] Discard unstaged changes in specified files
alias grl='git restore .'                                   # [DESTRUCTIVE] Discard all unstaged changes in current directory
alias grs='git restore --staged'                            # Unstage file changes while preserving modifications in worktree
alias grsl='git restore --staged .'                         # Unstage all staged changes in current directory

# Pull / restore a file from another branch or commit
# usage: grsf <source-branch/commit> <file-path>
grsf() {
    if [[ $# -lt 2 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: grsf <branch-or-commit> <file-path>"
        echo "Example: grsf main src/app.js"
        echo "Description: Restores a file from a specified commit or branch into working tree."
        return 1
    fi
    git restore --source="$1" "$2"
}
alias gchf='grsf'                                           # Checkout file compatibility alias

alias gst='git status'                                      # Show working tree status
alias gsts='git status -s'                                  # Show working tree status in short format
alias gsth='git status --show-stash'                        # Show status including stash count

# -----------------------------------------------------------------------------
# 6. Committing & Identity Management
# -----------------------------------------------------------------------------
alias gc='git commit'                                       # Record staged changes to repository
alias gcpatch='git commit -p'                               # Interactively choose hunks to commit
alias gca='git commit -a'                                   # Automatically stage modified tracked files and commit
alias gm='git commit -m'                                    # Commit staged changes with message
alias gam='git commit -am'                                  # Stage modified files and commit with message
alias gv='git commit -v'                                    # Commit with verbose diff shown in commit editor
alias gav='git commit -av'                                  # Stage modified files and commit with verbose diff in editor

alias gcamend='git commit --amend'                          # [REWRITE] Amend tip of current branch
alias gcan='git commit --amend --no-edit'                   # [REWRITE] Amend last commit without altering commit message
alias gcra='git commit --reset-author'                      # Reset author identity to current git config when amending

# Commit as someone else, then automatically reset author/committer env vars
# usage: gcase "Author Name" "author@example.com" "Commit message"
gcase() {
    if [[ $# -lt 3 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gcase <author-name> <author-email> <commit-message>"
        echo "Example: gcase \"Jane Doe\" \"jane@example.com\" \"feat: add authentication\""
        echo "Description: Commits staged changes with custom author and committer identity,"
        echo "             and automatically resets identity env vars afterwards."
        return 1
    fi

    local name="$1"
    local email="$2"
    local msg="$3"

    export GIT_AUTHOR_NAME="$name"
    export GIT_AUTHOR_EMAIL="$email"
    export GIT_COMMITTER_NAME="$name"
    export GIT_COMMITTER_EMAIL="$email"

    git commit -m "$msg"
    local ret=$?

    gcclear
    return $ret
}

# Temporarily export author identity
gauthor() {
    if [[ $# -lt 2 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gauthor <name> <email>"
        echo "Example: gauthor \"John Doe\" \"john@example.com\""
        echo "Description: Sets GIT_AUTHOR_NAME and GIT_AUTHOR_EMAIL in current shell. Use gcclear to reset."
        return 1
    fi
    export GIT_AUTHOR_NAME="$1"
    export GIT_AUTHOR_EMAIL="$2"
}

# Temporarily export committer identity
gcommitter() {
    if [[ $# -lt 2 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gcommitter <name> <email>"
        echo "Example: gcommitter \"John Doe\" \"john@example.com\""
        echo "Description: Sets GIT_COMMITTER_NAME and GIT_COMMITTER_EMAIL in current shell. Use gcclear to reset."
        return 1
    fi
    export GIT_COMMITTER_NAME="$1"
    export GIT_COMMITTER_EMAIL="$2"
}

gauthordate() {
    if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gauthordate <date-string>"
        echo "Example: gauthordate \"2026-01-01 12:00:00\""
        return 1
    fi
    export GIT_AUTHOR_DATE="$*"
}

gcommitterdate() {
    if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gcommitterdate <date-string>"
        echo "Example: gcommitterdate \"2026-01-01 12:00:00\""
        return 1
    fi
    export GIT_COMMITTER_DATE="$*"
}

gcdate() {
    if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gcdate <date-string>"
        echo "Example: gcdate \"2026-01-01 12:00:00\""
        return 1
    fi
    export GIT_AUTHOR_DATE="$1"
    export GIT_COMMITTER_DATE="$1"
}

# Reset temporary author and committer environment variables
gcclear() {
    unset GIT_AUTHOR_NAME
    unset GIT_AUTHOR_EMAIL
    unset GIT_AUTHOR_DATE

    unset GIT_COMMITTER_NAME
    unset GIT_COMMITTER_EMAIL
    unset GIT_COMMITTER_DATE
}

# Show currently active author and committer identities
gcshow() {
    local src
    src() { [[ -n $1 ]] && echo "env" || echo "config"; }

    printf "Author\n"
    printf "  Name : %s [%s]\n" \
        "${GIT_AUTHOR_NAME:-$(git config --get user.name 2>/dev/null)}" \
        "$(src "$GIT_AUTHOR_NAME")"

    printf "  Email: %s [%s]\n" \
        "${GIT_AUTHOR_EMAIL:-$(git config --get user.email 2>/dev/null)}" \
        "$(src "$GIT_AUTHOR_EMAIL")"

    printf "  Date : %s [%s]\n\n" \
        "${GIT_AUTHOR_DATE:-<unset>}" \
        "$([[ -n $GIT_AUTHOR_DATE ]] && echo env || echo default)"

    printf "Committer\n"
    printf "  Name : %s [%s]\n" \
        "${GIT_COMMITTER_NAME:-$(git config --get user.name 2>/dev/null)}" \
        "$(src "$GIT_COMMITTER_NAME")"

    printf "  Email: %s [%s]\n" \
        "${GIT_COMMITTER_EMAIL:-$(git config --get user.email 2>/dev/null)}" \
        "$(src "$GIT_COMMITTER_EMAIL")"

    printf "  Date : %s [%s]\n" \
        "${GIT_COMMITTER_DATE:-<unset>}" \
        "$([[ -n $GIT_COMMITTER_DATE ]] && echo env || echo default)"
}

# Commit as a squash commit against target SHA
gsq() {
    if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gsq <commit-sha>"
        echo "Example: gsq a1b2c3d"
        echo "Description: Creates a squash commit meant to be folded into <commit-sha>."
        return 1
    fi
    git commit --squash="$1"
}

# Squash and rebase directly with autosquash
gcfix() {
    if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gcfix <commit-sha>"
        echo "Example: gcfix a1b2c3d"
        echo "[!] REWRITE HISTORY: Automatically commits staged changes as squash and rebases back to <commit-sha>~1"
        return 1
    fi
    git commit --squash="$1" && git rebase -i --autosquash "$1~1"
}

# -----------------------------------------------------------------------------
# 7. Viewing Changes & Diffs
# -----------------------------------------------------------------------------
alias gd='git diff'                                         # Show unstaged diff between working tree and index
alias gds='git diff --staged'                               # Show staged diff between index and last commit
alias gdn='git diff --name-only'                            # Show only names of changed unstaged files
alias gdns='git diff --name-status'                         # Show names and status (M, D, A) of changed unstaged files
alias gdsn='git diff --staged --name-only'                  # Show only names of staged changed files
alias gdsns='git diff --staged --name-status'               # Show names and status of staged changed files
alias gdw='git diff -w'                                     # Show unstaged diff ignoring all whitespace changes
alias gdsw='git diff --staged -w'                           # Show staged diff ignoring all whitespace changes

# -----------------------------------------------------------------------------
# 8. Resetting Changes & History
# -----------------------------------------------------------------------------
alias grt='git reset'                                       # Unstage changes while keeping files modified on disk
alias grts='git reset --soft'                               # Undo commit(s) while keeping changes staged
alias grth='git reset --hard'                               # [DESTRUCTIVE] Delete uncommitted changes & reset HEAD to target
alias grmc='git rm --cached'                                # Untrack file from repository while keeping it on disk

# -----------------------------------------------------------------------------
# 9. Branching & Merging
# -----------------------------------------------------------------------------
alias gb='git branch'                                       # List local branches
alias gba='git branch -a'                                   # List both local and remote-tracking branches
alias gbv='git branch -v'                                   # List local branches with latest commit info
alias gbva='git branch -va'                                 # List all branches with commit info
alias gbd='git branch -d'                                   # Safely delete a merged local branch
alias gbdf='git branch -D'                                  # [DESTRUCTIVE] Force delete a local branch
alias gbdo='git push origin -d'                             # [DESTRUCTIVE] Delete a branch on origin remote
alias gbm='git branch -m'                                   # Rename current local branch

# Delete branch on specified remote
# usage: gbdr <remote-name> <branch-name>
gbdr() {
    if [[ $# -lt 2 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gbdr <remote-name> <branch-name>"
        echo "Example: gbdr origin feature-branch"
        echo "[!] DESTRUCTIVE: Permanently deletes <branch-name> from remote <remote-name>."
        return 1
    fi
    echo "[DESTRUCTIVE] Deleting branch '$2' from remote '$1'..."
    git push "$1" -d "$2"
}

alias gch='git checkout'                                    # Switch branch or restore files
alias gchb='git checkout -b'                                # Create and switch to a new branch
alias gcho='git checkout --orphan'                          # Create a new orphaned branch with no commit history

alias gs='git switch'                                       # Switch to an existing branch
alias gsc='git switch -c'                                   # Create and switch to a new branch

alias gmg='git merge'                                       # Merge changes from specified branch into current branch

# -----------------------------------------------------------------------------
# 10. Commit History & Logs
# -----------------------------------------------------------------------------
alias glg='git log'                                         # Show full commit history
alias glgo='git log --oneline'                              # Show one-line commit history (SHA + subject)
alias glgg='git log --graph'                                # Show text-based visual commit history graph
alias glgga='git log --graph --decorate --all'              # Show graph of all local and remote branches
alias glgs='git log --show-signature'                       # Show commit history with signature verification
alias glgos='git log --show-signature --oneline'            # Show one-line commit history with signature status

# -----------------------------------------------------------------------------
# 11. Stash Management
# -----------------------------------------------------------------------------
alias gas='git stash'                                       # Stash modified and staged changes
alias gasm='git stash push -m'                              # Stash changes with a descriptive message
alias gasu='git stash -u'                                   # Stash changes including untracked files
alias gasmu='git stash push -u -m'                          # Stash untracked files with a descriptive message
alias gasa='git stash -a'                                   # [SAFETY NOTE] Stash all files including ignored files
alias gasam='git stash push -a -m'                          # Stash all files including ignored with a message

alias gasl='git stash list'                                 # List all stash entries
alias gass='git stash show'                                 # Show summary diff of top stash entry
alias gasf='git stash show -p'                              # Show full patch diff of top stash entry

alias gasp='git stash pop'                                  # Apply and remove the latest stash entry
alias gasy='git stash apply'                                # Apply latest stash entry without removing it

# Apply stash by descriptive message or name pattern
# usage: gasym <pattern>
gasym() {
    if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gasym <search-pattern>"
        echo "Example: gasym \"wip navbar\""
        echo "Description: Applies the most recent stash entry matching <search-pattern>."
        return 1
    fi
    git stash apply stash^{/"$1"}
}

alias gasd='git stash drop'                                 # [DESTRUCTIVE] Delete a single stash entry permanently
alias gasb='git stash branch'                               # Create & switch to new branch, then apply & drop stash

# -----------------------------------------------------------------------------
# 12. Tags
# -----------------------------------------------------------------------------
alias gtg='git tag'                                         # List tags or create lightweight tag

# Create annotated tag with message
# usage: gtga <tagname> <message>
gtga() {
    if [[ $# -lt 2 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gtga <tagname> <message>"
        echo "Example: gtga v1.0.0 \"Initial release\""
        return 1
    fi
    git tag -a "$1" -m "$2"
}

# Create annotated tag pointing to a past commit
# usage: gtgac <tagname> <commit-sha> <message>
gtgac() {
    if [[ $# -lt 3 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gtgac <tagname> <commit-sha> <message>"
        echo "Example: gtgac v0.9.0 a1b2c3d \"Backdated beta release\""
        return 1
    fi
    git tag -a "$1" "$2" -m "$3"
}

alias gtgl='git tag -l'                                     # List tags with optional wildcard filtering
alias gtgho='git push origin --tags'                        # Push all local tags to origin remote
alias gtgd='git tag -d'                                     # [DESTRUCTIVE] Delete a local tag
alias gtgdo='git push origin --delete'                      # [DESTRUCTIVE] Delete a tag on origin remote

# -----------------------------------------------------------------------------
# 13. Worktrees
# -----------------------------------------------------------------------------
alias gwt='git worktree'                                    # Manage multiple working trees attached to repository
alias gwta='git worktree add'                               # Create new worktree with an existing branch

# Create a new worktree with a newly created branch
# usage: gwtab <path> <new-branch-name>
gwtab() {
    if [[ $# -lt 2 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: gwtab <worktree-path> <new-branch-name>"
        echo "Example: gwtab ../hotfix hotfix-login"
        echo "Description: Creates directory <worktree-path> and checks out new branch <new-branch-name>."
        return 1
    fi
    git worktree add "$1" -b "$2"
}

alias gwtl='git worktree list'                              # List all linked worktrees
alias gwtd='git worktree remove'                            # [DESTRUCTIVE] Remove a worktree directory

# -----------------------------------------------------------------------------
# 14. Patching, Rebasing & Reverting
# -----------------------------------------------------------------------------
alias gcp='git cherry-pick'                                 # Apply changes introduced by existing commits
alias gcpn='git cherry-pick -n'                             # Cherry-pick changes into working tree without committing
alias gcpx='git cherry-pick -x'                             # Cherry-pick and record origin commit SHA in message
alias gcpc='git cherry-pick --continue'                     # Continue in-progress cherry-pick after conflict resolution
alias gcpa='git cherry-pick --abort'                        # Abort in-progress cherry-pick and return to pre-state

alias grb='git rebase'                                      # Reapply commits on top of another base tip
alias grbc='git rebase --continue'                          # Continue in-progress rebase after resolving conflicts
alias grba='git rebase --abort'                             # Abort in-progress rebase and reset to original branch state

alias gvt='git revert'                                      # Create new commit(s) that invert changes of specified commits

# -----------------------------------------------------------------------------
# 15. Investigation & Reflogs
# -----------------------------------------------------------------------------
alias gct='git bisect'                                      # Binary search to find commit that introduced a bug
alias gbl='git blame'                                       # Show revision and author for each line of a file
alias grf='git reflog'                                      # View reference logs to recover lost commits or actions

# -----------------------------------------------------------------------------
# 16. Index Manipulation (git update-index)
# -----------------------------------------------------------------------------
alias gui='git update-index'                                # Low-level command to manipulate the index directly
alias guia='git update-index --add'                         # Add a file to the index (register a new path)
alias guirm='git update-index --remove'                     # Remove a file from the index (unregister a path)
alias guixi='git update-index --skip-worktree'              # [NON-DESTRUCTIVE] Tell Git to ignore local changes to a tracked file
alias guixiu='git update-index --no-skip-worktree'          # Undo skip-worktree; resume tracking local changes for a file
alias guixa='git update-index --assume-unchanged'           # [NON-DESTRUCTIVE] Assume a tracked file is unchanged (performance hint)
alias guixau='git update-index --no-assume-unchanged'       # Undo assume-unchanged; re-enable change detection for a file
alias guich='git update-index --chmod'                      # Update the executable bit of a tracked file (+x or -x)
alias guir='git update-index --refresh'                     # Refresh stat info for all tracked files without changing content
alias guiq='git update-index --really-refresh'              # Refresh stat info and mark files changed if content differs

# List files with skip-worktree or assume-unchanged set
# usage: guils
guils() {
    echo "=== skip-worktree (guixi) ==="
    git ls-files -v | grep '^S' || echo "  (none)"
    echo "=== assume-unchanged (guixa) ==="
    git ls-files -v | grep '^h' || echo "  (none)"
}

# -----------------------------------------------------------------------------
# 17. File Listing (git ls-files)
# -----------------------------------------------------------------------------
alias glsf='git ls-files'                                   # List tracked files in the index
alias glsfv='git ls-files -v'                               # List tracked files with status flags (H, S, h, ?, etc.)
alias glsfu='git ls-files -o'                               # List untracked files not in the index
alias glsfui='git ls-files -o --exclude-standard'           # List untracked files, honouring .gitignore rules
alias glsfd='git ls-files -d'                               # List deleted tracked files (missing from working tree)
alias glsfm='git ls-files -m'                               # List modified tracked files (changed but not staged)
alias glsfc='git ls-files --cached'                         # List files in the index (same as glsf, explicit flag)
alias glsfs='git ls-files -s'                               # List staged files with mode, SHA, and stage number
alias glsfi='git ls-files -i --exclude-standard'            # List ignored files matching .gitignore rules

# Show all tracked files that are NOT in 'H' (normal) mode — i.e. skip-worktree, assume-unchanged, etc.
alias glsfnh='git ls-files -v | grep -v "^H"'              # [NON-DESTRUCTIVE] List index entries with non-H flags (S, h, M, etc.)

# -----------------------------------------------------------------------------
# 18. Checkout Index (git checkout-index)
# -----------------------------------------------------------------------------
alias gchi='git checkout-index'                             # Copy files from the index to the working tree
alias gchia='git checkout-index -a'                         # Copy all indexed files to the working tree
alias gchif='git checkout-index -f'                         # Force overwrite existing working-tree files from index
alias gchiaf='git checkout-index -a -f'                     # Force copy all indexed files, overwriting existing ones
alias gchiu='git checkout-index -u'                         # Update only files whose stat info differs (skip up-to-date)
alias gchip='git checkout-index --prefix'                   # Write checked-out files to a directory prefix instead of working tree

# -----------------------------------------------------------------------------
# 19. Remote Refs (git ls-remote)
# -----------------------------------------------------------------------------
alias glsr='git ls-remote'                                  # List references (branches, tags) on a remote without fetching
alias glsro='git ls-remote origin'                          # List all refs on origin remote
alias glsrh='git ls-remote --heads'                         # List only remote branch refs (refs/heads/*)
alias glsrho='git ls-remote --heads origin'                 # List remote branch refs on origin
alias glsrt='git ls-remote --tags'                          # List only remote tag refs (refs/tags/*)
alias glsrto='git ls-remote --tags origin'                  # List remote tag refs on origin
alias glsrq='git ls-remote --quiet'                         # Suppress diagnostic output while listing remote refs
