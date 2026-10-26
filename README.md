# Shell-Setup

A modular, cross-platform Zsh and development environment configuration for **Termux (Android)**, **macOS**, and **Linux**.

## Features

- **Root Modular Zsh**: Core shell modules are centrally maintained in `zsh/` (`aliases.zsh`, `git-aliases.zsh`, `git-custom.zsh`, `prompt.zsh`), copied to `~/.zsh/`, and sourced dynamically by `~/.zshrc`.
- **Environment Base Configs**: Platform-specific shortcuts (`base.bash`) installed as `~/.zsh/base.zsh` (e.g., Homebrew aliases on macOS, pkg/storage aliases on Termux, sudo-aware apt aliases on Ubuntu/Debian).
- **Universal Neovim Setup**: Complete, modern Neovim configuration maintained in `.config/nvim/` and safely installed directly into `~/.config/nvim`.
- **Unified Git Utilities & Submodule Shortcuts**: Comprehensive Git aliases and submodule commands merged into `zsh/git-aliases.zsh` with descriptions, example usages, safety indicators (`[DESTRUCTIVE]`), and auto-resetting author overrides (`gcase`).
- **Interactive SSH & Git Commit Signing Setup**: Automated SSH key generator (`.ssh/setup.bash` or `ssh-setup` alias) supporting Auth keys, Signing keys, or Both, automatic `allowed_signers` setup, and clipboard integration for GitHub.
- **System Cleanup & Storage Inspection**: Tailored storage usage inspection aliases (`hdu`, `pdu`, `sdu`, etc.) and cache cleanup scripts for both macOS (`Mac/clean-up.bash`, `Mac/chrclean.sh`) and Termux (`Termux/clean-up.bash`).
- **Universal Installer**: Auto-detects your environment and installs packages, configs, plugins, and optional extensions.

---

## Quick Start

Run the universal installer from the repository root:

```bash
cd ~/Shell-Setup
./install.bash
```

Running without arguments launches an interactive menu:

```text
=== Shell-Setup Installer (termux) ===

  What would you like to do?

    1) Full install      — zsh + essentials + modules + gitconfig + ssh setup
    2) Install zsh       — install zsh & set as default shell
    3) Essentials        — install essentials (git, neovim, which, etc.)
    4) Modules only      — copy modular configs, base config & configure ~/.zshrc
    5) Git & SSH Setup   — configure ~/.gitconfig and setup SSH keys / signing
    6) Extensions        — install optional extras (Node.js, PHP, Antigravity)
    7) Git aliases       — install or update unified git aliases & submodule shortcuts
    8) Everything        — full install + all extensions + SSH setup
    q) Quit
```

### Android proot-distro (Ubuntu or Debian)

Both `ubuntu` and `debian` proot-distro images are supported. Install the image
once, log in, and run the installer from inside the container:

```bash
proot-distro install ubuntu        # or: proot-distro install debian
proot-distro login ubuntu          # or: proot-distro login debian

# Inside the container:
git clone https://github.com/<your-user>/Shell-Setup.git
cd Shell-Setup
./install.bash --all
```

The installer detects the proot container, clears inherited Termux/Android
environment variables, and uses the container's own `apt`, `git`, `zsh`, and
other tools. `sudo` is not required inside proot-distro because the login user
is root; on a normal Debian/Ubuntu desktop the installer uses `sudo` when needed.

### Command-Line Flags

For automated or non-interactive setups:

```bash
./install.bash --all          # Full installation (zsh + essentials + modules + gitconfig + ssh)
./install.bash --modules      # Only copy modules, base.bash, .config, .termux, patch ~/.zshrc
./install.bash --essentials   # Only install essential packages
./install.bash --zsh          # Only install zsh and set as default shell
./install.bash --ssh          # Run interactive SSH & Git commit signing setup
./install.bash --gitconfig    # Configure global Git config (~/.gitconfig & allowed_signers)
./install.bash --git-aliases  # Install or update unified git aliases & submodule shortcuts
./install.bash --extensions   # Interactive extension picker
./install.bash --node         # Install Node.js
./install.bash --php          # Install PHP
./install.bash --antigravity  # Install Antigravity CLI
./install.bash --everything   # Full setup including extensions and SSH setup
./install.bash --help         # Show help message
```

