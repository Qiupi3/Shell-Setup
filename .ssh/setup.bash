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

# In proot-distro the Termux prefix is bind-mounted into the guest. Prefer the
# guest's own binaries: Termux's ssh resolves ~/.ssh through Android's home
# (/data/data/com.termux/files/home), not $HOME, so it cannot see keys written
# by this script.
if [[ -n "${PD_CONTAINER:-}" || "${container:-}" == "proot-distro" ]]; then
    _guest_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    if [[ -d /data/data/com.termux/files/usr/bin ]]; then
        export PATH="$_guest_path:/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/sbin"
    else
        export PATH="$_guest_path"
    fi
    unset _guest_path
fi

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
        local auth_fp=""
        auth_fp="$(ssh-keygen -lf "$auth_key.pub" 2>/dev/null | awk '{print $2}' || true)"
        [[ -n "$auth_fp" ]] && info "Fingerprint: $(bold "$auth_fp")"

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
        local sign_fp=""
        sign_fp="$(ssh-keygen -lf "$sign_key.pub" 2>/dev/null | awk '{print $2}' || true)"
        [[ -n "$sign_fp" ]] && info "Fingerprint: $(bold "$sign_fp")"

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
    if [[ -n "$auth_key" ]]; then
        local verify_host="github.com-$user"
        [[ "$user" == "id_ed25519" ]] && verify_host="github.com"
        echo
        info "After adding the key on GitHub, verify with: $(bold "ssh -T git@$verify_host")"
    fi
    echo
    info "$(green "Completed SSH setup for $user!")"
}

# -----------------------------------------------------------------------------
# Existing Key Audit
#
# Scans ~/.ssh for private keys and reports whether each one is reachable from
# ~/.ssh/config (IdentityFile), ~/.config/git/accountList, or allowed_signers.
# Unmapped keys can be mapped without regenerating them.
# -----------------------------------------------------------------------------
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local hint=" [y/N] "
    [[ "$default" == "y" ]] && hint=" [Y/n] "

    local answer
    if ! read -r -p "${prompt}${hint}" answer; then
        echo
        return 1
    fi
    if [[ -z "$answer" ]]; then
        [[ "$default" == "y" ]]
        return
    fi
    [[ "$answer" =~ ^[Yy] ]]
}

is_private_key() {
    local f="$1"
    [[ -f "$f" ]] || return 1
    [[ "$f" == *.pub ]] && return 1
    head -n1 "$f" 2>/dev/null | grep -q 'PRIVATE KEY'
}

# Print the public key line for a private key: prefer the .pub sidecar, fall
# back to deriving it in memory. Never writes a missing .pub file.
key_pub_content() {
    local key="$1"
    if [[ -f "$key.pub" ]]; then
        cat "$key.pub"
    else
        ssh-keygen -y -P "" -f "$key" 2>/dev/null
    fi
}

key_fingerprint() {
    local content="$1" tmp fp
    tmp="$(mktemp)"
    printf '%s\n' "$content" > "$tmp"
    fp="$(ssh-keygen -lf "$tmp" 2>/dev/null | awk '{print $2}')"
    rm -f "$tmp"
    printf '%s' "${fp:-unknown}"
}

key_in_ssh_config() {
    local key="$1"
    local cfg="$HOME/.ssh/config"
    local base
    base="$(basename "$key")"
    [[ -f "$cfg" ]] || return 1
    grep -qiE "^[[:space:]]*IdentityFile[[:space:]]+.*(/|~/)${base}([[:space:]]|$)" "$cfg" 2>/dev/null
}

key_in_account_list() {
    local key="$1" u
    local base
    base="$(basename "$key")"
    for u in "${list_users[@]}"; do
        [[ "$base" == "$u" || "$base" == "${u}_Signing" ]] && return 0
    done
    return 1
}

key_in_allowed_signers() {
    local content="$1"
    local file="$HOME/.config/git/allowed_signers"
    local data
    data="$(printf '%s\n' "$content" | awk '{print $2}')"
    [[ -n "$data" && -f "$file" ]] || return 1
    grep -qF "$data" "$file" 2>/dev/null
}

