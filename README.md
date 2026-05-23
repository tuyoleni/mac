# mac

Fresh macOS developer setup in one small script.

## Run

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuyoleni/mac/main/mac)"
```

Install everything:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuyoleni/mac/main/mac)" -- full
```

With Git identity:

```bash
GIT_USER_NAME="Your Name" GIT_USER_EMAIL="you@example.com" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuyoleni/mac/main/mac)"
```

## Core

- Homebrew
- Xcode Command Line Tools
- Git, Git LFS, GitHub CLI
- Node.js and Python

The script also adds a small managed block to `~/.zshrc` so Homebrew is available in new terminals.

## Optional

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuyoleni/mac/main/mac)" -- webstorm android docker
```

Extras you can add:

- `webstorm`
- `android`
- `docker`
- `services`
- `full`

## Review First

```bash
curl -fsSLO https://raw.githubusercontent.com/tuyoleni/mac/main/mac
less mac
chmod +x mac
./mac
```

The script is safe to rerun.