---

## Repository Structure

```text
Shell-Setup/
├── .config/                    # Shared configurations (safely installed to ~/.config/)
│   ├── git/                    # Git account list template
│   │   └── accountList
│   └── nvim/                   # Universal Neovim configuration (installed to ~/.config/nvim)
│       ├── init.lua
│       ├── lazy-lock.json
│       ├── tailwind-classes.txt
│       ├── README.md
│       └── lua/
│           ├── config/         # LSP and autocompletion configs
│           └── plugins/        # Plugin definitions managed by lazy.nvim
├── .gitconfig                  # Global Git config template (SSH signing & nvim editor)
├── .gitignore
├── install.bash                # Root universal installer
├── nvim-cheatsheet.md          # Neovim keymaps reference
├── README.md                   # Main documentation
├── .ssh/
│   ├── config                  # Sample SSH host config (multi-account mapping)
│   ├── setup.bash              # Interactive SSH key generator & Git signing setup
│   └── README.md               # Detailed SSH and signing guide
├── zsh/                        # Universal Zsh configuration modules (installed to ~/.zsh/)
│   ├── aliases.zsh             # General shell aliases & ssh-setup shortcut
│   ├── git-aliases.zsh         # Unified Git & submodule aliases with safety indicators
│   ├── git-custom.zsh          # Multi-account Git clone helpers (gClone, qiuGClone, triGClone)
│   └── prompt.zsh              # Dynamic Git-aware prompt
├── Mac/
│   ├── base.bash               # macOS-specific aliases (Homebrew: bcu, bcc)
│   ├── clean-up.bash           # Unified macOS smart cleanup editor & storage analysis
│   ├── .zshrc                  # Modular macOS .zshrc
│   └── README.md               # macOS guide
├── Linux/
│   └── base.bash               # Ubuntu/Debian (and proot-distro) apt aliases
└── Termux/
    ├── base.bash               # Termux-specific aliases (pkgup, pkgin, storage shortcuts)
    ├── clean-up.bash           # Unified Termux smart cleanup editor & storage analysis
    ├── .termux/                # Color scheme & termux.properties (installed to ~/.termux/)
    ├── .zshrc                  # Modular Termux .zshrc
    └── README.md               # Termux guide
```

---

## Unified Git Aliases & Submodule Management

All Git and submodule utilities are consolidated in `zsh/git-aliases.zsh`. Each alias has a concise description, and complex/destructive commands include interactive help/usage when called with `-h` or `--help`.

### Git Submodule Shortcuts

| Alias | Command | Description |
|---|---|---|
| `gsm` | `git submodule` | Base submodule command |
| `gsmi` | `git submodule init` | Initialize submodules in `.git/config` |
| `gsmu` | `git submodule update` | Update registered submodules |
| `gsmui` | `git submodule update --init` | Initialize and update in one step |
| `gsmuir` | `git submodule update --init --recursive` | Recursively initialize and update all nested submodules |
| `gsmur` | `git submodule update --remote` | Update submodules to latest remote HEAD |
| `gsmurm` | `git submodule update --remote --merge` | Update submodules to remote HEAD and merge |
| `gsma <repo>` | `git submodule add <repo>` | Add a new repository as a submodule |
| `gsmd <path>` | `git submodule deinit <path>` | Unregister a submodule |
| `gsmdf <path>` | `git submodule deinit -f <path>` | `[DESTRUCTIVE]` Force unregister and discard submodule changes |
| `gsmrm <path>` | `gsmrm <path>` | `[DESTRUCTIVE]` Completely deinitialize, remove submodule, and clean `.git/modules` |
| `gsms` | `git submodule status` | Show commit SHA and status of submodules |
| `gsmsr` | `git submodule status --recursive` | Show status of submodules recursively |
| `gsmfe '<cmd>'` | `git submodule foreach '<cmd>'` | Execute command in each submodule |
| `gsmfer '<cmd>'` | `git submodule foreach --recursive` | Recursively execute command in each submodule |
| `gsmsync` | `git submodule sync` | Synchronize submodules' remote URL configuration |
| `gsmsyncr` | `git submodule sync --recursive` | Recursively sync submodule URLs |
| `gsmpl` | `gsmpl` | Pull latest commits for all submodules on main/master |
| `gsmch <branch>` | `gsmch <branch>` | Checkout specified branch across all submodules |
| `gsmdiff` | `git diff --submodule` | View diff of submodule changes |

