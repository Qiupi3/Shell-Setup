# macOS Shell Setup Guide

This folder contains macOS-specific configurations, environment base aliases, and system cleanup tools.

## Automated Installation

Run the universal installer from the repository root:

```bash
cd ~/Shell-Setup
./install.bash
```

This automates:
- Copying the modular `.zshrc` to `~/.zshrc` (with support for Apple Silicon `/opt/homebrew` and Intel `/usr/local`)
- Copying modular config files from root `zsh/` (`aliases.zsh`, `git-aliases.zsh`, `git-custom.zsh`, `prompt.zsh`) to `~/.zsh/`
- Copying macOS base aliases (`base.bash` with Homebrew shortcuts `bcu`, `bcc`) to `~/.zsh/base.zsh`
- Installing `zsh-syntax-highlighting` into `~/.zsh/plugins/` (if not already present)
- Copying shared configuration from `.config/` (including Neovim configuration in `.config/nvim/`) to `~/.config/`
- Setting up global Git configurations (`~/.gitconfig` & `~/.config/git/allowed_signers`)
- Installing SSH setup helper to `~/.ssh/setup.bash` (callable with alias `ssh-setup`)
- Setting Zsh as your default shell

## Cleanup & System Analysis Utilities

macOS-specific storage analysis, package analyzer, and smart cleanup utility:
- `clean-up.bash`: Unified interactive cleanup editor, package usage analyzer, and storage inspector:
  - **Smart Cache & Temp Cleanup**: Scans system caches (Safari, Chrome profiles & AI models, system logs) down to developer-specific tools (Homebrew, Node/npm, Python, Cargo, Go, Gradle, Xcode DerivedData, Android Studio, JetBrains IDEs, VS Code).
  - **Package & Project Usage Analyzer**: Scans Homebrew formulas, installed sizes, and dependencies/reverse dependencies. Prompts for folder to scan (default: user home `~`), correlates packages with active projects, identifies unused packages, and supports Full Cleanup (deleting project folder AND uninstalling package bundle).
  - **Git Unsaved Changes Detection**: Warns if a project has uncommitted changes, untracked files, or unpushed commits before deletion.
  - **Strict Confirmation**: Shows the exact filesystem paths to be cleared and asks for confirmation for every delete.
  - Sourced aliases for quick inspection: `hdu`, `sdu`, `ldu`, `lasdu`, `lcdu`, `ladu`, `gdu`, `adu`, `ndu`.
  - CLI options: `--cache`, `--packages`, `--all`, `--scan`, and `--dry-run`.
