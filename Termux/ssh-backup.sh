#!/bin/sh
# Universal trampoline: ensure execution under bash on Termux and proot-distro.
#
# proot-distro can start a session with Termux's Android bash, which has the
# wrong linker/libraries for guest tooling. Prefer the container's own bash.
if [ -n "${PD_CONTAINER:-}" ] || [ "${container:-}" = "proot-distro" ]; then
    if [ -x /bin/bash ] && [ "${BASH:-}" != "/bin/bash" ] && [ "${BASH:-}" != "/usr/bin/bash" ]; then
        exec /bin/bash "$0" "$@"
    elif [ -x /usr/bin/bash ] && [ "${BASH:-}" != "/usr/bin/bash" ]; then
        exec /usr/bin/bash "$0" "$@"
    fi
fi

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
    unset POSIXLY_CORRECT

    if [ -n "${PREFIX:-}" ] && [ -x "$PREFIX/bin/bash" ]; then
        exec "$PREFIX/bin/bash" "$0" "$@"
    elif command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    elif [ -x /bin/bash ]; then
        exec /bin/bash "$0" "$@"
    else
        echo "Error: bash is required to run this script." >&2
        exit 1
    fi
fi
# =============================================================================
# Termux SSH Backup & Restore (Termux/ssh-backup.sh)
#
# Collects every ~/.ssh directory from:
#   - Termux native
#   - every installed proot-distro container (new and legacy layouts)
#
# and stores them as one passphrase-encrypted archive in Android shared storage:
#   <shared storage>/Termux-SSH-Backup/Termux-SSH-Backup.tar.gpg
#
# Encryption is GPG symmetric (AES-256). There is no key file: the passphrase
# alone protects the archive. Restore decrypts to a private temporary directory,
# copies the files back into each environment's ~/.ssh, and removes the backup
# from shared storage by default.
#
# WARNING: the archive contains private keys. GPG encryption protects it while
# it is in shared storage. Keep the passphrase strong and do not store it on the
# device. Delete the archive when it is no longer needed.
#
# Usage:
#   ./ssh-backup.sh                 Interactive menu
#   ./ssh-backup.sh --backup        Back up all detected ~/.ssh directories
#   ./ssh-backup.sh --restore       Restore all backups
#   ./ssh-backup.sh --status        Show detected sources and existing backups
#   ./ssh-backup.sh --keep          Keep the backup after a successful restore
#   ./ssh-backup.sh --dry-run ...   Show actions without writing files
#   ./ssh-backup.sh --yes ...       Skip confirmation prompts
#   ./ssh-backup.sh --help          Show this help message
# =============================================================================
set -o pipefail
umask 077

SCRIPT_NAME="ssh-backup.sh"
BACKUP_DIR_NAME="Termux-SSH-Backup"
BACKUP_ARCHIVE_NAME="Termux-SSH-Backup.tar.gpg"
SAFETY_DIR_NAME=".ssh-backup-safety"
TERMUX_HOME_DEFAULT="/data/data/com.termux/files/home"
TERMUX_PREFIX_DEFAULT="/data/data/com.termux/files/usr"

