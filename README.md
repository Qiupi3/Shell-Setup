# Shell-Setup

A modular, cross-platform Zsh and development environment configuration for **Termux (Android)**, **macOS**, and **Linux**.

## Features

- **Four selectable modules**: Shell environment, Neovim, Git accounts & SSH, and Extensions. Install only what you need; each module is self-sufficient.
- **Modular Zsh**: Core shell modules are maintained in `zsh/` (`aliases.zsh`, `git-aliases.zsh`, `git-functions.zsh`, `prompt.zsh`), copied to `~/.zsh/`, and sourced dynamically by `~/.zshrc`.
- **Environment Base Configs**: Platform-specific shortcuts (`base.bash`) installed as `~/.zsh/base.zsh` (e.g., Homebrew aliases on macOS, pkg/storage aliases on Termux, sudo-aware apt aliases on Ubuntu/Debian).
- **Neovim as the default editor**: Config from `.config/nvim/` is installed to `~/.config/nvim`, with an `EDITOR`/`VISUAL` block appended to `~/.zshrc` and `git core.editor` set. Owned exclusively by Option 2.
- **Unified Git Utilities & Submodule Shortcuts**: Comprehensive Git aliases and submodule commands merged into `zsh/git-aliases.zsh` with descriptions, example usages, safety indicators (`[DESTRUCTIVE]`), and auto-resetting author overrides (`gcase`).
- **Git accounts without leaking data**: `customizeGit.bash` writes accounts and generated wrappers only under `$HOME`. The repository ships no usernames, emails, or private wrappers.
- **SSH key audit**: existing keys in `~/.ssh` are inspected and can be mapped to a Git account or to commit signing without regenerating them. New `ed25519` keys, `allowed_signers`, and host aliases are handled by `ssh-setup`.
- **Selectable extensions**: a multi-select picker (Space to toggle, Enter to install) for individual languages (Python, Node.js, PHP, Go, Rust, Java), CLI tooling (ripgrep, fd, fzf, jq, tmux, gh, …), and AI coding tools (Antigravity, plus OpenCode inside proot-distro) instead of everything at once.
- **System Cleanup & Storage Inspection**: Tailored storage usage inspection aliases (`hdu`, `pdu`, `sdu`, etc.) and cache cleanup scripts for macOS (`Mac/clean-up.bash`, `Mac/chrclean.sh`) and Termux (`Termux/clean-up.bash`).

---

## Quick Start

### One-liner (no clone required)

```bash
curl -fsSL https://raw.githubusercontent.com/Qiupi3/Shell-Setup/main/install.bash | bash
```

The script downloads the current `main` tarball to a temporary directory,
re-runs the installer from there, and removes it afterwards. It attaches the
controlling terminal, so the interactive menu and the extension picker work
even though stdin is a pipe. It also drains the remaining script bytes before
exiting, so curl never ends with `(23) Failure writing output to destination`.

Pass flags with `bash -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/Qiupi3/Shell-Setup/main/install.bash \
  | bash -s -- --all
```

### After installation: load zsh correctly

`~/.zshrc` is a **zsh** file. If the installer was launched from bash (the
normal case for `curl | bash`), `source ~/.zshrc` will fail with
`setopt: command not found` or `parse error near '('`. Start zsh instead:

```bash
exec zsh
```

`exec zsh` replaces the current bash process, so aliases, generated Git
functions, the prompt, and the tool `PATH` are available immediately — no need
to close Termux or re-enter proot-distro. A new terminal will use zsh
automatically after Option 1 sets it as the default shell.

### From a clone

Run the universal installer from the repository root:

```bash
cd ~/Shell-Setup
./install.bash
```

Running without arguments launches an interactive menu:

```text
=== Shell-Setup Installer (linux) ===

  What would you like to set up?

    1) Shell environment   — Zsh, aliases, plugins, ~/.zshrc (offers Neovim)
    2) Neovim editor       — config, EDITOR/VISUAL, git core.editor
    3) Git accounts & SSH  — accounts, SSH keys, clone wrappers
    4) Extensions          — multi-select languages and CLI tools
    5) Everything          — run 1 → 2 → 3 → 4
    q) Quit
```

### What each module installs