### Committing & Identity Reset

- `gcase`: Commits staged changes under a temporary author/committer identity, and **automatically resets** the environment afterwards (`gcclear`):
  ```bash
  gcase "Jane Doe" "jane@example.com" "feat: add user authentication"
  ```
  If called without arguments or with `--help`, `gcase` outputs usage examples.

### Safety Indicators

Commands that can overwrite history or permanently discard uncommitted changes are explicitly tagged:
- `glfh` (`git fetch origin && git reset --hard origin/main`): `[DESTRUCTIVE]` Discards local changes to match remote.
- `ghf` (`git push --force`): `[DESTRUCTIVE]` Force pushes and rewrites remote history.
- `grl` (`git restore .`): `[DESTRUCTIVE]` Discards unstaged modifications in current directory.
- `grth` (`git reset --hard`): `[DESTRUCTIVE]` Deletes uncommitted changes and resets branch HEAD.
- `gbdf` (`git branch -D`): `[DESTRUCTIVE]` Force deletes a local branch.
- `gbdr <remote> <branch>`: `[DESTRUCTIVE]` Deletes a remote branch.
- `gasd` (`git stash drop`): `[DESTRUCTIVE]` Permanently deletes a stash entry.

---

## Git Multi-Account Customizer

Manage multiple Git accounts and custom clone/config functions using `zsh/customizeGit.bash` (installed to `~/.zsh/customizeGit.bash`). Run it anytime with:

```bash
git-accounts
# or
custom-git
```

### Features
1. **Interactive TUI**: View all configured accounts, add new accounts, edit existing accounts, or delete accounts.
2. **Auto-Generates Custom Functions**: Dynamically writes into `git-custom.zsh` for each account:
   - `<short>GClone`: Multi-account SSH-based clone wrapper (e.g., `qiuGClone`, `tpGClone`)
   - `<short>_gConfig`: Configures repo-local user name and email
   - `<short>_vConfig`: Configures repo-local SSH commit signing key
3. **Structured Account List**: Records accounts in `~/.config/git/accountList` (format: `USERNAME:EMAIL:SHORTNAME`).
4. **Seamless SSH Setup Transition**: Prompts to immediately configure SSH keys for added accounts upon exit.

---

## SSH Key & Git Commit Signing Setup

An interactive setup utility is provided at `.ssh/setup.bash` and installed to `~/.ssh/setup.bash`. You can invoke it anytime with the alias:

```bash
ssh-setup
```

### What It Does

1. **Creates `~/.ssh`** if it does not already exist, applying secure permissions (`700`).
2. **Detects Git Accounts**: Reads `~/.config/git/accountList` and shows the current status of Auth keys, Signing keys, and SSH host aliases. Allows setup for a specific account, all accounts, selective accounts, or manual input.
3. **4 Key Type Choices**:
   - **Authentication key only [Default]**: Saves key as `~/.ssh/<Username>` (as-is), configures `~/.ssh/config` host alias for custom accounts (`Host github.com-<Username>`), and does NOT add to `allowed_signers` or touch `~/.gitconfig`.
   - **Commit signing key only**: Saves key as `~/.ssh/<Username>_Signing`, adds to `~/.config/git/allowed_signers`, and does NOT add to `~/.ssh/config` or set global `user.signingkey`.
   - **Both as one (unified)**: ONE key used for both authentication (`~/.ssh/config`) and commit signing (`allowed_signers`).
   - **Generate both keys (separate)**: Generates two distinct keys (`<Username>` for Auth and `<Username>_Signing` for commit signing).
