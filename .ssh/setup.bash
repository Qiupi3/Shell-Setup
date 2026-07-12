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
# SSH Key Setup & Git Commit Signing Configuration
# Location: ~/.ssh/setup.bash (sourced / copied from repository .ssh/setup.bash)
#
# Generates Ed25519 SSH keys for GitHub authentication and/or Git commit signing.
# Automatically sets up:
#   - ~/.ssh directory with correct permissions
#   - Account detection from ~/.config/git/accountList (single, selective, or all)
#   - 4 Key Types:
#       1) Authentication key only
#       2) Commit signing key only
#       3) Both as one (unified key)
#       4) Generate both keys (separate Auth and Signing keys)
#   - Proper key separation:
#       * Auth key: ~/.ssh/<Username>, added to ~/.ssh/config host
#       * Signing key: ~/.ssh/<Username>_Signing, added to allowed_signers
#   - Public key formatting and clipboard helper for GitHub
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
# Clipboard Helper
# -----------------------------------------------------------------------------
copy_to_clipboard() {
    local text="$1"
    if command -v termux-clipboard-set &>/dev/null; then
        printf '%s' "$text" | termux-clipboard-set 2>/dev/null && return 0
    elif command -v pbcopy &>/dev/null; then
        printf '%s' "$text" | pbcopy 2>/dev/null && return 0
    elif command -v wl-copy &>/dev/null; then
        printf '%s' "$text" | wl-copy 2>/dev/null && return 0
    elif command -v xclip &>/dev/null; then
        printf '%s' "$text" | xclip -selection clipboard 2>/dev/null && return 0
    elif command -v xsel &>/dev/null; then
        printf '%s' "$text" | xsel --clipboard --input 2>/dev/null && return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Load Account List (~/.config/git/accountList)
# -----------------------------------------------------------------------------
list_users=()
list_emails=()
list_shorts=()

load_account_list() {
    list_users=()
    list_emails=()
    list_shorts=()

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local repo_dir
    repo_dir="$(cd "$script_dir/.." 2>/dev/null && pwd || echo "$HOME/Shell-Setup")"

    local candidate_file=""
    if [[ -f "$HOME/.config/git/accountList" ]]; then
        candidate_file="$HOME/.config/git/accountList"
    elif [[ -f "$repo_dir/.config/git/accountList" ]]; then
        candidate_file="$repo_dir/.config/git/accountList"
    fi

    if [[ -n "$candidate_file" && -f "$candidate_file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            line="$(echo "$line" | tr '|' ':')"
            local u="" e="" s=""
            IFS=":" read -r u e s _ <<< "$line"
            u="$(echo "$u" | xargs)"
            e="$(echo "$e" | xargs)"
            s="$(echo "$s" | xargs)"
            if [[ -n "$u" && -n "$e" ]]; then
                list_users+=("$u")
                list_emails+=("$e")
                list_shorts+=("${s:-$u}")
            fi
        done < "$candidate_file"
    fi
}

# -----------------------------------------------------------------------------
# Setup SSH Keys for a Single Account
# -----------------------------------------------------------------------------
setup_single_account() {
    local user="$1"
    local email="$2"
    local ssh_dir="$HOME/.ssh"

    header "SSH Setup for Account: $user ($email)"

    # Ask the 4 questions about which key to create
    echo "  What type of SSH key would you like to create for $(bold "$user")?"
    echo "    1) Authentication key only   — for GitHub SSH access (clone / push) [Default]"
    echo "    2) Commit signing key only   — for Git commit signing"
    echo "    3) Both as one (unified)     — ONE key for both authentication and commit signing"
    echo "    4) Generate both keys        — TWO separate keys ($user for Auth, ${user}_Signing for Signing)"
    echo
    local mode_choice=""
    read -r -p "  Choose [1/2/3/4, default 1]: " mode_choice
    mode_choice="${mode_choice:-1}"
    case "$mode_choice" in
        2|[Ss]|[Ss][Ii][Gg][Nn]*)
            mode_choice="2"
            ;;
        3|[Oo]|[Oo][Nn][Ee]*|[Uu]*)
            mode_choice="3"
            ;;
        4|[Bb]|[Bb][Oo][Tt][Hh]*)
            mode_choice="4"
            ;;
        1|[Aa]|[Aa][Uu][Tt][Hh]*|*)
            mode_choice="1"
            ;;
    esac

    local auth_key=""
    local sign_key=""
    local sign_name="$user"
    if [[ "$sign_name" != *_Signing ]]; then
        sign_name="${sign_name}_Signing"
    fi

    case "$mode_choice" in
        1)
            # Auth key only
            auth_key="$ssh_dir/$user"
            info "Authentication key will be: $(bold "$auth_key")"
            ;;
        2)
            # Sign key only
            sign_key="$ssh_dir/$sign_name"
            info "Signing key will be:        $(bold "$sign_key")"
            ;;
        3)
            # Both as one (unified)
            auth_key="$ssh_dir/$user"
            sign_key="$auth_key"
            info "Unified key will be:        $(bold "$auth_key")"
            ;;
        4)
            # Generate both keys (separate)
            auth_key="$ssh_dir/$user"
            sign_key="$ssh_dir/$sign_name"
            info "Authentication key will be: $(bold "$auth_key")"
            info "Signing key will be:        $(bold "$sign_key")"
            ;;
    esac

    # -------------------------------------------------------------------------
    # Generate Authentication Key (Modes 1, 3, 4)
    # -------------------------------------------------------------------------
    local auth_passphrase=""
    if [[ -n "$auth_key" ]]; then
        header "Generating Authentication Key ($user)"
        local gen_auth=1
        if [[ -f "$auth_key" ]]; then
            warn "Key file already exists at $auth_key"
            local overwrite=""
            read -r -p "  Overwrite existing key? [y/N]: " overwrite
            if [[ "$overwrite" =~ ^[Yy] ]]; then
                rm -f "$auth_key" "$auth_key.pub"
            else
                info "Keeping existing key: $auth_key"
                gen_auth=0
            fi
        fi

        if [[ $gen_auth -eq 1 ]]; then
            local passphrase_confirm=""
            while true; do
                read -s -r -p "  Enter passphrase for auth key (empty for no passphrase): " auth_passphrase
                echo
                if [[ -z "$auth_passphrase" ]]; then
                    break
                fi
                read -s -r -p "  Confirm passphrase: " passphrase_confirm
                echo
                if [[ "$auth_passphrase" == "$passphrase_confirm" ]]; then
                    break
                else
                    warn "Passphrases did not match. Please try again."
                fi
            done
            ssh-keygen -t ed25519 -C "$email" -f "$auth_key" -N "$auth_passphrase"
        fi
        chmod 600 "$auth_key"
        chmod 644 "$auth_key.pub"
    fi

    # -------------------------------------------------------------------------
    # Generate Signing Key (Modes 2, 4)
    # -------------------------------------------------------------------------
    if [[ -n "$sign_key" && "$sign_key" != "$auth_key" ]]; then
        header "Generating Commit Signing Key ($sign_name)"
        local gen_sign=1
        if [[ -f "$sign_key" ]]; then
            warn "Key file already exists at $sign_key"
            local overwrite_sign=""
            read -r -p "  Overwrite existing signing key? [y/N]: " overwrite_sign
            if [[ "$overwrite_sign" =~ ^[Yy] ]]; then
                rm -f "$sign_key" "$sign_key.pub"
            else
                info "Keeping existing signing key: $sign_key"
                gen_sign=0
            fi
        fi

        if [[ $gen_sign -eq 1 ]]; then
            local sign_passphrase="$auth_passphrase"
            local ask_sign_pass=1
            if [[ -n "$auth_passphrase" && -n "$auth_key" ]]; then
                local same_pass=""
                read -r -p "  Use the same passphrase for signing key? [Y/n]: " same_pass
                if [[ ! "$same_pass" =~ ^[Nn] ]]; then
                    ask_sign_pass=0
                fi
            fi

            if [[ $ask_sign_pass -eq 1 ]]; then
                while true; do
                    read -s -r -p "  Enter passphrase for signing key (empty for no passphrase): " sign_passphrase
                    echo
                    if [[ -z "$sign_passphrase" ]]; then
                        break
                    fi
                    local sign_confirm=""
                    read -s -r -p "  Confirm signing passphrase: " sign_confirm
                    echo
                    if [[ "$sign_passphrase" == "$sign_confirm" ]]; then
                        break
                    else
                        warn "Passphrases did not match. Please try again."
                    fi
                done
            fi
            ssh-keygen -t ed25519 -C "$email (Signing)" -f "$sign_key" -N "$sign_passphrase"
        fi
        chmod 600 "$sign_key"
        chmod 644 "$sign_key.pub"
    fi

    # -------------------------------------------------------------------------
    # Handle ~/.ssh/config Host (Auth key only)
    # -------------------------------------------------------------------------
    if [[ -n "$auth_key" ]]; then
        local ssh_config_file="$ssh_dir/config"
        touch "$ssh_config_file"
        chmod 600 "$ssh_config_file"

        if [[ "$user" != "id_ed25519" ]]; then
            header "Configuring SSH Host in ~/.ssh/config"
            local host_alias="github.com-$user"
            if ! grep -q "Host $host_alias" "$ssh_config_file" 2>/dev/null; then
                info "Adding Host $host_alias to ~/.ssh/config..."
                cat <<EOF >> "$ssh_config_file"