| Option | Packages | Files |
|---|---|---|
| 1. Shell | `zsh`, `git`, `ca-certificates`; optional QoL tools | `zsh/*.zsh` → `~/.zsh/`, `base.bash` → `~/.zsh/base.zsh`, `ENV/.zshrc` → `~/.zshrc`, syntax-highlighting plugin |
| 2. Neovim | `neovim` | `.config/nvim/` → `~/.config/nvim/`, editor block in `~/.zshrc`, `git core.editor` |
| 3. Git & SSH | `openssh-client` (Linux) | `~/.ssh/config`, `~/.ssh/setup.bash`, `~/.config/git/accountList`, `~/.zsh/git-functions.zsh`, generated `~/.zsh/git-custom.zsh` |
| 4. Extensions | selected only | none |

**Essentials are not a separate option.** Each module installs the packages it
needs. The recommended CLI tools (`tree`, `which`, `man`, `less`, `curl`,
`wget`, `unzip`, `file`, `ps`) are offered at the end of Option 1, defaulting to
**no**, and the installer lists exactly which features will not work if skipped.

### Option 3 flow (Git accounts & SSH)

Option 3 runs in two orders that match the generated files:

1. **Accounts and wrappers** — opens the account manager so you define
   `USERNAME:EMAIL:SHORTNAME` first. On a fresh setup it goes straight to the
   first "Add account" prompt; when accounts already exist the manager is
   optional (default: skip). Saving regenerates `~/.zsh/git-custom.zsh` with
   `<short>GClone`, `<short>_gConfig`, and `<short>_vConfig`.
2. **SSH keys and signing** — runs `ssh-setup` once. Keys are named after the
   accounts, added to `~/.ssh/config` / `allowed_signers`, and the wrappers are
   regenerated afterwards. A single configured account is selected
   automatically instead of asking you to pick "1" from a one-item menu.

`<short>_vConfig` looks for `<Username>_Signing.pub`, then `<Username>.pub`, so
it works with both separate signing keys and unified/auth-only keys. It fails
with a clear message instead of silently using an unrelated default key.

### Android proot-distro (Ubuntu or Debian)

Both `ubuntu` and `debian` proot-distro images are supported. Install the image
once, log in, and run the installer from inside the container:

```bash
proot-distro install ubuntu        # or: proot-distro install debian
proot-distro login ubuntu          # or: proot-distro login debian

# Inside the container — one-liner:
curl -fsSL https://raw.githubusercontent.com/Qiupi3/Shell-Setup/main/install.bash | bash

# Or from a clone:
git clone https://github.com/<your-user>/Shell-Setup.git
cd Shell-Setup
./install.bash            # interactive: pick modules
# or
./install.bash --all      # Shell + Neovim + Git/SSH
```

The installer detects the proot container, re-executes itself with the
container's native `/bin/bash`, clears inherited Termux/Android environment
variables, and puts the guest's binaries ahead of the bind-mounted Termux ones.
Termux's `curl` and `tar` remain available as a fallback for the self-bootstrap
download, but Git, SSH, and zsh use the guest tools. Option 1 installs the guest
`zsh` and Option 3 installs the guest `openssh-client`: Termux's `ssh` resolves
`~/.ssh` through Android's home and cannot see keys stored in the container's
`$HOME/.ssh`.

If your login shell resolves `bash` to Termux's Android binary, run the
one-liner with the container's shell explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/Qiupi3/Shell-Setup/main/install.bash | /bin/bash
```

After installation, run `exec zsh` **inside the same proot-distro session** to
load the aliases, Git functions, prompt, and tool paths immediately. `sudo` is
not required inside proot-distro because the login user is root; on a normal
Debian/Ubuntu desktop the installer uses `sudo` when needed.

#### `Permission denied (publickey)` inside proot-distro

1. Confirm the client is the guest one, not Termux's:

   ```bash
   command -v ssh          # must be /usr/bin/ssh, not /data/data/com.termux/...
   ssh -T git@github.com-<Username>
   ```

   If it points at Termux, install the guest client and try again:

   ```bash
   apt-get update && apt-get install -y openssh-client
   ```

2. Compare the local fingerprint with GitHub → **Settings → SSH and GPG keys**:

   ```bash
   ssh-keygen -lf ~/.ssh/<Username>.pub
   ```

3. The key must be added to the GitHub account that owns the repository as an
   **Authentication Key**. An SSH **Signing Key** alone cannot clone or push.
   Re-running the setup with a new key means the new public key must be added
   again; the fingerprint printed here is the one GitHub must show.

SSH error messages always print the real `HostName` (`git@github.com`), even
when the remote uses the `github.com-<Username>` alias. That text does not mean
the alias was ignored.

### Command-Line Flags

```bash
# Modules
./install.bash --shell            # Option 1 (offers Option 2 at the end)
./install.bash --nvim             # Option 2
./install.bash --git              # Option 3
./install.bash --ext              # Option 4 (interactive picker)
./install.bash --ext python,node,ripgrep   # Option 4 (non-interactive)
./install.bash --ext antigravity  # Antigravity CLI (agy)
./install.bash --ext opencode     # OpenCode (proot-distro only)
./install.bash --all              # Options 1 + 2 + 3
./install.bash --everything       # Options 1 + 2 + 3 + 4