# Append USER:EMAIL:SHORT to ~/.config/git/accountList once.
add_account_entry() {
    local user="$1" email="$2" short="$3"
    local file="$HOME/.config/git/accountList"

    mkdir -p "$(dirname "$file")"
    touch "$file"

    if grep -qE "^[[:space:]]*${user}:" "$file" 2>/dev/null; then
        info "Account $(bold "$user") already exists in $(bold "$file")"
        return 0
    fi
    if [[ ! -s "$file" ]]; then
        cat > "$file" <<'EOF'
# Git Accounts Configuration List
# Format: USERNAME:EMAIL:SHORTNAME
EOF
    fi
    echo "${user}:${email}:${short}" >> "$file"
    info "Added $(bold "$user") to $(bold "$file")"
}

# Add "Host github.com-<user>" to ~/.ssh/config once.
add_ssh_host() {
    local user="$1" key="$2"
    local cfg="$HOME/.ssh/config"
    local alias="github.com-$user"

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    touch "$cfg"
    chmod 600 "$cfg"

    if grep -qE "^[[:space:]]*Host[[:space:]]+${alias}[[:space:]]*$" "$cfg" 2>/dev/null; then
        local existing
        existing="$(awk -v a="$alias" '
            $1 == "Host" && $2 == a { found = 1; next }
            found && $1 == "IdentityFile" { print $2; exit }
            found && $1 == "Host" { exit }
        ' "$cfg" 2>/dev/null)"
        if [[ -n "$existing" && "$existing" != "$key" && "${existing#\~}" != "${key#$HOME}" ]]; then
            warn "Host $(bold "$alias") already exists and points to $(bold "$existing")."
            warn "Not changing it; edit ~/.ssh/config manually if that is wrong."
        else
            info "Host $(bold "$alias") already exists in ~/.ssh/config"
        fi
        return 0
    fi

    cat >> "$cfg" <<EOF

# Custom SSH Host for $user
Host $alias
    HostName github.com
    User git
    IdentityFile $key
    IdentitiesOnly yes
EOF
    info "Added $(bold "$alias") → $(bold "$key")"
}

# Add a signing key to allowed_signers once.
add_allowed_signer() {
    local email="$1" content="$2"
    local file="$HOME/.config/git/allowed_signers"
    local key_type_and_data

    mkdir -p "$(dirname "$file")"
    touch "$file"

    key_type_and_data="$(printf '%s\n' "$content" | awk '{print $1, $2}')"
    if grep -qF "$key_type_and_data" "$file" 2>/dev/null; then
        info "Signing key already present in $(bold "$file")"
        return 0
    fi
    echo "$email $key_type_and_data" >> "$file"
    info "Added signing key for $(bold "$email") to $(bold "$file")"

    git config --global gpg.format ssh 2>/dev/null || true
    git config --global commit.gpgsign true 2>/dev/null || true
    git config --global gpg.ssh.allowedSignersFile "$file" 2>/dev/null || true
}

