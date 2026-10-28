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
set -eo pipefail

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
#
# Rule: user data is written ONLY under $HOME. The repository is read-only and
# used purely as a source of templates. This keeps a git clone clean and avoids
# one user's accounts leaking into the repo (and then into the next user).
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate the repository copy (may be absent when only ~/.zsh was installed).
REPO_DIR=""
if [[ -f "$SCRIPT_DIR/customizeGit.bash" && -d "$SCRIPT_DIR/../.config" ]]; then
    REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

TEMPLATE_ACCOUNT_LIST=""
if [[ -n "$REPO_DIR" && -f "$REPO_DIR/.config/git/accountList" ]]; then
    TEMPLATE_ACCOUNT_LIST="$REPO_DIR/.config/git/accountList"
fi

CONFIG_DIR="$HOME/.config/git"
ACCOUNT_LIST_FILE="$CONFIG_DIR/accountList"
INSTALLED_GIT_CUSTOM="$HOME/.zsh/git-custom.zsh"
INSTALLED_GIT_FUNCTIONS="$HOME/.zsh/git-functions.zsh"

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
    elif [[ -n "$TEMPLATE_ACCOUNT_LIST" && -f "$TEMPLATE_ACCOUNT_LIST" ]]; then
        # Repo template is read-only; used only when no user list exists yet.
        target_list="$TEMPLATE_ACCOUNT_LIST"
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
            s="${s:-$(echo "$u" | tr '[:upper:]' '[:lower:]')}"
            if [[ -n "$u" && -n "$e" ]]; then
                usernames+=("$u")
                emails+=("$e")
                shortnames+=("$s")
            fi
        done < "$target_list"
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

    info "Saved account list to $(bold "$ACCOUNT_LIST_FILE")"
}

# -----------------------------------------------------------------------------
# Generate git-custom.zsh Content
# -----------------------------------------------------------------------------
generate_git_custom_zsh() {
    local tmp_file
    tmp_file="$(mktemp)"

    cat <<'BASE_EOF' > "$tmp_file"
# ============================================================
# Account Specific Git Configurations & Clone Wrappers
# Generated locally by customizeGit.bash — DO NOT edit by hand.
#
# Generic helpers (EQLINE, reset_vConfig, gClone) live in
# ~/.zsh/git-functions.zsh, installed by the Shell module.
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
    local _sign_key=""
    local _candidate
    for _candidate in \\
        "\$HOME/.ssh/${u}_Signing.pub" \\
        "\$HOME/.ssh/${u}.pub" \\
        "\$HOME/.ssh/id_ed25519.pub"; do
        if [[ -f "\$_candidate" ]]; then
            _sign_key="\$_candidate"
            break
        fi
    done

    if [[ -z "\$_sign_key" ]]; then
        echo "No SSH signing key found for ${u}." >&2
        echo "Run 'ssh-setup' to create one." >&2
        return 1
    fi

    git config gpg.format ssh
    git config user.signingkey "\$_sign_key"
    git config commit.gpgsign true
    echo "Configured ${u} commit signing with \$_sign_key"
}

${s}GClone() {
    gClone "${u}" "${s}_gConfig" "\$@"
}
ACC_EOF
    done

    # User data goes to $HOME only — never back into the repository clone.
    mkdir -p "$HOME/.zsh"

    # Make sure the generic helpers are present even when the Shell module
    # (Option 1) was not run.
    if [[ ! -f "$INSTALLED_GIT_FUNCTIONS" ]]; then
        if [[ -n "$REPO_DIR" && -f "$REPO_DIR/zsh/git-functions.zsh" ]]; then
            cp "$REPO_DIR/zsh/git-functions.zsh" "$INSTALLED_GIT_FUNCTIONS"
            info "Installed $(bold "$INSTALLED_GIT_FUNCTIONS")"
        else
            warn "git-functions.zsh not found; run the Shell module to install it."
        fi
    fi

    cp "$tmp_file" "$INSTALLED_GIT_CUSTOM"
    info "Updated $(bold "$INSTALLED_GIT_CUSTOM")"

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

    if [[ ${#usernames[@]} -eq 0 ]]; then
        info "No Git accounts configured yet."
        echo
        add_account
        load_accounts
    fi

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
                if [[ "${SHELL_SETUP_NO_SSH_PROMPT:-0}" != "1" ]]; then
                    ask_ssh_setup
                fi
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

# Non-interactive entry point used by setup.bash / the installer when an
# account is added outside this menu and the generated wrappers need to be
# refreshed without opening the TUI.
case "${1:-}" in
    --sync|--generate)
        load_accounts
        generate_git_custom_zsh
        exit 0
        ;;
esac

main "$@"