# Legacy flags (still supported)
./install.bash --modules          # Copy shell configs only (no packages, no chsh)
./install.bash --essentials       # Union of module dependencies + QoL tools
./install.bash --zsh              # Install zsh and set it as default shell
./install.bash --ssh              # Alias for --git
./install.bash --gitconfig        # Only write ~/.gitconfig and allowed_signers
./install.bash --git-accounts     # Only run customizeGit.bash
./install.bash --git-aliases      # Only install/update unified git aliases
./install.bash --extensions       # Alias for --ext
./install.bash --node --php --antigravity
./install.bash --help             # Show help message
```

### Extension picker keys

Option 4 (`--ext` without a list) opens the same style of multi-select UI as
the cleanup scripts in `Mac/` and `Termux/`:

```text
↑/↓ or j/k   move the cursor
Space        toggle the highlighted tool
a            select all (or clear all when everything is selected)
i            invert the selection
Enter        install the selected tools
q or Esc     skip extensions
```

Already-installed tools are marked `[installed]` and can still be selected to
re-check them. When stdin is not a terminal (pipes, `</dev/null`, CI), the
picker falls back to the numbered prompt: space-separated numbers, `a` for all,
`n` to skip.

### AI coding tools

The picker includes an **AI coding tools** group:

| Tool | Availability | Installer |
|---|---|---|
| **Antigravity CLI** (`agy`) | Termux, Linux (including proot-distro), macOS | Termux uses [wallentx/antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux); Linux/macOS use the official `https://antigravity.google/cli/install.sh` |
| **OpenCode** (`opencode`) | **Linux proot-distro only** | Official v2 installer: `https://opencode.ai/v2/install` |

Antigravity on Termux installs the `glibc-repo`/`glibc` dependencies first. On
Linux and macOS the official installer places `agy` in `~/.local/bin` (make
sure that directory is on your `PATH`).

OpenCode is listed only inside the Linux catalog because it is supported only
when running in a proot-distro container. The installer checks for the
proot-distro environment and stops with an error anywhere else; from Termux,
log in to the container first:

```bash
proot-distro login ubuntu      # or: proot-distro login debian
curl -fsSL https://raw.githubusercontent.com/Qiupi3/Shell-Setup/main/install.bash | bash -s -- --ext opencode
```

The OpenCode installer writes `~/.opencode/bin`; the path is added to
`~/.zsh/paths.zsh`, so it is available after `exec zsh` (or a new zsh session).

---

## Repository Structure