map_unmapped_key() {
    local key="$1"
    local content
    content="$(key_pub_content "$key" 2>/dev/null || true)"
    if [[ -z "$content" ]]; then
        warn "Cannot read the public part of $(basename "$key") (passphrase-protected and no .pub)."
        warn "Add ${key}.pub manually or regenerate the key."
        return 0
    fi

    header "Map key: $(basename "$key")"
    echo "  1) Authentication key for a Git account"
    echo "  2) Commit signing key"
    echo "  3) Skip this key"
    echo

    local choice
    read -r -p "  Choose [1/2/3, default 3]: " choice
    choice="${choice:-3}"

    case "$choice" in
        1)
            local account email short
            if [[ ${#list_users[@]} -gt 0 ]]; then
                echo "  Existing accounts:"
                local i
                for ((i = 0; i < ${#list_users[@]}; i++)); do
                    echo "    $((i + 1))) ${list_users[i]} <${list_emails[i]}>"
                done
                echo "    n) New account"
                echo
                local pick
                read -r -p "  Map to [1-${#list_users[@]}/n]: " pick
                if [[ "$pick" =~ ^[0-9]+$ ]] && ((pick >= 1 && pick <= ${#list_users[@]})); then
                    account="${list_users[$((pick - 1))]}"
                    email="${list_emails[$((pick - 1))]}"
                    short="${list_shorts[$((pick - 1))]}"
                fi
            fi

            if [[ -z "${account:-}" ]]; then
                read -r -p "  Account username (e.g. Work): " account
                while [[ -z "$account" ]]; do
                    warn "Username cannot be empty."
                    read -r -p "  Account username: " account
                done
                read -r -p "  Email for $account: " email
                read -r -p "  Shortname for wrappers [default: ${account,,}]: " short
                short="${short:-${account,,}}"
                add_account_entry "$account" "$email" "$short"
                list_users+=("$account")
                list_emails+=("$email")
                list_shorts+=("$short")
            fi

            add_ssh_host "$account" "$key"
            info "Authentication key mapped to account $(bold "$account")."
            ;;
        2)
            local email default_email
            default_email="$(git config --get user.email 2>/dev/null || echo "")"
            read -r -p "  Email/principal for signing${default_email:+ [$default_email]}: " email
            email="${email:-$default_email}"
            while [[ -z "$email" ]]; do
                warn "Email cannot be empty for allowed_signers."
                read -r -p "  Email/principal for signing: " email
            done
            add_allowed_signer "$email" "$content"
            ;;
        *)
            info "Skipped $(basename "$key")."
            ;;
    esac
}

audit_ssh_keys() {
    header "Existing SSH Key Audit"

    local ssh_dir="$HOME/.ssh"
    local -a key_paths=()
    local f
    [[ -d "$ssh_dir" ]] || return 0

    while IFS= read -r f; do
        is_private_key "$f" && key_paths+=("$f")
    done < <(find "$ssh_dir" -maxdepth 1 -type f ! -name '*.pub' -print 2>/dev/null | sort)

    if [[ ${#key_paths[@]} -eq 0 ]]; then
        info "No private keys found in $ssh_dir"
        return 0
    fi

    echo "  $(bold "KEY")                          $(bold "FINGERPRINT")                 $(bold "STATUS")"
    echo

    local -a orphan_keys=()
    local k content fp missing sign_note
    for k in "${key_paths[@]}"; do
        content="$(key_pub_content "$k" 2>/dev/null || true)"
        if [[ -n "$content" ]]; then
            fp="$(key_fingerprint "$content")"
        else
            fp="(no public key)"
        fi

        # "Unmapped" means the key is not tied to a host or a Git account.
        # Not being in allowed_signers is only informational: auth-only keys
        # are perfectly valid.
        missing=()
        key_in_ssh_config "$k"   || missing+=("host")
        key_in_account_list "$k" || missing+=("account")

        sign_note=""
        if [[ -n "$content" ]] && ! key_in_allowed_signers "$content"; then
            sign_note=" (not a signer)"
        fi

        if [[ ${#missing[@]} -eq 0 ]]; then
            printf "  %-30s %-30s %s%s\n" "$(basename "$k")" "$fp" "$(green "mapped")" "$sign_note"
        else
            orphan_keys+=("$k")
            printf "  %-30s %-30s %s%s\n" "$(basename "$k")" "$fp" "$(yellow "unmapped: ${missing[*]}")" "$sign_note"
        fi
    done

    echo
    if [[ ${#orphan_keys[@]} -eq 0 ]]; then
        info "All private keys are mapped."
        return 0
    fi

    warn "${#orphan_keys[@]} key(s) are not fully mapped."
    if ! ask_yes_no "  Map an unmapped key now?" n; then
        info "Skipped key mapping. You can map later with customizeGit.bash / setup.bash."
        return 0
    fi

    local sel
    if [[ ${#orphan_keys[@]} -eq 1 ]]; then
        map_unmapped_key "${orphan_keys[0]}"
        return 0
    fi

    echo
    local i
    for ((i = 0; i < ${#orphan_keys[@]}; i++)); do
        echo "    $((i + 1))) $(basename "${orphan_keys[$i]}")"
    done
    echo "    a) Map all unmapped keys one by one"
    echo
    read -r -p "  Choose: " sel

    if [[ "$sel" == [aA] ]]; then
        for k in "${orphan_keys[@]}"; do
            map_unmapped_key "$k"
        done
    elif [[ "$sel" =~ ^[0-9]+$ ]] && ((sel >= 1 && sel <= ${#orphan_keys[@]})); then
        map_unmapped_key "${orphan_keys[$((sel - 1))]}"
    else
        warn "Invalid selection; nothing mapped."
    fi
}

# -----------------------------------------------------------------------------
# Refresh generated account wrappers
#
# setup.bash may add an account (when mapping an existing key) or create new
# keys. Regenerate ~/.zsh/git-custom.zsh so the account list and wrapper
# functions stay in sync without asking the user to open the manager again.
# -----------------------------------------------------------------------------
sync_git_custom() {
    local customizer="$HOME/.zsh/customizeGit.bash"
    [[ -f "$customizer" ]] || return 0

    SHELL_SETUP_NO_SSH_PROMPT=1 bash "$customizer" --sync >/dev/null 2>&1 || true
}

# -----------------------------------------------------------------------------
# Main Setup Flow
# -----------------------------------------------------------------------------
main() {
    header "SSH Key & Git Signing Setup"

    # A Termux ssh client inside proot reads the Android home instead of
    # $HOME, so keys created below would be invisible to Git. Stop with an
    # actionable message rather than generating unusable keys.
    local ssh_client
    ssh_client="$(command -v ssh 2>/dev/null || true)"
    if [[ ( -n "${PD_CONTAINER:-}" || "${container:-}" == "proot-distro" ) \
        && "$ssh_client" == /data/data/com.termux/* ]]; then
        err "This proot guest is using Termux's ssh ($ssh_client)."
        err "That client reads /data/data/com.termux/files/home/.ssh, not $HOME/.ssh."
        info "Install the guest OpenSSH client first:"
        info "  apt-get update && apt-get install -y openssh-client"
        info "Then re-run: $(bold "bash ~/.ssh/setup.bash")"
        return 1
    fi

    local ssh_dir="$HOME/.ssh"
    if [[ ! -d "$ssh_dir" ]]; then
        info "Creating ~/.ssh directory..."
        mkdir -p "$ssh_dir"
    fi
    chmod 700 "$ssh_dir"

    load_account_list
    audit_ssh_keys

    local selected_users=()
    local selected_emails=()

    if [[ ${#list_users[@]} -eq 1 ]]; then
        # One account is the common case after the Option 3 account step.
        # Don't make the user pick "1" from a one-item menu.
        selected_users=("${list_users[0]}")
        selected_emails=("${list_emails[0]}")
        local only_user="${list_users[0]}"
        local only_auth="$(yellow "[Auth: None]")"
        local only_sign="$(yellow "[Sign: None]")"
        local only_host=""
        [[ -f "$ssh_dir/$only_user" ]] && only_auth="$(green "[Auth: Found]")"
        [[ -f "$ssh_dir/${only_user}_Signing" ]] && only_sign="$(green "[Sign: Found]")"
        grep -q "Host github.com-$only_user" "$ssh_dir/config" 2>/dev/null \
            && only_host="$(green "[SSH Host: Added]")"
        echo "$(bold "Git Account:") $(cyan "$only_user") <${list_emails[0]}>"
        printf "      Status: %s  %s  %s\n" "$only_auth" "$only_sign" "$only_host"
        echo
    elif [[ ${#list_users[@]} -gt 1 ]]; then
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

    sync_git_custom

    echo
    info "$(green "All SSH setups finished successfully!")"
}

main "$@"
