#!/bin/sh
# Universal trampoline: ensure execution under bash on Termux, macOS, and Linux
if [ -z "$BASH_VERSION" ]; then
    if [ -n "$PREFIX" ] && [ -x "$PREFIX/bin/bash" ]; then
        exec "$PREFIX/bin/bash" "$0" "$@"
    elif command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "Error: bash is required to run this script." >&2
        exit 1
    fi
fi
# =============================================================================
# Git Multi-Account Customizer & Manager
# Location: zsh/customizeGit.bash (installed to ~/.zsh/customizeGit.bash)
#
# Interactive TUI tool to manage multiple Git accounts:
#   - View configured Git accounts
#   - Add, edit, or delete accounts
#   - Automatically generates wrapper functions in git-custom.zsh:
#       <short>GClone(), <short>_gConfig(), <short>_vConfig()
#   - Saves account entries to ~/.config/git/accountList
#   - Offers to trigger SSH key setup (.ssh/setup.bash) directly
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Formatting Helpers
# -----------------------------------------------------------------------------
bold()   { printf '\033[1m%s\033[0m' "$*"; }
green()  { printf '\033[32m%s\033[0m' "$*"; }
yellow() { printf '\033[33m%s\033[0m' "$*"; }
red()    { printf '\033[31m%s\033[0m' "$*"; }
cyan()   { printf '\033[36m%s\033[0m' "$*"; }
info()   { echo "  $(green "»") $*"; }
warn()   { echo "  $(yellow "⚠") $*"; }
err()    { echo "  $(red "✗") $*" >&2; }
header() { echo; echo "$(bold "=== $* ===")"; echo; }

# -----------------------------------------------------------------------------
# Path Detection
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SCRIPT_DIR/../zsh" && -f "$SCRIPT_DIR/git-custom.zsh" ]]; then
    REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    REPO_DIR="$HOME/Shell-Setup"
fi

CONFIG_DIR="$HOME/.config/git"
ACCOUNT_LIST_FILE="$CONFIG_DIR/accountList"
REPO_ACCOUNT_LIST="$REPO_DIR/.config/git/accountList"
REPO_GIT_CUSTOM="$REPO_DIR/zsh/git-custom.zsh"
INSTALLED_GIT_CUSTOM="$HOME/.zsh/git-custom.zsh"

# In-memory arrays of accounts
usernames=()
emails=()
shortnames=()

