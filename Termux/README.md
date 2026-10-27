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
./install.bash
```

This automates:
- Copying the slim, modular `.zshrc` into `~/.zshrc`
- Copying modular config files from root `zsh/` (`aliases.zsh`, `git-aliases.zsh`, `git-functions.zsh`, `prompt.zsh`) to `~/.zsh/`
- Copying Termux base shortcuts (`Termux/base.bash`) to `~/.zsh/base.zsh`
- Installing `zsh-syntax-highlighting` into `~/.zsh/plugins/` (if not already present)
- Copying Termux terminal settings and styling from `Termux/.termux/` to `~/.termux/`
- Installing the Neovim configuration from `.config/nvim/` to `~/.config/nvim/` **only when Option 2 is selected**
- Setting up global Git configurations (`~/.gitconfig` & `~/.config/git/allowed_signers`) and SSH files **only when Option 3 is selected**

---

# 4. Storage Usage Inspection & Cleanup

Termux includes a dedicated storage analysis and cache cleanup utility in `Termux/clean-up.bash`:

### Storage Inspection Aliases
- `hdu`: Home directory usage (`~`)
- `pdu`: Termux Prefix / System storage usage (`$PREFIX`)
- `sdu`: Android Shared Storage / SDCard usage (`/sdcard`)
- `cdu`: User Cache Directory usage (`~/.cache`)
- `apdu`: APT / PKG downloaded package archive usage
- `tdu`: Temporary directory usage (`$PREFIX/tmp`)
- `gdu`, `ndu`, `pldu`: Gradle, NPM, and Pip cache usage

### Smart Cleanup & Package Analyzer
Run `./clean-up.bash` to launch the interactive main menu:
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
  - `./clean-up.bash --cache` : Launch cache TUI editor directly.
  - `./clean-up.bash --packages` (or `--pkg`) : Launch package & project analyzer directly.
  - `./clean-up.bash --scan` : Preview cleanable sizes without deleting.
  - `./clean-up.bash --dry-run` : Simulate actions without modifying files.
  - `./clean-up.bash --all` : Clean all detected cache targets (with per-item confirmation).

---

# 5. Change Your Default Shell

Set Zsh as your default login shell:

```bash
chsh -s zsh
```

---

# 6. Restart Your Terminal Session

Close the current terminal session:

```bash
exit
```

Then reopen Termux. Your new Zsh configuration will be loaded automatically!