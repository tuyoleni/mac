# mac

Interactive macOS setup for a fresh laptop. A short onboarding wizard lets you pick what you want, then you watch each step run with a live spinner.

## Run

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuyoleni/mac/main/mac)"
```

Flags go after `--`:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuyoleni/mac/main/mac)" -- --yes
```

| Flag | Effect |
|---|---|
| `-y`, `--yes` | Skip the wizard, run the defaults |
| `--demo` | Fake every step to preview the progress screen; installs nothing |
| `full` | Also preselect PostgreSQL 16 and Redis |
| `docker` | Also preselect Docker Desktop |
| `workspaces` | Only set up workspaces and the shell block |

Optional env vars: `GIT_USER_NAME`, `PERSONAL_EMAIL`, `MOODBOD_EMAIL`, `ASMBLY_EMAIL` prefill the identity prompts.

## The wizard

Controls are just the arrow keys and Enter (`q` quits). Enter on a row ticks or unticks it; Enter on **Continue** moves on, **Back** goes back.

1. **Welcome:** choose *Guided* (step by step) or *One list* (everything on one screen).
2. **Command-line tools**
3. **Apps**
4. **Setup:** git defaults, workspaces, shell. If workspaces are ticked it asks for your name and a git email per workspace (skippable).
5. **Review:** shows exactly what will be set up, then **Install**.

Anything already installed is marked and starts unticked.

Ticked by default:

- **CLI tools:** Git, Git LFS, GitHub CLI, Node.js, Python
- **Apps:** WebStorm, Postman, NotchNook, Arc, OrbStack, Android Studio (installed last)
- **Config:** Git defaults, workspaces, shell setup

Off by default: PostgreSQL 16, Redis, Docker Desktop, macOS defaults (key repeat, Finder, Dock).

Selecting any brew package automatically adds the Xcode Command Line Tools and Homebrew steps first. They need your admin password once, up front.

## While it runs

Each step shows `[n/total]`, a spinner and the latest line of output. It ends in `✓` with the time taken, or `✗` with the last lines of the error. A failed step never stops the rest; failures are listed at the end and rerunning retries only what's missing. The full log is at `~/.mac-setup.log`.

## Workspaces

`personal`, `moodbod` and `asmbly` are shell aliases that switch the whole environment. Each workspace in `~/.profiles/<name>/` has its own:

- SSH key (`IdentitiesOnly`, so keys never leak between accounts)
- Git author and committer identity (`profile.env`, created once and never overwritten)
- `gcloud` and `gh` login
- Private `HOME` for any CLI that keeps its login in `~` with no env override. Those commands run under it (only that command, nothing else is affected). The list lives in `~/.profiles/tools` and is yours to extend:

```bash
ws-tool add <command>   # wrap a new tool, effective immediately
ws-tool rm <command>
ws-tool list
wsrun <command> ...     # one-off: run anything inside the active workspace
```

  Default list: `convex vercel firebase wrangler supabase netlify railway flyctl stripe heroku aws`. `npx <tool>` follows the same rule, and tools with no global binary (like `convex`) run through `npx`. The list is created once and never overwritten by reruns.

- Shared config: each workspace home links to the files in `~/.profiles/shared` (default `.gitconfig`, `.gitignore_global`, `.npmrc`, `.yarnrc`, `.editorconfig`, `.ssh/known_hosts`), so wrapped tools behave normally. Logins and private keys are never shared. Add more with `ws-share <path relative to ~>`.

After setup, in each workspace run `gh auth login` and `npx convex login` once, and add the printed SSH public keys to the matching GitHub accounts. Extra per-workspace exports (tools that take an env var instead, e.g. `AWS_PROFILE`) go in `~/.profiles/<name>/local.sh`.

## What it touches

- `~/.zshrc`: one managed block between `# >>> mac >>>` and `# <<< mac <<<` (Homebrew, Android SDK, Java, workspace switcher). Everything outside it is left alone.
- `~/workspace-switcher.sh`: regenerated on every run.
- `~/.profiles/`: workspace data, never deleted.

Safe to rerun at any time. Requires macOS; works with the stock bash 3.2.

## Review first

```bash
curl -fsSLO https://raw.githubusercontent.com/tuyoleni/mac/main/mac
less mac
chmod +x mac
./mac
```