4. **Automated Keypair Generation**: Generates modern `ed25519` key pairs with prompted email and username (or pre-filled from account list).
5. **Git Commit Signing Configuration**: When generating a signing key, ensures `~/.config/git/allowed_signers` is updated and global `gpg.format = ssh`, `commit.gpgsign = true`, and `gpg.ssh.allowedSignersFile` are configured.
6. **Multi-Account SSH Host Alias**: Automatically creates host entries in `~/.ssh/config` for custom accounts (e.g., `Host github.com-Work`).
7. **GitHub Ready**: Automatically copies public keys to your system clipboard (`pbcopy` on macOS, `termux-clipboard-set` on Termux, or `xclip`/`wl-copy` on Linux) and prints formatted blocks with instructions for GitHub.

---

## Storage Inspection & Cleanup

Both macOS and Termux include storage usage inspection aliases and cleanup functions:

### Storage Inspection Aliases

| Alias | Description | Platform |
|---|---|---|
| `hdu` | Home directory usage (`~`) | All |
| `pdu` | Termux prefix/system usage (`$PREFIX`) | Termux |
| `sdu` | Root usage (`/`) on Mac / SDCard usage (`/sdcard`) on Termux | Mac / Termux |
| `cdu` | User cache directory usage (`~/.cache`) | Termux |
| `apdu` | Package manager deb archive cache usage | Termux |
| `tdu` | Temporary folder usage (`$PREFIX/tmp`) | Termux |
| `ldu`, `lcdu` | macOS `~/Library` and `~/Library/Caches` usage | Mac |
| `gdu`, `ndu`, `pldu` | Gradle (`~/.gradle`), NPM (`~/.npm`), and Pip (`~/.cache/pip`) cache usage | All |

### Smart Cleanup & System Analyzers

Both macOS and Termux include a unified cleanup utility and system analyzer (`clean-up.bash`) featuring:
1. **Interactive Cache & Temp TUI**: Checklist editor for browser, IDE, and app caches with arrow key navigation, Space to toggle, category badges, and human-readable sizes.
2. **Package & Project Usage Analyzer**:
   - Scans installed packages (Homebrew on macOS, APT/dpkg on Termux), installed sizes, and dependencies/reverse dependencies.
   - Scans projects in a user-chosen directory (prompts for scan folder, defaulting to root `/`).
   - Correlates packages to active project folders (e.g. PHP, Node.js, Python, Rust, Go, Java/Kotlin, C/C++, Ruby).
   - Identifies whether packages are currently in use or potentially unused.
   - Displays project folder size and supports **Full Cleanup** (deleting the project folder AND uninstalling the package bundle together).
   - **Git Status & Unsaved Changes Detection**: Inspects every detected project for uncommitted modifications, untracked files, and unpushed commits to remote. Warns prominently before any deletion to prevent accidental loss of work!
3. **Strict Safety & Path Confirmation**:
   - Shows the exact filesystem paths to be cleared before every deletion.
   - Asks for explicit confirmation for every item (`[Y/n/a(all)/q(quit)]`).

- **Command-Line Options**:
  - `./clean-up.bash` : Launch interactive main menu.
  - `./clean-up.bash --cache` : Launch cache & temp TUI editor directly.
  - `./clean-up.bash --packages` (or `--pkg`) : Launch package & project analyzer directly.
  - `./clean-up.bash --scan` : Scan and report all cleanable sizes without deleting.
  - `./clean-up.bash --dry-run` : Simulate cleanup and preview files/packages to be removed.
  - `./clean-up.bash --all` : Clean all detected cache targets (with per-item confirmation).
