# mac

Fresh macOS developer setup in one small script.

## Run

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuyoleni/mac/main/mac)"
```

With Git identity:

```bash
GIT_USER_NAME="Your Name" GIT_USER_EMAIL="you@example.com" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuyoleni/mac/main/mac)"
```

## Core

- Homebrew
- Xcode Command Line Tools
- Git, Git LFS, GitHub CLI
- Node.js, Python, pnpm, Yarn
- Common CLI tools: `jq`, `ripgrep`, `fzf`, `bat`, `eza`, `tree`, `tmux`, `shellcheck`, `shfmt`
- Shell setup for Homebrew, `mise`, `direnv`, `zoxide`, and `starship`

## Optional

```bash
INSTALL_GUI_APPS=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuyoleni/mac/main/mac)"
INSTALL_ANDROID=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuyoleni/mac/main/mac)"
INSTALL_DOCKER=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuyoleni/mac/main/mac)"
INSTALL_DEV_SERVICES=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuyoleni/mac/main/mac)"
```

## Review First

```bash
curl -fsSLO https://raw.githubusercontent.com/tuyoleni/mac/main/mac
less mac
chmod +x mac
./mac
```

The script is safe to rerun. It keeps a managed block in `~/.zshrc` and updates that block on future runs.
