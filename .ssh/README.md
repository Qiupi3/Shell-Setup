# SSH Key Setup Guide for Git & GitHub

This directory contains configuration and automated setup tools for managing SSH keys and Git commit signing.

This folder will be replicated inside `~/.ssh`, either copy manually or using the Automated Script. The Automated Script will be called when using the built in `install.bash` script.

---

## Quick Setup: Automated Script

You can run the interactive setup script directly:

```bash
# Using the repository script:
bash .ssh/setup.bash

# Or after installing Shell-Setup, use the alias:
ssh-setup
```

### What the Setup Script Automates:
1. Ensures `~/.ssh` exists with secure permissions (`chmod 700`).
2. Detects accounts from `~/.config/git/accountList` (with key existence indicators), allowing you to configure a specific account, all accounts, selective accounts, or manual input.
3. Provides 4 key setup choices:
   - **Authentication key only [Default]**: Filename as is (`~/.ssh/<Username>`), configured in `~/.ssh/config` host aliases (for custom accounts, e.g. `github.com-<Username>`), and NOT added to `allowed_signers`.
   - **Commit signing key only**: Filename with suffix `_Signing` (`~/.ssh/<Username>_Signing`), added to `~/.config/git/allowed_signers`, and NOT added to `~/.ssh/config`.
   - **Both as one (unified)**: ONE key used for both authentication (`~/.ssh/config`) and commit signing (`allowed_signers`).
   - **Generate both keys (separate)**: Two distinct keys (`<Username>` for Auth and `<Username>_Signing` for commit signing).
4. Generates modern `Ed25519` key pairs (`ssh-keygen -t ed25519`).
5. Configures `~/.config/git/allowed_signers` automatically when signing keys are set up, keeping `~/.gitconfig` global signing key untouched for account wrappers.
6. Copies public keys to your system clipboard (`pbcopy`, `termux-clipboard-set`, or `xclip`/`wl-copy`) and prints them formatted for GitHub.

---

## Manual Setup Guide

If you prefer to perform the setup manually:

### 1. Ensure `~/.ssh` Exists

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

### 2. Generate a New SSH Key

#### Recommended: Ed25519
```bash
ssh-keygen -t ed25519 -C "your_email@example.com" -f ~/.ssh/id_ed25519
```

Set secure permissions:
```bash
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

---

## 3. Key Separation Rules

- **Authentication Key**:
  - Saved as `~/.ssh/<Account>` (filename as-is).
  - Configured in `~/.ssh/config` under `Host github.com-<Account>` (for custom account names).
  - Used for `git clone`, `git push`, and SSH connections.
  - Added as **Authentication Key** on GitHub.
  - NOT added to `allowed_signers`.
- **Commit Signing Key**:
  - Saved as `~/.ssh/<Account>_Signing`.
  - Added to `~/.config/git/allowed_signers`.
  - Used exclusively for Git commit verification (`gpg.format ssh`).
  - Added as **Signing Key** on GitHub.
  - NOT added to `~/.ssh/config` host aliases.

---

## 4. Add the Public Key to GitHub

1. Open **GitHub** → **Settings** → **SSH and GPG keys**.
2. Click **New SSH key**.
3. View or copy your public key:
   ```bash
   cat ~/.ssh/id_ed25519.pub
   ```
4. Paste the key content into the "Key" field.
5. In **Key type**:
   - Select **Authentication Key** for git clone/push.
   - Select **Signing Key** for verifying git commits with a "Verified" badge.
6. Click **Add SSH key**.

---

## 5. Configure Git Commit Signing

Create the directory and allowed signers file:

```bash
mkdir -p ~/.config/git
touch ~/.config/git/allowed_signers
```

Add your email and signing public key to `~/.config/git/allowed_signers`:

```text
your_email@example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK...
```

Configure Git to sign commits with SSH globally (to do so locally, remove the `--global` flag):

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers
```

---

## 6. Multi-Account SSH Configuration

To manage multiple GitHub accounts, define host aliases in `~/.ssh/config`:

```text
# Work account's custom SSH
Host github.com-CompanyAccount
    Hostname github.com
    User git
    IdentityFile ~/.ssh/Work

# Personal account's custom SSH
Host github.com-Personal
    Hostname github.com
    User git
    IdentityFile ~/.ssh/Personal
```

When cloning:
```bash
git clone git@github.com-Work:Owner/Repo.git
```
Or use the built-in clone helper:
```bash
workGClone Owner/Repo
```