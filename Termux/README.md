# Termux Shell Setup & Migration Guide

This guide walks you through updating your system, installing **Zsh**, applying the modular configuration, installing useful plugins, and setting Zsh as your default shell on Termux (Android).

## Prerequisites

- `git`

---

# 1. Update Your System

Before installing new packages, update your package lists and upgrade all installed packages.

```bash
pkg update && pkg upgrade -y
```

---

# 2. Install Zsh

Install the Zsh shell using the package manager:

```bash
pkg install zsh
```

---

# 3. Apply Your Zsh Configuration & Modules

Run the automated installer script from the repository root:

```bash
cd ~/Shell-Setup/
./install.sh
```

This automates:
- Copying the slim, modular `.zshrc` into `~/.zshrc`
- Copying modular config files from root `zsh/` (`aliases.zsh`, `git-aliases.zsh`, `git-functions.zsh`, `prompt.zsh`) to `~/.zsh/`
- Copying Termux base shortcuts (`Termux/base.sh`) to `~/.zsh/base.zsh`
- Installing `zsh-syntax-highlighting` into `~/.zsh/plugins/` (if not already present)
- Copying Termux terminal settings and styling from `Termux/.termux/` to `~/.termux/`
- Installing the Neovim configuration from `.config/nvim/` to `~/.config/nvim/` **only when Option 2 is selected**
- Setting up global Git configurations (`~/.gitconfig` & `~/.config/git/allowed_signers`) and SSH files **only when Option 3 is selected**
- Installing a choosable Ubuntu/Debian proot-distro and running Option 1 inside it **when Option 4 is selected**

---

# 4. Storage Usage Inspection & Cleanup

Termux includes a dedicated storage analysis and cache cleanup utility in `Termux/clean-up.sh`:

### Storage Inspection Aliases
- `hdu`: Home directory usage (`~`)
- `pdu`: Termux Prefix / System storage usage (`$PREFIX`)
- `sdu`: Android Shared Storage / SDCard usage (`/sdcard`)
- `cdu`: User Cache Directory usage (`~/.cache`)
- `apdu`: APT / PKG downloaded package archive usage
- `tdu`: Temporary directory usage (`$PREFIX/tmp`)
- `gdu`, `ndu`, `pldu`: Gradle, NPM, and Pip cache usage

### Smart Cleanup & Package Analyzer
Run `./clean-up.sh` to launch the interactive main menu:
- **Smart Cache & Temp Cleanup**: TUI checklist editor for runtime temporary files, user caches, NPM, Pip, Cargo, Go, and gallery thumbnails.
- **Package & Project Usage Analyzer**:
  - Scans installed Debian/Termux packages, sizes, dependencies, and reverse dependencies.
  - Prompts for directory to scan for projects (defaults to user home '~').
  - Correlates packages with detected project directories (PHP, Node.js, Python, Rust, Go, Java, etc.).
  - Identifies in-use and unused packages.
  - Supports **Full Cleanup**: Removes project folder AND uninstalls associated package bundle.
  - **Git Status & Unsaved Changes Detection**: Detects uncommitted changes and unpushed commits before deletion to prevent accidental data loss.
- **Strict Confirmation**: Shows the exact path to be cleared and asks for confirmation for every delete.
- CLI options:
  - `./clean-up.sh --cache` : Launch cache TUI editor directly.
  - `./clean-up.sh --packages` (or `--pkg`) : Launch package & project analyzer directly.
  - `./clean-up.sh --scan` : Preview cleanable sizes without deleting.
  - `./clean-up.sh --dry-run` : Simulate actions without modifying files.
  - `./clean-up.sh --all` : Clean all detected cache targets (with per-item confirmation).

---

# 5. SSH Backup & Restore

`Termux/ssh-backup.sh` backs up every `~/.ssh` directory from Termux native and all installed proot-distro containers, encrypts the archive with GPG, and writes it to Android shared storage. Restore decrypts the archive and copies each environment's files back into its own `~/.ssh`.

From the repository checkout:

```bash
chmod +x Termux/ssh-backup.sh
./Termux/ssh-backup.sh
```

Non-interactive usage:

```bash
./Termux/ssh-backup.sh --backup           # back up all detected ~/.ssh directories
./Termux/ssh-backup.sh --restore          # restore, then remove the archive from shared storage
./Termux/ssh-backup.sh --restore --keep   # restore and keep the archive for another run
./Termux/ssh-backup.sh --status           # show detected sources and the existing archive
./Termux/ssh-backup.sh --backup --dry-run # preview without writing anything
./Termux/ssh-backup.sh --restore --yes    # skip confirmation prompts
```

## Encryption

The backup is a single passphrase-encrypted file:

```text
$HOME/storage/shared/Termux-SSH-Backup/
└── Termux-SSH-Backup.tar.gpg
```

- **GPG symmetric encryption only** — no keypair, key file, or passphrase file is created.
- **AES-256**, SHA-512 key derivation with 65,011,712 S2K iterations, zlib compression, and MDC integrity protection.
- The passphrase is read with a hidden prompt (`read -s`), passed to GPG through file descriptor 3, and never written to disk, command-line arguments, or shell history.
- On backup the passphrase must be at least 12 characters and entered twice; restore allows three attempts.
- If `gpg` is missing, the script installs `gnupg` automatically (`pkg install -y gnupg` in Termux, `apt-get install -y gnupg` in proot-distro).

The decrypted archive contains the per-environment layout:

```text
termux/.ssh/
proot-distro/<container>/root/.ssh/
proot-distro/<container>/home/<user>/.ssh/
manifest.txt
```

## Restore behavior

- Runs `termux-setup-storage` automatically when Android storage access is missing in Termux native.
- Uses the Termux home and `/sdcard` bind mounts when run inside proot-distro.
- Detects both the current proot-distro layout (`containers/<name>/rootfs`) and the legacy `installed-rootfs/<name>` layout.
- Decrypts into a private temporary directory, then copies files into each target `~/.ssh`.
- Saves pre-restore copies locally under `~/.ssh-backup-safety/<timestamp>-<pid>/` (never in shared storage), and resets permissions (`700` for directories, `600` for private files, `644` for `*.pub`).
- Removes the encrypted archive and local safety copies after a successful restore by default. Use `--keep` (or `--no-clean`) to retain them. If restore fails, both are kept for retry.

> Android shared storage is readable by apps with storage permission. The GPG archive protects private keys while it is stored there, but the passphrase is the only thing standing between that file and your keys. Use a strong passphrase, never store it on the device, and remove the archive when it is no longer needed.

> Older releases created a plaintext backup directory (`termux/`, `proot-distro/`). `--status` warns if that layout is present; re-run `--backup` to create an encrypted archive, then delete the old plaintext files.

---

# 6. Change Your Default Shell

Set Zsh as your default login shell:

```bash
chsh -s zsh
```

---

# 7. Load the New Configuration

You do **not** need to close Termux. Start zsh in the current session:

```bash
exec zsh
```

This replaces the current bash process with zsh and loads the new aliases,
functions, prompt, and PATH immediately. A newly opened Termux session will
also start zsh automatically.

> From bash, do not run `source ~/.zshrc` — it is a zsh configuration and will
> fail with `setopt: command not found` / `parse error near '('`. Use
> `exec zsh` instead.
