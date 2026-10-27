# Generic helper functions shared by the generated git-custom.zsh wrappers.
# Installed to ~/.zsh/git-functions.zsh by the Shell / Git modules.
#
# This file intentionally contains NO account data. Account-specific wrappers
# (<short>GClone, <short>_gConfig, <short>_vConfig) are generated locally into
# ~/.zsh/git-custom.zsh by customizeGit.bash.

# EQLINE function
EQLINE() {
    echo "================================"
    echo "================================"
}

# reset_vConfig function
# Function to reset configured local git Signing Key
reset_vConfig() {
    git config --unset commit.gpgsign 2>/dev/null || true
    git config --unset gpg.format 2>/dev/null || true
    git config --unset user.signingkey 2>/dev/null || true
}

# ============================================================
# Custom gClone function using SSH (Host) based Git Clone
#
# Account-aware form (used by <short>GClone wrappers):
#   gClone <account> <account>_gConfig <repo>
#
# Direct form (no account context, plain git@github.com):
#   gClone <user/repo>
#   gClone <https://github.com/user/repo>
#   gClone <git@github.com:user/repo.git>
#   gClone <user> <repo>
# ============================================================
gClone() {
    EQLINE
    echo "Git Cloning"

    local ACCOUNT=""
    local CONFIG_FUNC=""
    local DEFAULT_USER=""

    # Account-aware form only when the second argument is a generated
    # <short>_gConfig function. This keeps the documented direct form working.
    if [[ $# -ge 2 && "$2" == *_gConfig ]]; then
        ACCOUNT="$1"
        CONFIG_FUNC="$2"
        DEFAULT_USER="$ACCOUNT"
        shift 2
    fi

    local REPO_OWNER REPO INPUT URL

    case $# in
        1)
            INPUT="$1"

            case "$INPUT" in
                https://github.com/*)
                    URL="${INPUT#https://github.com/}"
                    REPO_OWNER="${URL%%/*}"
                    REPO="${URL#*/}"
                    REPO="${REPO%.git}"
                    ;;

                git@github.com:*)
                    URL="${INPUT#git@github.com:}"
                    REPO_OWNER="${URL%%/*}"
                    REPO="${URL#*/}"
                    REPO="${REPO%.git}"
                    ;;

                */*)
                    REPO_OWNER="${INPUT%%/*}"
                    REPO="${INPUT#*/}"
                    REPO="${REPO%.git}"
                    ;;

                *)
                    REPO_OWNER="$DEFAULT_USER"
                    REPO="${INPUT%.git}"
                    ;;
            esac
            ;;

        2)
            REPO_OWNER="$1"
            REPO="${2%.git}"
            ;;

        *)
            echo "Usage:"
            echo "  <account>GClone <repo>"
            echo "  <account>GClone <user> <repo>"
            echo "  <account>GClone <user/repo>"
            echo "  <account>GClone <https://github.com/user/repo>"
            echo "  <account>GClone <git@github.com:user/repo.git>"
            return 1
            ;;
    esac

    if [[ -z "$REPO_OWNER" || -z "$REPO" ]]; then
        echo "Could not determine repository owner/name from input." >&2
        return 1
    fi

    echo "==============CLONE DETAILS=============="
    echo "Account : ${ACCOUNT:-<none>}"
    echo "Repo    : $REPO_OWNER/$REPO"
    echo

    local remote
    if [[ -n "$ACCOUNT" ]]; then
        remote="git@github.com-${ACCOUNT}:${REPO_OWNER}/${REPO}.git"
    else
        remote="git@github.com:${REPO_OWNER}/${REPO}.git"
    fi

    if git clone "$remote"; then
        echo "Clone successful."
    else
        echo "Clone failed."
        return 1
    fi

    cd "$REPO" || {
        echo "Failed to enter repository."
        return 1
    }

    if [[ -n "$CONFIG_FUNC" && "$REPO_OWNER" == "$DEFAULT_USER" ]]; then
        echo "Match. ACCOUNT=$DEFAULT_USER, OWNER=$REPO_OWNER"
        echo "Configuring Git user..."
        "$CONFIG_FUNC"
    else
        echo "External repository detected."
        echo "Skipping Git configuration."
    fi

    echo
    echo "Done."

    EQLINE
}