```text
Shell-Setup/
├── .config/                    # Shared configurations (installed only by their module)
│   ├── git/                    # Account list template (no real accounts)
│   │   └── accountList
│   └── nvim/                   # Universal Neovim configuration (installed to ~/.config/nvim)
│       ├── init.lua
│       ├── lazy-lock.json
│       ├── tailwind-classes.txt
│       ├── README.md
│       └── lua/
│           ├── config/         # LSP and autocompletion configs
│           └── plugins/        # Plugin definitions managed by lazy.nvim
├── .gitconfig                  # Global Git config template (SSH allowed signers)
├── .gitignore
├── install.bash                # Root universal installer
├── nvim-cheatsheet.md          # Neovim keymaps reference
├── README.md                   # Main documentation
├── .ssh/
│   ├── config                  # Sample SSH host config (multi-account mapping)
│   ├── setup.bash              # Key audit, generator & Git signing setup
│   └── README.md               # Detailed SSH and signing guide
├── zsh/                        # Universal Zsh configuration modules (installed to ~/.zsh/)
│   ├── aliases.zsh             # General shell aliases & ssh-setup shortcut
│   ├── git-aliases.zsh         # Unified Git & submodule aliases with safety indicators
│   ├── git-functions.zsh       # Generic gClone / reset_vConfig helpers (no accounts)
│   ├── paths.zsh               # Adds ~/.local/bin, OpenCode, Bun, Cargo, Deno, pnpm to PATH
│   ├── customizeGit.bash       # Generates ~/.zsh/git-custom.zsh from your account list
│   └── prompt.zsh              # Dynamic Git-aware prompt
├── Mac/
│   ├── base.bash               # macOS-specific aliases (Homebrew: bcu, bcc)
│   ├── clean-up.bash           # Unified macOS smart cleanup editor & storage analysis
│   ├── .zshrc                  # Modular macOS .zshrc
│   └── README.md               # macOS guide
├── Linux/
│   ├── base.bash               # Ubuntu/Debian (and proot-distro) apt aliases
│   └── .zshrc                  # Modular Linux .zshrc (history, completion, modules)
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
2. **Auto-Generates Custom Functions**: Dynamically writes `~/.zsh/git-custom.zsh` for each account:
   - `<short>GClone`: Multi-account SSH-based clone wrapper (e.g. `workGClone`)
   - `<short>_gConfig`: Configures repo-local user name and email
   - `<short>_vConfig`: Configures repo-local SSH commit signing key
3. **Structured Account List**: Records accounts in `~/.config/git/accountList` (format: `USERNAME:EMAIL:SHORTNAME`). The repo template contains no real accounts.
4. **Repository stays clean**: every write goes to `$HOME`. `customizeGit.bash` never modifies the cloned repository, so account data cannot leak to another user or the next `git pull`.
5. **Generic helpers**: `gClone` and `reset_vConfig` live in `~/.zsh/git-functions.zsh` and contain no account data.
6. **Seamless SSH transition**: when run from Option 3, the installer handles SSH setup right after the account list, so keys are always attached to a known account. Standalone `git-accounts` still offers SSH setup on exit (set `SHELL_SETUP_NO_SSH_PROMPT=1` to suppress it).
7. **Path setup**: `~/.zsh/paths.zsh` adds per-user tool directories (`~/.local/bin`, OpenCode, Bun, Cargo, Deno, pnpm, Antigravity) so new zsh sessions find them.

---

## SSH Key & Git Commit Signing Setup

An interactive setup utility is provided at `.ssh/setup.bash` and installed to `~/.ssh/setup.bash`. You can invoke it anytime with the alias:

```bash
ssh-setup
```

### What It Does

1. **Creates `~/.ssh`** if it does not already exist, applying secure permissions (`700`).
2. **Audits existing keys first**: every private key in `~/.ssh` is listed with its fingerprint and whether it is mapped to a host (`~/.ssh/config`), an account (`accountList`), or commit signing (`allowed_signers`). Unmapped keys can be mapped to an existing/new account or added as a signing key **without regenerating them**. Auth-only keys are not treated as broken just because they are absent from `allowed_signers`.
3. **Detects Git Accounts**: Reads `~/.config/git/accountList` and shows the current status of Auth keys, Signing keys, and SSH host aliases. A single account is selected automatically; multiple accounts can be set up individually, all at once, selectively, or by manual input.
4. **4 Key Type Choices**:
   - **Authentication key only [Default]**: Saves key as `~/.ssh/<Username>` (as-is), configures `~/.ssh/config` host alias for custom accounts (`Host github.com-<Username>`), and does NOT add to `allowed_signers` or touch `~/.gitconfig`.
   - **Commit signing key only**: Saves key as `~/.ssh/<Username>_Signing`, adds to `~/.config/git/allowed_signers`, and does NOT add to `~/.ssh/config` or set global `user.signingkey`.
   - **Both as one (unified)**: ONE key used for both authentication (`~/.ssh/config`) and commit signing (`allowed_signers`).
   - **Generate both keys (separate)**: Generates two distinct keys (`<Username>` for Auth and `<Username>_Signing` for commit signing).
5. **Automated Keypair Generation**: Generates modern `ed25519` key pairs with prompted email and username (or pre-filled from account list).
6. **Git Commit Signing Configuration**: When generating a signing key, ensures `~/.config/git/allowed_signers` is updated and global `gpg.format = ssh`, `commit.gpgsign = true`, and `gpg.ssh.allowedSignersFile` are configured.
7. **Multi-Account SSH Host Alias**: Automatically creates host entries in `~/.ssh/config` for custom accounts (e.g., `Host github.com-Work`).
8. **GitHub Ready**: Automatically copies public keys to your system clipboard (`pbcopy` on macOS, `termux-clipboard-set` on Termux, or `xclip`/`wl-copy` on Linux) and prints formatted blocks with instructions for GitHub.

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
