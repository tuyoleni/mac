# mac

Interactive macOS setup for a fresh laptop. Pick what you want from a checklist, then watch each step run with a live spinner.

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
| `-y`, `--yes` | Skip the menu, run the defaults |
| `full` | Also preselect PostgreSQL 16 and Redis |
| `docker` | Also preselect Docker Desktop |
| `workspaces` | Only set up workspaces and the shell block |

Optional env vars: `GIT_USER_NAME`, `PERSONAL_EMAIL`, `MOODBOD_EMAIL`, `ASMBLY_EMAIL` prefill the identity prompts.

## The menu

`↑/↓` (or `j/k`) move, `space` toggles, `a` all, `n` none, `enter` starts, `q` quits. Anything already installed is marked and starts unticked.

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
- Private `HOME` used by **Convex** and **Vercel**, which store logins in `~` and have no override. `convex`, `vercel`, `npx convex` and `npx vercel` run under it; nothing else is affected.

After setup, in each workspace run `gh auth login` and `npx convex login` once, and add the printed SSH public keys to the matching GitHub accounts. Extra per-workspace exports can go in `~/.profiles/<name>/local.sh`.

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
