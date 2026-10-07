# mac

Set up a new Mac in one command, with workspaces.

## Install

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuyoleni/mac/main/mac)"
```

Pick what you want with the arrow keys and Enter, then choose **Install**. It's safe to run again.

## Workspaces

A workspace is a folder for one account, like `work` or `personal`. Anything you put inside it automatically uses that account for git, GitHub and your command-line tools. There is nothing to switch.

The installer asks for your workspace names. To add one later:

```bash
ws add work
```

Then sign in to GitHub once, inside its folder:

```bash
cd ~/Developer/Work
gh auth login
```

`ws status` shows all your workspaces.