# Custom SSH Host for $user
Host $host_alias
    HostName github.com
    User git
    IdentityFile $auth_key
EOF
                info "Added $(bold "$host_alias") with IdentityFile $(bold "$auth_key") to ~/.ssh/config"
            else
                info "Host $(bold "$host_alias") already exists in ~/.ssh/config"
            fi
        else
            info "Default key id_ed25519 is used automatically by OpenSSH; skipping ~/.ssh/config host entry."
        fi
    fi

    # -------------------------------------------------------------------------
    # Handle ~/.config/git/allowed_signers (Signing key only)
    # Note: Do NOT configure ~/.gitconfig with user.signingkey!
    # -------------------------------------------------------------------------
    if [[ ("$mode_choice" == "2" || "$mode_choice" == "3" || "$mode_choice" == "4") && -f "$sign_key.pub" ]]; then
        header "Configuring Git Allowed Signers"
        local git_config_dir="$HOME/.config/git"
        local allowed_signers="$git_config_dir/allowed_signers"

        mkdir -p "$git_config_dir"
        touch "$allowed_signers"

        local sign_pub_content
        sign_pub_content="$(cat "$sign_key.pub")"
        local key_type_and_data
        key_type_and_data="$(echo "$sign_pub_content" | awk '{print $1, $2}')"

        if grep -qF "$key_type_and_data" "$allowed_signers" 2>/dev/null; then
            info "Signing key already present in $(bold "$allowed_signers")"
        else
            echo "$email $key_type_and_data" >> "$allowed_signers"
            info "Added signing key for $(bold "$email") to $(bold "$allowed_signers")"
        fi

        # Ensure Git knows how to verify SSH signatures with allowed_signers
        git config --global gpg.format ssh 2>/dev/null || true
        git config --global commit.gpgsign true 2>/dev/null || true
        git config --global gpg.ssh.allowedSignersFile "$allowed_signers" 2>/dev/null || true
        info "Git verification reference configured in ~/.gitconfig (allowedSignersFile)."
        info "Note: Global user.signingkey is untouched; use ${list_shorts[0]:-acc}_vConfig per repository."
    fi

    # -------------------------------------------------------------------------
    # Output and Copy Public Keys for GitHub
    # -------------------------------------------------------------------------
    header "GitHub Public Keys ($user)"

    # Output Authentication Key
    if [[ -n "$auth_key" && -f "$auth_key.pub" ]]; then
        local auth_pub
        auth_pub="$(cat "$auth_key.pub")"
        echo
        echo "$(bold "----------------------------------------------------------------------")"
        if [[ "$mode_choice" == "3" ]]; then
            echo "$(cyan "Unified Public Key") (Use on GitHub as $(bold "Authentication Key") AND $(bold "Signing Key"))"
        else
            echo "$(cyan "Authentication Public Key") (Key type on GitHub: $(bold "Authentication Key"))"
        fi
        echo "File: $(bold "$auth_key.pub")"
        echo "$(bold "----------------------------------------------------------------------")"
        echo "$auth_pub"
        echo "$(bold "----------------------------------------------------------------------")"

        if copy_to_clipboard "$auth_pub"; then
            info "$(green "Copied public key to clipboard!")"
        else
            info "Tip: Copy the public key string above to clipboard."
        fi
    fi

    # Output Signing Key
    if [[ ("$mode_choice" == "2" || "$mode_choice" == "4") && -f "$sign_key.pub" ]]; then
        local sign_pub
        sign_pub="$(cat "$sign_key.pub")"
        echo
        echo "$(bold "----------------------------------------------------------------------")"
        echo "$(cyan "Commit Signing Public Key") (Key type on GitHub: $(bold "Signing Key"))"
        echo "File: $(bold "$sign_key.pub")"
        echo "$(bold "----------------------------------------------------------------------")"
        echo "$sign_pub"
        echo "$(bold "----------------------------------------------------------------------")"

        local copy_sign="y"
        if [[ -n "$auth_key" ]]; then
            read -r -p "  Copy Signing key to clipboard now? [Y/n]: " copy_sign
        fi
        if [[ -z "$copy_sign" || "$copy_sign" =~ ^[Yy] ]]; then
            if copy_to_clipboard "$sign_pub"; then
                info "$(green "Copied Signing public key to clipboard!")"
            else
                info "Tip: Copy the signing key string above manually."
            fi
        fi
    fi

    echo
    echo "$(bold "GitHub Instructions for $user:")"
    echo "  1. Open GitHub → Settings → SSH and GPG keys"
    echo "  2. Click 'New SSH key'"
    if [[ "$mode_choice" == "1" ]]; then
        echo "  3. Paste key and choose Key type: 'Authentication Key'"
    elif [[ "$mode_choice" == "2" ]]; then
        echo "  3. Paste key and choose Key type: 'Signing Key'"
    elif [[ "$mode_choice" == "3" ]]; then
        echo "  3. Paste key and choose 'Authentication Key'"
        echo "  4. (Optional) Add again with Key type: 'Signing Key' for verified badges"
    else
        echo "  3. Add Authentication key ($auth_key.pub) as 'Authentication Key'"
        echo "  4. Add Signing key ($sign_key.pub) as 'Signing Key'"
    fi
    echo
    info "$(green "Completed SSH setup for $user!")"
}

