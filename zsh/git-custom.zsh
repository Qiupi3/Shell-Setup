# EQLINE function
EQLINE() {
    echo "================================"
    echo "================================"
}

# reset_vConfig function
# Function to reset configured local git Signing Key
reset_vConfig() {
    git config --unset commit.gpgsign
    git config --unset gpg.format
    git config --unset user.signingkey
}

# ============================================================
# Custom gClone function using SSH (Host) based Git Clone
#
# Supports:
#   gClone <repo>
#   gClone <user> <repo>
#   gClone <user/repo>
#   gClone <https://github.com/user/repo>
#   gClone <git@github.com:user/repo.git>
# ============================================================
gClone() {
    EQLINE
    echo "Git Cloning"

    local ACCOUNT="$1"
    shift

    local CONFIG_FUNC="$1"
    shift

    local DEFAULT_USER="$ACCOUNT"

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
            echo "  <wrapper> <repo>"
            echo "  <wrapper> <user> <repo>"
            echo "  <wrapper> <user/repo>"
            echo "  <wrapper> <https://github.com/user/repo>"
            echo "  <wrapper> <git@github.com:user/repo.git>"
            return 1
            ;;
    esac

    echo "==============CLONE DETAILS=============="
    echo "Account : $ACCOUNT"
    echo "Repo    : $REPO_OWNER/$REPO"
    echo

    if git clone "git@github.com-${ACCOUNT}:${REPO_OWNER}/${REPO}.git"; then
        echo "Clone successful."
    else
        echo "Clone failed."
        return 1
    fi

    cd "$REPO" || {
        echo "Failed to enter repository."
        return 1
    }

    if [ "$REPO_OWNER" = "$DEFAULT_USER" ]; then
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

# ============================================================
# Account Specific Git Configurations & Clone Wrappers
# Managed by customizeGit.bash
# ============================================================