# -----------------------------------------------------------------------------
# Formatting Helpers
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[31m'; G=$'\033[32m'
    Y=$'\033[33m'; C=$'\033[36m'; N=$'\033[0m'
else
    B=""; DIM=""; R=""; G=""; Y=""; C=""; N=""
fi

bold()   { printf '%s%s%s' "$B" "$*" "$N"; }
green()  { printf '%s%s%s' "$G" "$*" "$N"; }
yellow() { printf '%s%s%s' "$Y" "$*" "$N"; }
red()    { printf '%s%s%s' "$R" "$*" "$N"; }
cyan()   { printf '%s%s%s' "$C" "$*" "$N"; }
info()   { echo "  $(green "»") $*"; }
warn()   { echo "  $(yellow "⚠") $*"; }
err()    { echo "  $(red "✗") $*" >&2; }
header() { echo; echo "$(bold "=== $* ===")"; echo; }

# -----------------------------------------------------------------------------
# Global State
# -----------------------------------------------------------------------------
IN_PROOT=0
IS_TERMUX=0
CURRENT_CONTAINER=""
ENV_LABEL="Termux native"
TERMUX_HOME_DIR=""
TERMUX_PREFIX_DIR=""
ANDROID_STORAGE=""
BACKUP_ROOT=""
BACKUP_ARCHIVE=""
ACTION=""
ASSUME_YES=0
DRY_RUN=0
KEEP_BACKUP=0
PASSPHRASE=""
TEMP_DIRS=()
TEMP_ARCHIVE=""

BACKUP_LABELS=()
BACKUP_SOURCES=()
BACKUP_RELS=()

RESTORE_LABELS=()
RESTORE_SOURCES=()
RESTORE_TARGETS=()
RESTORE_RELS=()

# -----------------------------------------------------------------------------
# Cleanup & Temporary Directories
# -----------------------------------------------------------------------------
cleanup_on_exit() {
    PASSPHRASE=""

    [[ -n "$TEMP_ARCHIVE" ]] && rm -f "$TEMP_ARCHIVE" 2>/dev/null || true
    TEMP_ARCHIVE=""

    local dir=""
    for dir in "${TEMP_DIRS[@]}"; do
        [[ -n "$dir" ]] && rm -rf "$dir" 2>/dev/null || true
    done
}

trap cleanup_on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

clear_passphrase() {
    PASSPHRASE=""
}

make_temp_dir() {
    local dir=""
    dir="$(mktemp -d "${TMPDIR:-/tmp}/termux-ssh-backup.XXXXXX")" || return 1
    chmod 700 "$dir" 2>/dev/null || true
    TEMP_DIRS+=("$dir")
    printf '%s\n' "$dir"
}

# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------
usage() {
    cat <<EOF
$(bold "$SCRIPT_NAME") — encrypted backup and restore of SSH keys between
Termux/proot-distro and Android shared storage.

Usage:
  $SCRIPT_NAME                    Interactive menu
  $SCRIPT_NAME --backup           Back up Termux and all proot-distro ~/.ssh dirs
  $SCRIPT_NAME --restore          Restore all backups into their environments
  $SCRIPT_NAME --status           Show detected sources and existing backups
  $SCRIPT_NAME --keep             Keep the backup after a successful restore
  $SCRIPT_NAME --dry-run          Preview actions without writing files
  $SCRIPT_NAME --yes              Skip confirmation prompts
  $SCRIPT_NAME --help             Show this help

Backup archive:
  <shared storage>/$BACKUP_DIR_NAME/$BACKUP_ARCHIVE_NAME

Encryption:
  GPG symmetric encryption with AES-256 and a passphrase. No key file is
  created or required. The passphrase is read with a hidden prompt and is
  never stored in the script, shell history, or a passphrase file.

  The passphrase is entered twice on backup and must be at least 12
  characters. Restore allows three attempts.

  If gpg is missing, gnupg is installed automatically:
    Termux native : pkg install -y gnupg
    proot-distro  : apt-get install -y gnupg

Archive layout:
  termux/.ssh
  proot-distro/<container>/root/.ssh
  proot-distro/<container>/home/<user>/.ssh

Restore cleanup:
  After a successful restore, the encrypted archive and the local
  pre-restore copies under ~/.ssh-backup-safety/ are removed by default.
  Use --keep (or --no-clean) to retain them. If any restore step fails,
  both are kept so the restore can be retried.

Android storage:
  In Termux native, missing storage access is requested with
  termux-setup-storage. Inside proot-distro, Termux's home and /sdcard are
  already bind-mounted by default. If they are unavailable, run
  termux-setup-storage from Termux and re-enter the container.
EOF
}

# -----------------------------------------------------------------------------
# Confirmation
# -----------------------------------------------------------------------------
confirm() {
    local prompt="$1" answer=""
    if [[ $ASSUME_YES -eq 1 ]]; then
        return 0
    fi
    read -r -p "  $prompt [y/N]: " answer || return 1
    [[ "$answer" =~ ^[Yy] ]]
}

# -----------------------------------------------------------------------------
# Passphrase Prompt
# -----------------------------------------------------------------------------
prompt_passphrase() {
    local mode="$1" first="" second=""

    echo "  The passphrase is not stored anywhere. Use at least 12 characters."

    while true; do
        if ! IFS= read -r -s -p "  Passphrase: " first; then
            echo
            return 1
        fi
        echo

        if [[ -z "$first" ]]; then
            warn "Passphrase cannot be empty."
            continue
        fi

        if (( ${#first} < 12 )); then
            warn "Passphrase must be at least 12 characters."
            continue
        fi

        if [[ "$mode" == "confirm" ]]; then
            if ! IFS= read -r -s -p "  Confirm passphrase: " second; then
                echo
                return 1
            fi
            echo

            if [[ "$first" != "$second" ]]; then
                warn "Passphrases do not match. Try again."
                continue
            fi
        fi

        PASSPHRASE="$first"
        return 0
    done
}

# -----------------------------------------------------------------------------
# Environment Detection
# -----------------------------------------------------------------------------
detect_environment() {
    CURRENT_CONTAINER="${PD_CONTAINER:-}"

    if [[ -n "${PD_CONTAINER:-}" || "${container:-}" == "proot-distro" ]]; then
        IN_PROOT=1
        IS_TERMUX=1
        CURRENT_CONTAINER="${CURRENT_CONTAINER:-unknown}"
        ENV_LABEL="proot-distro (${CURRENT_CONTAINER})"
    elif [[ -d /data/data/com.termux || -n "${TERMUX_VERSION:-}" ]]; then
        IN_PROOT=0
        IS_TERMUX=1
        ENV_LABEL="Termux native"
    else
        err "This script is for Termux / proot-distro on Android only."
        exit 1
    fi

    TERMUX_HOME_DIR=""
    if [[ -n "${TERMUX__HOME:-}" && -d "${TERMUX__HOME}" ]]; then
        TERMUX_HOME_DIR="$TERMUX__HOME"
    elif [[ $IN_PROOT -eq 0 && -n "${HOME:-}" && -d "${HOME}" ]]; then
        TERMUX_HOME_DIR="$HOME"
    elif [[ -d "$TERMUX_HOME_DEFAULT" ]]; then
        TERMUX_HOME_DIR="$TERMUX_HOME_DEFAULT"
    fi

    if [[ -z "$TERMUX_HOME_DIR" || ! -d "$TERMUX_HOME_DIR" ]]; then
        err "Could not locate the Termux home directory."
        if [[ $IN_PROOT -eq 1 ]]; then
            err "Re-enter proot-distro with the default bind mounts, or run this script from Termux native."
        fi
        exit 1
    fi

    if [[ -n "${TERMUX__PREFIX:-}" && -d "${TERMUX__PREFIX}" ]]; then
        TERMUX_PREFIX_DIR="$TERMUX__PREFIX"
    elif [[ -n "${PREFIX:-}" && "$PREFIX" == /data/data/com.termux/* && -d "$PREFIX" ]]; then
        TERMUX_PREFIX_DIR="$PREFIX"
    elif [[ -d "$TERMUX_PREFIX_DEFAULT" ]]; then
        TERMUX_PREFIX_DIR="$TERMUX_PREFIX_DEFAULT"
    else
        TERMUX_PREFIX_DIR="$TERMUX_PREFIX_DEFAULT"
    fi
}

# -----------------------------------------------------------------------------
# Android Storage Detection & termux-setup-storage
# -----------------------------------------------------------------------------
storage_writable() {
    local dir="$1" probe=""
    [[ -d "$dir" && -w "$dir" ]] || return 1

    probe="$dir/.ssh-backup-write-test.$$"
    if ( : > "$probe" ) 2>/dev/null; then
        rm -f "$probe" 2>/dev/null || true
        return 0
    fi
    return 1
}

ensure_android_storage() {
    local shared="$TERMUX_HOME_DIR/storage/shared"
    local i=""
    local candidates=()
    local candidate=""

    if [[ ! -d "$shared" && $IN_PROOT -eq 0 ]]; then
        if command -v termux-setup-storage >/dev/null 2>&1; then
            info "Android storage is not linked yet."
            info "Requesting storage access with termux-setup-storage..."
            termux-setup-storage >/dev/null 2>&1 || true

            for ((i = 0; i < 30; i++)); do
                [[ -d "$shared" ]] && break
                sleep 1
            done
        else
            warn "termux-setup-storage was not found on PATH."
        fi
    fi

    [[ -d "$shared" ]] && candidates+=("$shared")
    [[ -d /storage/emulated/0 ]] && candidates+=("/storage/emulated/0")
    [[ -d /sdcard ]] && candidates+=("/sdcard")

    for candidate in "${candidates[@]}"; do
        if storage_writable "$candidate"; then
            ANDROID_STORAGE="$candidate"
            break
        fi
    done

    if [[ -z "$ANDROID_STORAGE" ]]; then
        err "Android shared storage is not available or not writable."
        if [[ $IN_PROOT -eq 1 ]]; then
            err "Exit proot-distro, run 'termux-setup-storage' in Termux, then re-enter the container."
        else
            err "Run 'termux-setup-storage' in Termux, grant the permission, and try again."
        fi
        exit 1
    fi

    BACKUP_ROOT="$ANDROID_STORAGE/$BACKUP_DIR_NAME"
    BACKUP_ARCHIVE="$BACKUP_ROOT/$BACKUP_ARCHIVE_NAME"
}

# -----------------------------------------------------------------------------
# GPG Installation & Detection
# -----------------------------------------------------------------------------
install_gpg() {
    if [[ $IN_PROOT -eq 1 ]]; then
        if command -v apt-get >/dev/null 2>&1; then
            if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
                apt-get install -y gnupg || {
                    apt-get update && apt-get install -y gnupg
                }
            else
                sudo apt-get install -y gnupg || {
                    sudo apt-get update && sudo apt-get install -y gnupg
                }
            fi
            return $?
        fi
    else
        if command -v pkg >/dev/null 2>&1; then
            pkg install -y gnupg
            return $?
        elif [[ -x "$TERMUX_PREFIX_DIR/bin/pkg" ]]; then
            PATH="$TERMUX_PREFIX_DIR/bin:$PATH" \
                "$TERMUX_PREFIX_DIR/bin/pkg" install -y gnupg
            return $?
        fi
    fi

    return 1
}

ensure_gpg() {
    if command -v gpg >/dev/null 2>&1; then
        return 0
    fi

    warn "gpg was not found. Installing gnupg..."

    if ! install_gpg; then
        err "Could not install gnupg automatically."
        if [[ $IN_PROOT -eq 1 ]]; then
            err "Install it manually: apt-get install -y gnupg"
        else
            err "Install it manually: pkg install -y gnupg"
        fi
        return 1
    fi

    hash -r 2>/dev/null || true

    if ! command -v gpg >/dev/null 2>&1; then
        err "gnupg was installed but gpg is still not available on PATH."
        return 1
    fi

    info "Installed: $(gpg --version 2>/dev/null | head -n 1)"
    return 0
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
copy_tree() {
    local src="$1" dest="$2"

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[dry-run] copy ${src}/ → ${dest}/"
        return 0
    fi

    mkdir -p "$dest" || return 1
    cp -RL "$src/." "$dest/" || return 1
    return 0
}

count_files() {
    local dir="$1"
    find "$dir" -type f 2>/dev/null | wc -l | tr -d ' '
}

fix_ssh_permissions() {
    local dir="$1"
    [[ $DRY_RUN -eq 1 ]] && return 0

    chmod 700 "$dir" 2>/dev/null || true
    find "$dir" -type d -exec chmod 700 {} + 2>/dev/null || true
    find "$dir" -type f -exec chmod 600 {} + 2>/dev/null || true
    find "$dir" -type f -name '*.pub' -exec chmod 644 {} + 2>/dev/null || true
}

container_rootfs() {
    local name="$1" base=""

    for base in \
        "$TERMUX_PREFIX_DIR/var/lib/proot-distro/containers/$name/rootfs" \
        "$TERMUX_PREFIX_DIR/var/lib/proot-distro/installed-rootfs/$name" \
        "$TERMUX_PREFIX_DIR/var/lib/proot-distro/installed-rootfs/$name/rootfs"; do
        if [[ -d "$base" ]]; then
            printf '%s\n' "$base"
            return 0
        fi
    done

    return 1
}

# -----------------------------------------------------------------------------
# Backup Source Discovery
# -----------------------------------------------------------------------------
add_backup_source() {
    local label="$1" src="$2" rel="$3" existing=""

    [[ -d "$src" ]] || return 0

    for existing in "${BACKUP_RELS[@]}"; do
        [[ "$existing" == "$rel" ]] && return 0
    done

    BACKUP_LABELS+=("$label")
    BACKUP_SOURCES+=("$src")
    BACKUP_RELS+=("$rel")
}

add_proot_container_sources() {
    local name="$1" rootfs="$2" home_dir="" user=""

    if [[ -d "$rootfs/root/.ssh" ]]; then
        add_backup_source \
            "proot-distro/$name/root" \
            "$rootfs/root/.ssh" \
            "proot-distro/$name/root"
    fi

    for home_dir in "$rootfs"/home/*; do
        [[ -d "$home_dir/.ssh" ]] || continue
        user="$(basename "$home_dir")"
        add_backup_source \
            "proot-distro/$name/home/$user" \
            "$home_dir/.ssh" \
            "proot-distro/$name/home/$user"
    done
}

collect_backup_sources() {
    BACKUP_LABELS=()
    BACKUP_SOURCES=()
    BACKUP_RELS=()

    add_backup_source "termux" "$TERMUX_HOME_DIR/.ssh" "termux"

    local dir="" name="" rootfs=""

    for dir in "$TERMUX_PREFIX_DIR"/var/lib/proot-distro/containers/*; do
        [[ -d "$dir/rootfs" ]] || continue
        name="$(basename "$dir")"
        add_proot_container_sources "$name" "$dir/rootfs"
    done

    for dir in "$TERMUX_PREFIX_DIR"/var/lib/proot-distro/installed-rootfs/*; do
        [[ -d "$dir" ]] || continue
        name="$(basename "$dir")"
        rootfs="$dir"

        # Some legacy installs nest the rootfs one level deeper.
        if [[ ! -d "$rootfs/root" && -d "$rootfs/rootfs" ]]; then
            rootfs="$rootfs/rootfs"
        fi

        [[ -d "$rootfs" ]] && add_proot_container_sources "$name" "$rootfs"
    done

    # Fallback for a custom/older proot layout: use the current guest home.
    if [[ $IN_PROOT -eq 1 && -n "$CURRENT_CONTAINER" && -d "$HOME/.ssh" ]]; then
        add_backup_source \
            "proot-distro/$CURRENT_CONTAINER (current)" \
            "$HOME/.ssh" \
            "proot-distro/$CURRENT_CONTAINER/${HOME#/}"
    fi
}

# -----------------------------------------------------------------------------
# Encryption & Decryption
# -----------------------------------------------------------------------------
write_manifest() {
    local dir="$1"
    local manifest="$dir/manifest.txt"
    local i=""

    {
        echo "# Termux SSH Backup"
        echo "# Created: $(date '+%Y-%m-%d %H:%M:%S %z')"
        if [[ $IN_PROOT -eq 1 ]]; then
            echo "# Run from: proot-distro container ${CURRENT_CONTAINER}"
        else
            echo "# Run from: Termux native"
        fi
        echo "# Encryption: GPG symmetric, AES-256"
        echo "#"
        echo "# Entries (relative to archive root):"
        for i in "${!BACKUP_RELS[@]}"; do
            echo "${BACKUP_RELS[i]}/.ssh <- ${BACKUP_SOURCES[i]}"
        done
    } > "$manifest" 2>/dev/null || warn "Could not write $manifest"
}

gpg_encrypt_stage() {
    local stage="$1" archive="$2"
    local tmp="$archive.tmp.$$"
    local entries=()

    [[ -d "$stage/termux" ]] && entries+=("termux")
    [[ -d "$stage/proot-distro" ]] && entries+=("proot-distro")
    [[ -f "$stage/manifest.txt" ]] && entries+=("manifest.txt")

    if [[ ${#entries[@]} -eq 0 ]]; then
        err "Nothing to archive."
        return 1
    fi

    rm -f "$tmp"
    TEMP_ARCHIVE="$tmp"

    if ! tar -cf - -C "$stage" "${entries[@]}" |
        gpg --batch --yes --no-tty --quiet \
            --pinentry-mode loopback \
            --passphrase-fd 3 \
            --no-symkey-cache \
            --symmetric \
            --cipher-algo AES256 \
            --s2k-digest-algo SHA512 \
            --s2k-count 65011712 \
            --compress-algo zlib \
            --no-emit-version \
            --output "$tmp" \
            3< <(printf '%s\n' "$PASSPHRASE"); then
        rm -f "$tmp"
        TEMP_ARCHIVE=""
        return 1
    fi

    chmod 600 "$tmp" 2>/dev/null || true

    if ! mv -f "$tmp" "$archive"; then
        rm -f "$tmp"
        TEMP_ARCHIVE=""
        return 1
    fi

    TEMP_ARCHIVE=""
    return 0
}

gpg_decrypt_archive() {
    local archive="$1" stage="$2"

    gpg --batch --yes --no-tty --quiet \
        --pinentry-mode loopback \
        --passphrase-fd 3 \
        --no-symkey-cache \
        --decrypt "$archive" \
        3< <(printf '%s\n' "$PASSPHRASE") |
        tar -xf - -C "$stage" --no-same-owner
}

# -----------------------------------------------------------------------------
# Backup
# -----------------------------------------------------------------------------
do_backup() {
    collect_backup_sources

    header "Backup SSH Files (Encrypted)"

    if [[ ${#BACKUP_SOURCES[@]} -eq 0 ]]; then
        warn "No ~/.ssh directories were found in Termux or proot-distro."
        return 0
    fi

    echo "  Archive: $(bold "$BACKUP_ARCHIVE")"
    echo
    echo "  Sources:"

    local i="" total=0 dest="" files="" stage=""
    for i in "${!BACKUP_SOURCES[@]}"; do
        printf "    %s %s\n" "$(cyan "${BACKUP_LABELS[i]}")" "${DIM}→${N} ${BACKUP_RELS[i]}/.ssh"
        printf "      %s\n" "${BACKUP_SOURCES[i]}"
    done
    echo

    if ! command -v gpg >/dev/null 2>&1; then
        warn "gpg is not installed; a real backup will install gnupg."
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[dry-run] create GPG-encrypted archive: $BACKUP_ARCHIVE"
        info "Dry run complete; no files were written."
        return 0
    fi

    if ! confirm "Create the encrypted backup archive now?"; then
        info "Backup cancelled."
        return 0
    fi

    if ! ensure_gpg; then
        return 1
    fi

    if ! prompt_passphrase confirm; then
        info "Backup cancelled."
        return 0
    fi

    if ! mkdir -p "$BACKUP_ROOT"; then
        err "Could not create $BACKUP_ROOT"
        clear_passphrase
        return 1
    fi

    stage="$(make_temp_dir)" || {
        err "Could not create a temporary directory."
        clear_passphrase
        return 1
    }

    info "Staging SSH files in a private temporary directory..."

    for i in "${!BACKUP_SOURCES[@]}"; do
        dest="$stage/${BACKUP_RELS[i]}/.ssh"
        info "Adding ${BACKUP_LABELS[i]}..."

        if copy_tree "${BACKUP_SOURCES[i]}" "$dest"; then
            files="$(count_files "$dest")"
            total=$((total + files))
            info "Staged ${files} file(s)."
        else
            err "Failed to stage ${BACKUP_LABELS[i]}."
            clear_passphrase
            return 1
        fi
    done

    write_manifest "$stage"

    info "Encrypting archive with GPG (AES-256)..."

    if ! gpg_encrypt_stage "$stage" "$BACKUP_ARCHIVE"; then
        err "Encryption failed; the existing backup was not changed."
        clear_passphrase
        return 1
    fi

    clear_passphrase
    rm -rf "$stage" 2>/dev/null || true

    echo
    info "$(green "Backup complete.")"
    info "Files encrypted: $(bold "$total")"
    info "Archive: $(bold "$BACKUP_ARCHIVE")"
    info "Keep the passphrase safe; it cannot be recovered."

    return 0
}

# -----------------------------------------------------------------------------
# Restore Action Discovery
# -----------------------------------------------------------------------------
add_restore_action() {
    local label="$1" src="$2" target="$3" rel="$4" existing=""

    [[ -d "$src" ]] || return 0

    for existing in "${RESTORE_TARGETS[@]}"; do
        [[ "$existing" == "$target" ]] && return 0
    done

    RESTORE_LABELS+=("$label")
    RESTORE_SOURCES+=("$src")
    RESTORE_TARGETS+=("$target")
    RESTORE_RELS+=("$rel")
}

collect_restore_actions() {
    local stage="$1"
    local cdir="" name="" rootfs="" home_dir="" user="" rel="" target=""

    RESTORE_LABELS=()
    RESTORE_SOURCES=()
    RESTORE_TARGETS=()
    RESTORE_RELS=()

    if [[ -d "$stage/termux/.ssh" ]]; then
        add_restore_action \
            "termux" \
            "$stage/termux/.ssh" \
            "$TERMUX_HOME_DIR/.ssh" \
            "termux"
    fi

    for cdir in "$stage"/proot-distro/*; do
        [[ -d "$cdir" ]] || continue
        name="$(basename "$cdir")"
        rootfs="$(container_rootfs "$name" 2>/dev/null || true)"

        if [[ -d "$cdir/root/.ssh" ]]; then
            if [[ -n "$rootfs" ]]; then
                target="$rootfs/root/.ssh"
            elif [[ $IN_PROOT -eq 1 && "$name" == "$CURRENT_CONTAINER" && "${HOME#/}" == "root" ]]; then
                target="$HOME/.ssh"
            else
                warn "Skipping proot-distro/$name/root: container not found."
                target=""
            fi

            [[ -n "$target" ]] && add_restore_action \
                "proot-distro/$name/root" \
                "$cdir/root/.ssh" \
                "$target" \
                "proot-distro/$name/root"
        fi

        for home_dir in "$cdir"/home/*; do
            [[ -d "$home_dir/.ssh" ]] || continue
            user="$(basename "$home_dir")"
            rel="home/$user"

            if [[ -n "$rootfs" ]]; then
                target="$rootfs/$rel/.ssh"
            elif [[ $IN_PROOT -eq 1 && "$name" == "$CURRENT_CONTAINER" && "${HOME#/}" == "$rel" ]]; then
                target="$HOME/.ssh"
            else
                warn "Skipping proot-distro/$name/$rel: container not found."
                target=""
            fi

            [[ -n "$target" ]] && add_restore_action \
                "proot-distro/$name/$rel" \
                "$home_dir/.ssh" \
                "$target" \
                "proot-distro/$name/$rel"
        done
    done
}

# -----------------------------------------------------------------------------
# Restore
# -----------------------------------------------------------------------------
do_restore() {
    if [[ ! -f "$BACKUP_ARCHIVE" ]]; then
        warn "No encrypted backup found at $BACKUP_ARCHIVE"

        if [[ -d "$BACKUP_ROOT/termux" || -d "$BACKUP_ROOT/proot-distro" ]]; then
            warn "A legacy plaintext backup was found. Re-run --backup to create the encrypted archive, then remove the old files."
        fi
        return 0
    fi

    header "Restore SSH Files (Encrypted)"

    echo "  Archive: $(bold "$BACKUP_ARCHIVE")"
    echo

    if ! ensure_gpg; then
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        info "Dry run: passphrase is still required to inspect the archive."
    fi

    local stage="" attempts=0
    while true; do
        if ! prompt_passphrase no; then
            info "Restore cancelled."
            return 0
        fi

        stage="$(make_temp_dir)" || {
            err "Could not create a temporary directory."
            clear_passphrase
            return 1
        }

        if gpg_decrypt_archive "$BACKUP_ARCHIVE" "$stage"; then
            break
        fi

        warn "Decryption failed: wrong passphrase or damaged archive."
        rm -rf "$stage" 2>/dev/null || true
        clear_passphrase

        attempts=$((attempts + 1))
        if (( attempts >= 3 )); then
            err "Too many failed attempts. The archive was not changed."
            return 1
        fi
    done

    clear_passphrase
    fix_ssh_permissions "$stage"

    collect_restore_actions "$stage"

    if [[ ${#RESTORE_SOURCES[@]} -eq 0 ]]; then
        warn "No restorable .ssh directories were found in the archive."
        rm -rf "$stage" 2>/dev/null || true
        return 0
    fi

    echo "  Restore plan:"

    local i=""
    for i in "${!RESTORE_SOURCES[@]}"; do
        printf "    %s\n" "$(cyan "${RESTORE_LABELS[i]}")"
        printf "      %s %s\n" "${RESTORE_SOURCES[i]}" "${DIM}→${N} ${RESTORE_TARGETS[i]}"
    done
    echo

    local confirm_prompt="Restore these files? Same-name files in each ~/.ssh will be overwritten."
    if [[ $KEEP_BACKUP -eq 0 ]]; then
        confirm_prompt+=" The encrypted archive will then be removed from shared storage."
    fi

    if [[ $DRY_RUN -eq 0 ]] && ! confirm "$confirm_prompt"; then
        info "Restore cancelled."
        rm -rf "$stage" 2>/dev/null || true
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        info "Dry run complete; no target files were written."
        rm -rf "$stage" 2>/dev/null || true
        return 0
    fi

    local safety_root="$TERMUX_HOME_DIR/$SAFETY_DIR_NAME/$(date '+%Y%m%d-%H%M%S')-$$"
    local safety_created=0
    local failed=0 target="" files=""

    for i in "${!RESTORE_SOURCES[@]}"; do
        target="${RESTORE_TARGETS[i]}"
        info "Restoring ${RESTORE_LABELS[i]}..."

        if [[ -d "$target" ]]; then
            info "Saving current files to ${safety_root}/${RESTORE_RELS[i]}/.ssh"
            if copy_tree "$target" "$safety_root/${RESTORE_RELS[i]}/.ssh"; then
                safety_created=1
            else
                warn "Could not save a safety copy of $target"
            fi
        fi

        if copy_tree "${RESTORE_SOURCES[i]}" "$target"; then
            fix_ssh_permissions "$target"
            files="$(count_files "$target")"
            info "Restored ${files} file(s)."
        else
            err "Failed to restore ${RESTORE_LABELS[i]}."
            failed=1
        fi
    done

    rm -rf "$stage" 2>/dev/null || true

    echo
    if [[ $failed -ne 0 ]]; then
        err "Restore finished with errors."
        info "Encrypted archive kept for retry: $(bold "$BACKUP_ARCHIVE")"
        [[ $safety_created -eq 1 ]] && info "Pre-restore copies: $(bold "$safety_root")"
        return 1
    fi

    info "$(green "Restore complete.")"

    if [[ $KEEP_BACKUP -eq 1 ]]; then
        info "Encrypted archive kept: $(bold "$BACKUP_ARCHIVE")"
        [[ $safety_created -eq 1 ]] && info "Pre-restore copies: $(bold "$safety_root")"
        return 0
    fi

    info "Removing encrypted archive from shared storage..."
    if rm -f "$BACKUP_ARCHIVE"; then
        rmdir "$BACKUP_ROOT" 2>/dev/null || true
        info "Archive removed: $(bold "$BACKUP_ARCHIVE")"
    else
        warn "Restore succeeded, but the archive could not be removed from $BACKUP_ARCHIVE"
    fi

    [[ $safety_created -eq 1 ]] && rm -rf "$safety_root" 2>/dev/null || true

    return 0
}

# -----------------------------------------------------------------------------
# Status
# -----------------------------------------------------------------------------
show_status() {
    header "SSH Backup Status"

    echo "  Environment  : $(cyan "$ENV_LABEL")"
    echo "  Termux home  : $TERMUX_HOME_DIR"
    echo "  Termux prefix: $TERMUX_PREFIX_DIR"
    echo "  Storage      : $ANDROID_STORAGE"
    echo "  Archive      : $(bold "$BACKUP_ARCHIVE")"

    if command -v gpg >/dev/null 2>&1; then
        echo "  GPG          : $(gpg --version 2>/dev/null | head -n 1)"
    else
        echo "  GPG          : $(yellow "not installed (installed automatically when needed)")"
    fi
    echo

    collect_backup_sources

    echo "  Detected SSH sources:"
    if [[ ${#BACKUP_SOURCES[@]} -eq 0 ]]; then
        echo "    (none)"
    else
        local i=""
        for i in "${!BACKUP_SOURCES[@]}"; do
            printf "    %s  %s\n" "$(cyan "${BACKUP_LABELS[i]}")" "${BACKUP_SOURCES[i]}"
        done
    fi
    echo

    echo "  Encrypted backup:"
    if [[ -f "$BACKUP_ARCHIVE" ]]; then
        local size=""
        size="$(du -h "$BACKUP_ARCHIVE" 2>/dev/null | awk 'NR==1 {print $1}')"
        printf "    %s%s\n" "${BACKUP_ARCHIVE#$BACKUP_ROOT/}" "${size:+ (${size})}"
    else
        echo "    (none)"
    fi

    if [[ -d "$BACKUP_ROOT/termux" || -d "$BACKUP_ROOT/proot-distro" ]]; then
        echo
        warn "Legacy plaintext backup data exists under $BACKUP_ROOT"
        warn "It is not used by this encrypted version. Remove it after verifying your encrypted backup."
    fi
}

# -----------------------------------------------------------------------------
# Interactive Menu
# -----------------------------------------------------------------------------
interactive_menu() {
    while true; do
        header "Termux SSH Backup"

        echo "  Environment: $(cyan "$ENV_LABEL")"
        echo "  Archive    : $(bold "$BACKUP_ARCHIVE")"
        echo
        echo "  1) Back up SSH files → encrypted Android storage"
        echo "  2) Restore SSH files ← encrypted storage (cleanup after success)"
        echo "  3) Show backup status"
        echo "  4) Exit"
        echo

        local choice=""
        read -r -p "  Choose [1-4]: " choice || return 0

        case "$choice" in
            1|[Bb]|[Bb][Aa][Cc][Kk][Uu][Pp])
                do_backup
                ;;
            2|[Rr]|[Rr][Ee][Ss][Tt][Oo][Rr][Ee])
                do_restore
                ;;
            3|[Ss]|[Ss][Tt][Aa][Tt][Uu][Ss])
                show_status
                ;;
            4|[Qq]|[Ee][Xx][Ii][Tt]|"")
                info "Exiting."
                return 0
                ;;
            *)
                warn "Invalid choice: '$choice'"
                ;;
        esac

        echo
        read -r -p "  Press Enter to return to the menu..." _ || return 0
    done
}

# -----------------------------------------------------------------------------
# Argument Parsing & Main
# -----------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--backup)
                ACTION="backup"
                ;;
            -r|--restore)
                ACTION="restore"
                ;;
            -s|--status|--list)
                ACTION="status"
                ;;
            -y|--yes)
                ASSUME_YES=1
                ;;
            -k|--keep|--no-clean)
                KEEP_BACKUP=1
                ;;
            -n|--dry-run)
                DRY_RUN=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                err "Unknown option: $1"
                echo
                usage
                exit 1
                ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"
    detect_environment
    ensure_android_storage

    case "$ACTION" in
        backup)
            do_backup
            ;;
        restore)
            do_restore
            ;;
        status)
            show_status
            ;;
        "")
            interactive_menu
            ;;
    esac
}

main "$@"