# -----------------------------------------------------------------------------
# Main Setup Flow
# -----------------------------------------------------------------------------
main() {
    header "SSH Key & Git Signing Setup"

    local ssh_dir="$HOME/.ssh"
    if [[ ! -d "$ssh_dir" ]]; then
        info "Creating ~/.ssh directory..."
        mkdir -p "$ssh_dir"
    fi
    chmod 700 "$ssh_dir"

    load_account_list

    local selected_users=()
    local selected_emails=()

    if [[ ${#list_users[@]} -gt 0 ]]; then
        echo "$(bold "Discovered Git Accounts in ~/.config/git/accountList:")"
        echo
        for ((i = 0; i < ${#list_users[@]}; i++)); do
            local u="${list_users[i]}"
            local e="${list_emails[i]}"
            local auth_f="$ssh_dir/$u"
            local sign_f="$ssh_dir/${u}_Signing"

            local auth_stat="$(yellow "[Auth: None]")"
            [[ -f "$auth_f" ]] && auth_stat="$(green "[Auth: Found]")"

            local sign_stat="$(yellow "[Sign: None]")"
            [[ -f "$sign_f" ]] && sign_stat="$(green "[Sign: Found]")"

            local host_stat=""
            if grep -q "Host github.com-$u" "$ssh_dir/config" 2>/dev/null; then
                host_stat="$(green "[SSH Host: Added]")"
            fi

            printf "  %s %s <%s>\n" "$(bold "[$((i + 1))]")" "$(cyan "$u")" "$e"
            printf "      Status: %s  %s  %s\n" "$auth_stat" "$sign_stat" "$host_stat"
            echo
        done

        echo "$(bold "Setup Options:")"
        echo "  1-${#list_users[@]}) Select a specific account from the list"
        echo "  a)    Setup ALL accounts in sequence"
        echo "  s)    Selective accounts (choose multiple, e.g. 1, 2)"
        echo "  m)    Manual input (custom username & email not in list)"
        echo "  q)    Quit directly"
        echo
        local acc_choice=""
        read -r -p "  Choose [1-${#list_users[@]}/a/s/m/q, default 1]: " acc_choice
        acc_choice="${acc_choice:-1}"

        case "$acc_choice" in
            [Qq]|[Qq][Uu][Ii][Tt]|[Ee][Xx][Ii][Tt])
                info "Exiting SSH setup."
                exit 0
                ;;
            [Aa]|[Aa][Ll][Ll])
                selected_users=("${list_users[@]}")
                selected_emails=("${list_emails[@]}")
                ;;
            [Ss]|[Ss][Ee][Ll]*)
                local sel_input=""
                read -r -p "  Enter account numbers to setup (e.g. 1, 2): " sel_input
                sel_input="$(echo "$sel_input" | tr ',' ' ')"
                for num in $sel_input; do
                    if [[ "$num" =~ ^[0-9]+$ ]] && ((num >= 1 && num <= ${#list_users[@]})); then
                        local idx=$((num - 1))
                        selected_users+=("${list_users[idx]}")
                        selected_emails+=("${list_emails[idx]}")
                    fi
                done
                if [[ ${#selected_users[@]} -eq 0 ]]; then
                    warn "No valid accounts selected; using account #1."
                    selected_users=("${list_users[0]}")
                    selected_emails=("${list_emails[0]}")
                fi
                ;;
            [Mm]|[Mm][Aa][Nn]*)
                # Manual entry below
                ;;
            *)
                if [[ "$acc_choice" =~ ^[0-9]+$ ]] && ((acc_choice >= 1 && acc_choice <= ${#list_users[@]})); then
                    local idx=$((acc_choice - 1))
                    selected_users=("${list_users[idx]}")
                    selected_emails=("${list_emails[idx]}")
                else
                    warn "Unrecognized selection; defaulting to account #1."
                    selected_users=("${list_users[0]}")
                    selected_emails=("${list_emails[0]}")
                fi
                ;;
        esac
    fi

    # If manual input chosen or no accounts configured in list
    if [[ ${#selected_users[@]} -eq 0 ]]; then
        header "Manual Key Configuration"

        local default_email
        default_email="$(git config --get user.email 2>/dev/null || echo "")"
        local email_prompt="  Enter email for SSH key"
        if [[ -n "$default_email" ]]; then
            email_prompt="$email_prompt [default: $default_email]: "
        else
            email_prompt="$email_prompt: "
        fi

        local email=""
        read -r -p "$email_prompt" email
        email="${email:-$default_email}"
        while [[ -z "$email" ]]; do
            warn "Email cannot be empty."
            read -r -p "  Enter email: " email
        done

        local default_key="id_ed25519"
        local user=""
        read -r -p "  Enter username or key-pair name [default: $default_key]: " user
        user="${user:-$default_key}"

        selected_users=("$user")
        selected_emails=("$email")
    fi

    for ((k = 0; k < ${#selected_users[@]}; k++)); do
        setup_single_account "${selected_users[k]}" "${selected_emails[k]}"
    done

    echo
    info "$(green "All SSH setups finished successfully!")"
}

main "$@"