# -----------------------------------------------------------------------------
# Load Accounts from File or Existing git-custom.zsh
# -----------------------------------------------------------------------------
load_accounts() {
    usernames=()
    emails=()
    shortnames=()

    local target_list=""
    if [[ -f "$ACCOUNT_LIST_FILE" ]]; then
        target_list="$ACCOUNT_LIST_FILE"
    elif [[ -f "$REPO_ACCOUNT_LIST" ]]; then
        target_list="$REPO_ACCOUNT_LIST"
    fi

    if [[ -n "$target_list" && -f "$target_list" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Trim whitespace
            line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            # Normalize possible pipe separator to colon
            line="$(echo "$line" | tr '|' ':')"
            local u="" e="" s=""
            IFS=":" read -r u e s _ <<< "$line"
            u="$(echo "$u" | xargs)"
            e="$(echo "$e" | xargs)"
            s="$(echo "$s" | xargs)"
            if [[ -n "$u" && -n "$e" && -n "$s" ]]; then
                usernames+=("$u")
                emails+=("$e")
                shortnames+=("$s")
            fi
        done < "$target_list"
    fi

    # Fallback to defaults if list was empty
    if [[ ${#usernames[@]} -eq 0 ]]; then
        usernames=("Work" "Personal")
        emails=("work@example.com" "personal@example.com")
        shortnames=("work" "personal")
    fi
}

# -----------------------------------------------------------------------------
# Save Accounts to accountList File
# -----------------------------------------------------------------------------
save_account_list() {
    mkdir -p "$CONFIG_DIR"
    {
        echo "# ============================================================================="
        echo "# Git Accounts Configuration List"
        echo "# Location: ~/.config/git/accountList"
        echo "# Managed by customizeGit.bash"
        echo "# Format: USERNAME:EMAIL:SHORTNAME"
        echo "# ============================================================================="
        echo
        for ((i = 0; i < ${#usernames[@]}; i++)); do
            echo "${usernames[i]}:${emails[i]}:${shortnames[i]}"
        done
    } > "$ACCOUNT_LIST_FILE"

    # Also sync to repository if inside Shell-Setup repo
    if [[ -d "$REPO_DIR" ]]; then
        mkdir -p "$REPO_DIR/.config/git" 2>/dev/null || true
        cp "$ACCOUNT_LIST_FILE" "$REPO_ACCOUNT_LIST" 2>/dev/null || true
    fi
    info "Saved account list to $(bold "$ACCOUNT_LIST_FILE")"
}

# -----------------------------------------------------------------------------
# Generate git-custom.zsh Content
# -----------------------------------------------------------------------------
generate_git_custom_zsh() {
    local tmp_file
    tmp_file="$(mktemp)"

    cat <<'BASE_EOF' > "$tmp_file"
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
BASE_EOF

    for ((i = 0; i < ${#usernames[@]}; i++)); do
        local u="${usernames[i]}"
        local e="${emails[i]}"
        local s="${shortnames[i]}"

        cat <<ACC_EOF >> "$tmp_file"

# ${s}_gConfig function
# Helper to configure local git repository to use ${u} account
${s}_gConfig() {
    echo "Configuring local git identity to ${u}"
    git config user.name "${u}"
    git config user.email "${e}"
    echo "Configured local git identity to ${u}"
}

# ${s}_vConfig function
# Helper to configure local git repository to use ${u} Signing Key via SSH
${s}_vConfig() {
    git config gpg.format ssh
    git config user.signingkey ~/.ssh/${u}_Signing.pub
    git config commit.gpgsign true
}

${s}GClone() {
    gClone ${u} ${s}_gConfig "\$@"
}
ACC_EOF
    done

    # Write to repository file if exists
    if [[ -d "$REPO_DIR/zsh" ]]; then
        cp "$tmp_file" "$REPO_GIT_CUSTOM"
        info "Updated $(bold "$REPO_GIT_CUSTOM")"
    fi

    # Write to installed ~/.zsh/git-custom.zsh if installed
    if [[ -d "$HOME/.zsh" ]]; then
        cp "$tmp_file" "$INSTALLED_GIT_CUSTOM"
        info "Updated $(bold "$INSTALLED_GIT_CUSTOM")"
    fi

    rm -f "$tmp_file"
}

# -----------------------------------------------------------------------------
# Display Current Accounts
# -----------------------------------------------------------------------------
display_accounts() {
    echo "$(bold "Configured Git Accounts (${#usernames[@]}):")"
    echo
    if [[ ${#usernames[@]} -eq 0 ]]; then
        echo "    $(yellow "(No accounts configured yet.)")"
        echo
        return 0
    fi

    for ((i = 0; i < ${#usernames[@]}; i++)); do
        local u="${usernames[i]}"
        local e="${emails[i]}"
        local s="${shortnames[i]}"
        printf "  %s %s\n" "$(bold "[$((i + 1))]")" "$(cyan "$u")"
        printf "      Email    : %s\n" "$e"
        printf "      Shortname: %s\n" "$(bold "$s")"
        printf "      Functions: %s, %s, %s\n" "$(green "${s}GClone")" "$(green "${s}_gConfig")" "$(green "${s}_vConfig")"
        echo
    done
}

# -----------------------------------------------------------------------------
# Add an Account
# -----------------------------------------------------------------------------
add_account() {
    header "Add New Git Account"

    local user="" email="" short=""

    read -r -p "  Enter Username (e.g. Work): " user
    while [[ -z "$user" ]]; do
        warn "Username cannot be empty."
        read -r -p "  Enter Username: " user
    done

    read -r -p "  Enter Email (e.g. user@example.com): " email
    while [[ -z "$email" ]]; do
        warn "Email cannot be empty."
        read -r -p "  Enter Email: " email
    done

    # Suggest shortname as lowercase initials or first 3-4 chars
    local default_short
    default_short="$(echo "$user" | tr '[:upper:]' '[:lower:]' | tr -dc '[:alnum:]' | head -c 4)"
    read -r -p "  Enter Shortname [default: $default_short]: " short
    short="${short:-$default_short}"
    short="$(echo "$short" | tr '[:upper:]' '[:lower:]' | tr -dc '[:alnum:]_')"
    while [[ -z "$short" ]]; do
        warn "Shortname cannot be empty."
        read -r -p "  Enter Shortname: " short
        short="$(echo "$short" | tr '[:upper:]' '[:lower:]' | tr -dc '[:alnum:]_')"
    done

    # Check for duplicate shortname or username
    for ((i = 0; i < ${#usernames[@]}; i++)); do
        if [[ "${usernames[i]}" == "$user" ]]; then
            warn "Account with username '$user' already exists. Updating existing entry."
            emails[i]="$email"
            shortnames[i]="$short"
            save_account_list
            generate_git_custom_zsh
            info "Account $(bold "$user") updated successfully!"
            return 0
        fi
        if [[ "${shortnames[i]}" == "$short" ]]; then
            warn "Shortname '$short' is already used by ${usernames[i]}."
            local overwrite=""
            read -r -p "  Overwrite? [y/N]: " overwrite
            if [[ "$overwrite" =~ ^[Yy] ]]; then
                usernames[i]="$user"
                emails[i]="$email"
                save_account_list
                generate_git_custom_zsh
                info "Account $(bold "$user") updated successfully!"
                return 0
            else
                info "Aborting addition."
                return 0
            fi
        fi
    done

    usernames+=("$user")
    emails+=("$email")
    shortnames+=("$short")

    save_account_list
    generate_git_custom_zsh
    info "$(green "Account $(bold "$user") ($short) added successfully!")"
}

# -----------------------------------------------------------------------------
# Edit an Account
# -----------------------------------------------------------------------------
edit_account() {
    header "Edit Git Account"

    if [[ ${#usernames[@]} -eq 0 ]]; then
        warn "No accounts available to edit."
        return 0
    fi

    display_accounts

    local idx=""
    read -r -p "  Enter account number to edit [1-${#usernames[@]}]: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || ((idx < 1 || idx > ${#usernames[@]})); then
        err "Invalid account number."
        return 0
    fi

    local i=$((idx - 1))
    local curr_user="${usernames[i]}"
    local curr_email="${emails[i]}"
    local curr_short="${shortnames[i]}"

    echo
    echo "  Editing $(bold "$curr_user"): (press Enter to keep current value)"

    local new_user="" new_email="" new_short=""
    read -r -p "  Username [$curr_user]: " new_user
    new_user="${new_user:-$curr_user}"

    read -r -p "  Email [$curr_email]: " new_email
    new_email="${new_email:-$curr_email}"

    read -r -p "  Shortname [$curr_short]: " new_short
    new_short="${new_short:-$curr_short}"
    new_short="$(echo "$new_short" | tr '[:upper:]' '[:lower:]' | tr -dc '[:alnum:]_')"

    usernames[i]="$new_user"
    emails[i]="$new_email"
    shortnames[i]="$new_short"

    save_account_list
    generate_git_custom_zsh
    info "$(green "Account #$idx updated to $(bold "$new_user") ($new_short)!")"
}

# -----------------------------------------------------------------------------
# Delete an Account
# -----------------------------------------------------------------------------
delete_account() {
    header "Delete Git Account"

    if [[ ${#usernames[@]} -eq 0 ]]; then
        warn "No accounts available to delete."
        return 0
    fi

    display_accounts

    local idx=""
    read -r -p "  Enter account number to delete [1-${#usernames[@]}]: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || ((idx < 1 || idx > ${#usernames[@]})); then
        err "Invalid account number."
        return 0
    fi

    local i=$((idx - 1))
    local target_user="${usernames[i]}"

    local confirm=""
    read -r -p "  Are you sure you want to delete $(bold "$target_user")? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy] ]]; then
        local new_users=()
        local new_emails=()
        local new_shorts=()
        for ((j = 0; j < ${#usernames[@]}; j++)); do
            if [[ $j -ne $i ]]; then
                new_users+=("${usernames[j]}")
                new_emails+=("${emails[j]}")
                new_shorts+=("${shortnames[j]}")
            fi
        done
        usernames=("${new_users[@]}")
        emails=("${new_emails[@]}")
        shortnames=("${new_shorts[@]}")

        save_account_list
        generate_git_custom_zsh
        info "$(green "Account $(bold "$target_user") deleted successfully.")"
    else
        info "Deletion cancelled."
    fi
}

# -----------------------------------------------------------------------------
# Prompt to Run SSH Setup
# -----------------------------------------------------------------------------
ask_ssh_setup() {
    echo
    local run_ssh=""
    read -r -p "  Would you like to configure/generate SSH keys for your accounts now? [Y/n]: " run_ssh
    if [[ -z "$run_ssh" || "$run_ssh" =~ ^[Yy] ]]; then
        local ssh_script=""
        if [[ -f "$HOME/.ssh/setup.bash" ]]; then
            ssh_script="$HOME/.ssh/setup.bash"
        elif [[ -f "$REPO_DIR/.ssh/setup.bash" ]]; then
            ssh_script="$REPO_DIR/.ssh/setup.bash"
        fi

        if [[ -n "$ssh_script" ]]; then
            info "Launching SSH Setup helper: $ssh_script..."
            bash "$ssh_script"
        else
            warn "Could not locate setup.bash. Run 'ssh-setup' once installed."
        fi
    else
        info "Skipping SSH setup. You can run it anytime with: $(bold "ssh-setup")"
    fi
}

# -----------------------------------------------------------------------------
# Main Interactive TUI Loop
# -----------------------------------------------------------------------------
main() {
    load_accounts

    while true; do
        header "Git Multi-Account Manager"
        display_accounts

        echo "$(bold "Actions:")"
        echo "  1) Add account"
        echo "  2) Edit account"
        echo "  3) Delete account"
        echo "  4) Save & Exit"
        echo "  q) Quit"
        echo

        local choice=""
        read -r -p "  Choose action [1-4/q]: " choice

        case "$choice" in
            1|[Aa]|[Aa][Dd][Dd])
                add_account
                ;;
            2|[Ee]|[Ee][Dd][Ii][Tt])
                edit_account
                ;;
            3|[Dd]|[Dd][Ee][Ll]*)
                delete_account
                ;;
            4|[Ss]|[Qq]|[Ee][Xx][Ii][Tt]|[Qq][Uu][Ii][Tt]|"")
                info "Finalizing configuration..."
                save_account_list
                generate_git_custom_zsh
                ask_ssh_setup
                echo
                info "$(green "All account updates completed!")"
                exit 0
                ;;
            *)
                warn "Invalid choice: '$choice'. Please choose 1, 2, 3, 4, or q."
                ;;
        esac
    done
}

main "$@"
