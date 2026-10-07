#!/usr/bin/env bash
# ws: folder-based workspaces. The folder you are in decides which accounts
# (git identity + SSH key, gh, gcloud, Convex, Vercel, ...) every tool uses.
#
#   ws add <name> [--dir <path>]   create a workspace (+ its folder under the root)
#   ws list | status | doctor      overview, login state, health checks
#   ws which [path]                which workspace owns a path
#   ws exec [-w name] -- cmd...    run a command inside a workspace
#   ws tool add|rm|list <cmd>      CLIs whose login lives in ~ (run under a private HOME)
#   ws share <path>                share a file from ~ with every workspace home
#   ws rm <name> [--purge]         remove a workspace
#   ws init [zsh|bash]             shell integration (put in your rc: eval "$(ws init zsh)")
#   ws shims                       (re)generate PATH shims
#
# Bash 3.2 compatible. Data lives in $WS_DIR (default ~/.profiles).

set -uo pipefail

WS_VERSION="0.1.0"
REAL_HOME="${WS_REAL_HOME:-$HOME}"
WS_DIR="${WS_DIR:-$REAL_HOME/.profiles}"
WS_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SHIMS_DIR="$WS_DIR/shims"
WS_ROOT="$REAL_HOME/Developer"
[[ -f "$WS_DIR/config" ]] && . "$WS_DIR/config"

# Env-var based tools always get a shim; HOME-bound tools come from $WS_DIR/tools.
BUILTIN_SHIMS="gh gcloud npx"
DEFAULT_TOOLS="convex vercel firebase wrangler supabase netlify railway flyctl stripe heroku aws"
DEFAULT_SHARED=".gitconfig .gitignore_global .npmrc .yarnrc .editorconfig .ssh/known_hosts"

die()  { echo "ws: $*" >&2; exit 1; }
warn() { echo "ws: $*" >&2; }
is_tty() { [[ -t 0 && -t 1 ]]; }

valid_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; }
titlecase() { local f; f="$(printf '%s' "${1:0:1}" | tr '[:lower:]' '[:upper:]')"; printf '%s%s' "$f" "${1:1}"; }

# ---------- registry ----------

ws_exists()   { [[ -n "$1" && -d "$WS_DIR/$1" && -f "$WS_DIR/$1/root" ]]; }
ws_root()     { cat "$WS_DIR/$1/root" 2>/dev/null; }
ws_names()    { local d; for d in "$WS_DIR"/*/; do [[ -f "${d}root" ]] && basename "$d"; done; }
ws_field()    { # ws_field <name> WS_EMAIL
  ( WS_NAME=""; WS_EMAIL=""; . "$WS_DIR/$1/profile.env" 2>/dev/null; eval "printf '%s' \"\${$2:-}\"" )
}

# ---------- resolution: nearest .workspace marker up the ancestry ----------

_walk() {
  local d="$1" n
  while :; do
    if [[ -f "$d/.workspace" ]]; then
      n="$(sed -n 's/^name=//p' "$d/.workspace" | head -1)"
      if ws_exists "$n"; then printf '%s' "$n"; return 0; fi
    fi
    [[ "$d" == / || -z "$d" ]] && return 1
    d="$(dirname "$d")"
  done
}

resolve() { # resolve [path] -> name or empty (exit 1). Tries logical then physical path.
  local p="${1:-$PWD}" d
  [[ -d "$p" ]] || p="$(dirname "$p")"
  d="$(cd "$p" 2>/dev/null && pwd)" || return 1
  _walk "$d" && return 0
  d="$(cd "$p" 2>/dev/null && pwd -P)" || return 1
  _walk "$d"
}

# ---------- tools / shared lists ----------

tools_list() { [[ -f "$WS_DIR/tools" ]] && grep -v -e '^#' -e '^$' "$WS_DIR/tools"; }
in_tools()   { [[ -n "$1" && -f "$WS_DIR/tools" ]] && grep -qx -- "$1" "$WS_DIR/tools"; }

ensure_lists() {
  mkdir -p "$WS_DIR"
  if [[ ! -f "$WS_DIR/tools" ]]; then
    { echo "# CLIs that keep their login in ~ and run under the workspace HOME."
      echo "# Edit freely, or: ws tool add <command>"
      for t in $DEFAULT_TOOLS; do echo "$t"; done; } > "$WS_DIR/tools"
  fi
  if [[ ! -f "$WS_DIR/shared" ]]; then
    { echo "# Files from your real ~ that every workspace home links to (never logins)."
      echo "# Edit freely, or: ws share <path relative to ~>"
      for f in $DEFAULT_SHARED; do echo "$f"; done; } > "$WS_DIR/shared"
  fi
  if [[ ! -f "$WS_DIR/config" ]]; then
    printf '# Where workspace folders live\nWS_ROOT="%s"\n' "$WS_ROOT" > "$WS_DIR/config"
  fi
}

link_shared() { # link_shared <name>
  local f home="$WS_DIR/$1/home"
  [[ -f "$WS_DIR/shared" ]] || return 0
  mkdir -p "$home"
  while IFS= read -r f; do
    [[ -z "$f" || "$f" == \#* ]] && continue
    [[ -e "$REAL_HOME/$f" || -L "$REAL_HOME/$f" ]] || continue
    [[ -e "$home/$f" || -L "$home/$f" ]] && continue
    mkdir -p "$(dirname "$home/$f")" && ln -s "$REAL_HOME/$f" "$home/$f"
  done < "$WS_DIR/shared"
}

# ---------- environment for a workspace ----------

export_env() { # export_env <name>
  local d="$WS_DIR/$1"
  export WS_WORKSPACE="$1" WS_REAL_HOME="$REAL_HOME" WS_DIR
  export GH_CONFIG_DIR="$d/gh" CLOUDSDK_CONFIG="$d/gcloud"
  # git identity comes from includeIf, never from env: stale exports would beat it.
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_SSH_COMMAND
  link_shared "$1"
}

use_private_home() { # use_private_home <name>
  export npm_config_cache="${npm_config_cache:-$REAL_HOME/.npm}"
  export HOME="$WS_DIR/$1/home"
}

find_real() { # find_real <tool>: first match on PATH that is not a shim
  local d IFS=:
  for d in $PATH; do
    [[ "$d" == "$SHIMS_DIR" || -z "$d" ]] && continue
    [[ -f "$d/$1" && -x "$d/$1" ]] && { printf '%s' "$d/$1"; return 0; }
  done
  return 1
}

# ---------- shims ----------

cmd_shims() {
  local t
  mkdir -p "$SHIMS_DIR"
  for t in $BUILTIN_SHIMS $(tools_list); do
    printf '#!/bin/sh\nexec "%s" shim "%s" "$@"\n' "$WS_SELF" "$t" > "$SHIMS_DIR/$t"
    chmod +x "$SHIMS_DIR/$t"
  done
  # drop shims for tools no longer listed
  for f in "$SHIMS_DIR"/*; do
    [[ -e "$f" ]] || continue
    t="$(basename "$f")"
    case " $BUILTIN_SHIMS " in *" $t "*) continue ;; esac
    in_tools "$t" || rm -f "$f"
  done
}

cmd_shim() { # ws shim <tool> args...  (called by the shim scripts)
  local tool="$1" real name bound=0 npxreal
  shift
  real="$(find_real "$tool")"
  if [[ "$tool" == npx ]]; then in_tools "${1:-}" && bound=1; else in_tools "$tool" && bound=1; fi
  name="$(resolve "$PWD")"

  if [[ -n "$name" ]]; then
    export_env "$name"
    [[ "$bound" == 1 ]] && use_private_home "$name"
  fi

  if [[ -n "$real" ]]; then exec "$real" "$@"; fi
  if [[ "$bound" == 1 && "$tool" != npx ]]; then
    npxreal="$(find_real npx)" || die "$tool: not found and npx is unavailable"
    exec "$npxreal" "$tool" "$@"
  fi
  die "$tool: command not found"
}

# ---------- git: native includeIf, works in every app ----------

gen_gitconfig() { # gen_gitconfig <name>
  local n="$1" f="$WS_DIR/$1/gitconfig" nm em gh
  nm="$(ws_field "$n" WS_NAME)"; em="$(ws_field "$n" WS_EMAIL)"
  : > "$f"
  [[ -n "$nm" ]] && git config -f "$f" user.name "$nm"
  [[ -n "$em" ]] && git config -f "$f" user.email "$em"
  git config -f "$f" core.sshCommand "ssh -i $WS_DIR/$n/ssh/id_ed25519 -o IdentitiesOnly=yes"
  gh="$(find_real gh || true)"
  if [[ -n "$gh" ]]; then
    git config -f "$f" credential.https://github.com.helper ""
    git config -f "$f" --add credential.https://github.com.helper "!GH_CONFIG_DIR=$WS_DIR/$n/gh $gh auth git-credential"
  fi
}

# git matches gitdir against the *real* path, so register the root both as
# typed and fully resolved (macOS /var -> /private/var, iCloud/Dropbox links...).
root_variants() { # root_variants <name>
  local root phys; root="$(ws_root "$1")"
  printf '%s\n' "$root"
  phys="$(cd "$root" 2>/dev/null && pwd -P)"
  [[ -n "$phys" && "$phys" != "$root" ]] && printf '%s\n' "$phys"
  return 0
}

git_link() { # git_link <name>: ~/.gitconfig includeIf for the workspace root
  local r
  while IFS= read -r r; do
    git config --global --replace-all "includeIf.gitdir/i:$r/.path" "$WS_DIR/$1/gitconfig"
  done < <(root_variants "$1")
}

git_unlink() {
  local r
  while IFS= read -r r; do
    git config --global --remove-section "includeIf.gitdir/i:$r/" 2>/dev/null || true
  done < <(root_variants "$1")
}

# ---------- commands ----------

ask() { # ask <prompt> <default>
  local a=""
  if is_tty; then printf '  %s%s ' "$1" "${2:+[$2]}" >&2; IFS= read -r a; fi
  printf '%s' "${a:-$2}"
}

find_dir_ci() { # existing dir under WS_ROOT matching name case-insensitively
  local d lc
  lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  for d in "$WS_ROOT"/*/; do
    [[ -d "$d" ]] || continue
    [[ "$(basename "$d" | tr '[:upper:]' '[:lower:]')" == "$lc" ]] && { printf '%s' "${d%/}"; return 0; }
  done
  return 1
}

cmd_add() {
  local name="" dir="" gname="" gemail="" a
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir) dir="$2"; shift 2 ;;
      --git-name) gname="$2"; shift 2 ;;
      --git-email) gemail="$2"; shift 2 ;;
      -*) die "add: unknown option $1" ;;
      *) name="$1"; shift ;;
    esac
  done
  [[ -n "$name" ]] || die "usage: ws add <name> [--dir path] [--git-name N] [--git-email E]"
  valid_name "$name" || die "name must be lowercase letters, digits, - or _"
  ensure_lists

  if [[ -z "$dir" ]]; then dir="$(find_dir_ci "$name" || true)"; fi
  [[ -n "$dir" ]] || dir="$WS_ROOT/$(titlecase "$name")"
  dir="${dir/#\~/$REAL_HOME}"
  mkdir -p "$dir" || die "cannot create $dir"
  dir="$(cd "$dir" && pwd)"

  local d="$WS_DIR/$name"
  mkdir -p "$d"/{home,gcloud,gh,ssh}
  chmod 700 "$d/ssh"
  printf '%s\n' "$dir" > "$d/root"
  printf 'name=%s\n' "$name" > "$dir/.workspace"

  if [[ ! -f "$d/profile.env" ]]; then
    [[ -n "$gname" ]]  || gname="$(ask "Git name for $name:" "$(git config --global user.name 2>/dev/null || true)")"
    [[ -n "$gemail" ]] || gemail="$(ask "Git email for $name:" "")"
    printf 'WS_NAME="%s"\nWS_EMAIL="%s"\n' "$gname" "$gemail" > "$d/profile.env"
  fi
  # An adopted profile may have no email yet: without one, commits silently
  # use the global identity, so ask (interactive only; doctor flags it otherwise).
  if [[ -z "$(ws_field "$name" WS_EMAIL)" ]] && is_tty; then
    gname="$(ws_field "$name" WS_NAME)"
    [[ -n "$gname" ]] || gname="$(ask "Git name for $name:" "$(git config --global user.name 2>/dev/null || true)")"
    gemail="$(ask "Git email for $name (blank = use global):" "")"
    printf 'WS_NAME="%s"\nWS_EMAIL="%s"\n' "$gname" "$gemail" > "$d/profile.env"
  fi
  if [[ ! -f "$d/ssh/id_ed25519" ]]; then
    ssh-keygen -t ed25519 -C "$name@$(hostname -s)" -f "$d/ssh/id_ed25519" -N "" >/dev/null 2>&1 \
      || warn "could not generate an SSH key"
  fi

  gen_gitconfig "$name"
  git_link "$name"
  link_shared "$name"
  cmd_shims
  echo "workspace '$name' -> $dir"
  echo "  public SSH key: $d/ssh/id_ed25519.pub"
  echo "  next: cd \"$dir\" && gh auth login"
  a="$(command -v ws_ai_write 2>/dev/null || true)"; [[ -n "$a" ]] && ws_ai_write "$name"
  return 0
}

cmd_rm() {
  local name="${1:-}" purge=0
  [[ "${2:-}" == --purge ]] && purge=1
  ws_exists "$name" || die "no such workspace: $name"
  local root; root="$(ws_root "$name")"
  git_unlink "$name"
  rm -f "$root/.workspace"
  if [[ "$purge" == 1 ]]; then rm -rf "${WS_DIR:?}/$name"; echo "removed $name and its data"
  else rm -f "$WS_DIR/$name/root"; echo "removed $name (data kept in $WS_DIR/$name; --purge to delete it)"; fi
  echo "your project files in $root were not touched"
}

cmd_which() {
  local quiet=0 p="" n
  while [[ $# -gt 0 ]]; do case "$1" in -q|--quiet) quiet=1 ;; *) p="$1" ;; esac; shift; done
  n="$(resolve "${p:-$PWD}")" || n=""
  if [[ -z "$n" ]]; then [[ "$quiet" == 1 ]] || echo "(no workspace)"; return 1; fi
  if [[ "$quiet" == 1 ]]; then printf '%s\n' "$n"; else printf '%s  %s\n' "$n" "$(ws_root "$n")"; fi
}

cmd_exec() {
  local name=""
  if [[ "${1:-}" == -w ]]; then name="$2"; shift 2; fi
  [[ "${1:-}" == -- ]] && shift
  [[ $# -gt 0 ]] || die "usage: ws exec [-w name] -- command..."
  [[ -n "$name" ]] || name="$(resolve "$PWD")" || name=""
  if [[ -n "$name" ]]; then
    ws_exists "$name" || die "no such workspace: $name"
    export_env "$name"
    in_tools "$1" && use_private_home "$name"
    [[ "$1" == npx ]] && in_tools "${2:-}" && use_private_home "$name"
  fi
  # run the real binary even if a shim shadows it
  local real; real="$(find_real "$1" || true)"
  if [[ -n "$real" ]]; then shift; exec "$real" "$@"; fi
  exec "$@"
}

proj_count() { # rough: git repos up to 4 levels below the root
  find "$1" -maxdepth 4 -name .git -prune 2>/dev/null | wc -l | tr -d ' '
}

login_gh()     { local h="$WS_DIR/$1/gh/hosts.yml"; [[ -f "$h" ]] && sed -n 's/^ *user: *//p' "$h" | head -1; }
login_convex() { [[ -f "$WS_DIR/$1/home/.convex/config.json" ]] && echo yes; }
login_vercel() { [[ -n "$(find "$WS_DIR/$1/home" -name auth.json -path '*vercel*' 2>/dev/null | head -1)" ]] && echo yes; }
login_gcloud() { [[ -n "$(find "$WS_DIR/$1/gcloud" -name 'credentials.db' -o -name 'application_default_credentials.json' 2>/dev/null | head -1)" ]] && echo yes; }

cmd_status() {
  local n cur
  cur="$(resolve "$PWD")" || cur=""
  printf '%-10s %-28s %-22s %-5s %-7s %-7s %-7s %s\n' WORKSPACE FOLDER "GIT IDENTITY" GH CONVEX VERCEL GCLOUD PROJECTS
  for n in $(ws_names); do
    printf '%-10s %-28s %-22s %-5s %-7s %-7s %-7s %s%s\n' \
      "$n" "$(ws_root "$n" | sed "s#^$REAL_HOME#~#")" "$(ws_field "$n" WS_EMAIL)" \
      "$(login_gh "$n" | cut -c1-5)" "$(login_convex "$n")" "$(login_vercel "$n")" "$(login_gcloud "$n")" \
      "$(proj_count "$(ws_root "$n")")" "$([[ "$n" == "$cur" ]] && echo '   <- here')"
  done
  echo
  echo "(blank = not logged in; run the login inside that workspace's folder)"
}

cmd_list() { local n; for n in $(ws_names); do printf '%s\t%s\n' "$n" "$(ws_root "$n")"; done; }

cmd_doctor() {
  local n bad=0 root first
  chk() { if [[ "$1" == ok ]]; then printf '  \033[32mok\033[0m   %s\n' "$2"; else printf '  \033[31mFAIL\033[0m %s\n' "$2"; bad=1; fi; }
  echo "ws $WS_VERSION  data: $WS_DIR  root: $WS_ROOT"
  first="$(command -v gh 2>/dev/null || true)"
  if [[ -z "$first" ]]; then chk fail "gh not installed (skipping shim check)"
  elif [[ "$first" == "$SHIMS_DIR/gh" ]]; then chk ok "shims are first on PATH"
  else chk fail "PATH: 'gh' resolves to $first, not the shim. Put \"$SHIMS_DIR\" first (eval \"\$(ws init zsh)\" in your rc)."; fi
  # What an AI agent's non-interactive login shell would resolve (nothing sourced from .zshrc).
  local sh lg; sh="${SHELL:-/bin/zsh}"
  lg="$("$sh" -lc 'command -v gh' 2>/dev/null | tail -1)"
  if [[ -z "$lg" ]]; then :
  elif [[ "$lg" == "$SHIMS_DIR/gh" ]]; then chk ok "login shell ($(basename "$sh") -lc) resolves gh to the shim"
  else chk fail "login shell resolves gh to $lg, not the shim: run ws setup-shell"; fi
  for n in $(ws_names); do
    echo "workspace $n"
    root="$(ws_root "$n")"
    [[ -d "$root" ]] && chk ok "folder $root" || chk fail "folder missing: $root"
    [[ -f "$root/.workspace" ]] && chk ok "marker present" || chk fail "marker missing in $root (ws add $n --dir \"$root\")"
    [[ -f "$WS_DIR/$n/ssh/id_ed25519" ]] && chk ok "ssh key" || chk fail "ssh key missing"
    [[ -n "$(ws_field "$n" WS_EMAIL)" ]] && chk ok "git email $(ws_field "$n" WS_EMAIL)" || chk fail "no git email (edit $WS_DIR/$n/profile.env, then ws add $n)"
    [[ "$(git config --global --get "includeIf.gitdir/i:$root/.path" 2>/dev/null)" == "$WS_DIR/$n/gitconfig" ]] \
      && chk ok "git includeIf linked" || chk fail "git includeIf not linked (run: ws add $n)"
  done
  return "$bad"
}

cmd_tool() {
  case "${1:-list}" in
    add) [[ -n "${2:-}" ]] || die "usage: ws tool add <command>"
         ensure_lists; in_tools "$2" || echo "$2" >> "$WS_DIR/tools"; cmd_shims; echo "$2 now runs under the workspace HOME" ;;
    rm)  [[ -n "${2:-}" ]] || die "usage: ws tool rm <command>"
         grep -vx -- "$2" "$WS_DIR/tools" > "$WS_DIR/tools.tmp"; mv "$WS_DIR/tools.tmp" "$WS_DIR/tools"; cmd_shims; echo "removed $2" ;;
    list) tools_list ;;
    *) die "usage: ws tool add|rm|list [command]" ;;
  esac
}

cmd_share() {
  [[ -n "${1:-}" ]] || die "usage: ws share <path relative to ~>"
  ensure_lists
  grep -qx -- "$1" "$WS_DIR/shared" || echo "$1" >> "$WS_DIR/shared"
  local n; for n in $(ws_names); do link_shared "$n"; done
  echo "shared: $1"
}

cmd_init() {
  local sh="${1:-zsh}"
  cat <<EOF
export WS_DIR="$WS_DIR"
case ":\$PATH:" in *":$SHIMS_DIR:"*) PATH="\${PATH//:$SHIMS_DIR/}"; PATH="\${PATH/#$SHIMS_DIR:/}" ;; esac
export PATH="$SHIMS_DIR:\$PATH"
EOF
  if [[ "$sh" == zsh ]]; then echo 'typeset -U path PATH'; fi
  cat <<'EOF'
_ws_hook() {
  local d="$PWD" n=""
  while :; do
    if [[ -f "$d/.workspace" ]]; then n="$(sed -n 's/^name=//p' "$d/.workspace" | head -1)"; [[ -d "$WS_DIR/$n" ]] && break; n=""; fi
    [[ "$d" == / || -z "$d" ]] && break; d="${d%/*}"; [[ -z "$d" ]] && d=/
  done
  [[ "$n" == "${WS_WORKSPACE:-}" ]] && return 0
  if [[ -n "$n" ]]; then
    export WS_WORKSPACE="$n" GH_CONFIG_DIR="$WS_DIR/$n/gh" CLOUDSDK_CONFIG="$WS_DIR/$n/gcloud"
  else
    unset WS_WORKSPACE GH_CONFIG_DIR CLOUDSDK_CONFIG
  fi
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_SSH_COMMAND
  _ws_prompt
}
_ws_prompt() {
  : "${_WS_BASE_PS1:=$PS1}"
  if [[ -n "${WS_WORKSPACE:-}" ]]; then PS1="($WS_WORKSPACE) $_WS_BASE_PS1"; else PS1="$_WS_BASE_PS1"; fi
}
# `<name>` jumps to a workspace folder: e.g. `asmbly`
ws_go() { local r; r="$(cat "$WS_DIR/$1/root" 2>/dev/null)" && cd "$r"; }
EOF
  if [[ "$sh" == zsh ]]; then
    echo 'autoload -Uz add-zsh-hook; add-zsh-hook chpwd _ws_hook; _ws_hook'
  else
    echo 'case ";${PROMPT_COMMAND:-};" in *";_ws_hook;"*) ;; *) PROMPT_COMMAND="_ws_hook${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;; esac'
  fi
  local n
  for n in $(ws_names); do printf "alias %s='ws_go %s'\n" "$n" "$n"; done
}

# ---------- shell setup + migration ----------

block_set() { # block_set <file> <start> <end> <body> [append=0|1]
  local f="$1" s="$2" e="$3" body="$4" app="${5:-0}" tmp
  touch "$f"; tmp="$(mktemp)"
  awk -v s="$s" -v e="$e" '$0==s{k=1;next} $0==e{k=0;next} !k{print}' "$f" > "$tmp"
  if [[ "$app" == 1 ]]; then { cat "$tmp"; printf '\n%s\n%s\n%s\n' "$s" "$body" "$e"; } > "$f"
  else { printf '%s\n%s\n%s\n\n' "$s" "$body" "$e"; cat "$tmp"; } > "$f"; fi
  rm -f "$tmp"
}

short() { printf '%s' "${1/#$REAL_HOME/\$HOME}"; }

# Installs ws to ~/.local/bin and wires PATH + hooks. PATH-only blocks go into the
# files that non-interactive and login shells read (AI agents), appended so they
# land after Homebrew's own PATH changes.
cmd_setup_shell() {
  local bin="$REAL_HOME/.local/bin" zd="${ZDOTDIR:-$REAL_HOME}" pathline S E
  S="# >>> ws >>>"; E="# <<< ws <<<"
  mkdir -p "$bin"; ensure_lists
  if [[ "$WS_SELF" != "$bin/ws" ]]; then cp "$WS_SELF" "$bin/ws"; chmod +x "$bin/ws"; fi
  "$bin/ws" shims
  pathline="export PATH=\"$(short "$SHIMS_DIR"):$(short "$bin"):\$PATH\""

  # drop the legacy switcher
  if [[ -f "$zd/.zshrc" ]]; then
    grep -v -E '^source ~/workspace-switcher\.sh$' "$zd/.zshrc" > "$zd/.zshrc.tmp" && mv "$zd/.zshrc.tmp" "$zd/.zshrc"
  fi
  [[ -f "$REAL_HOME/workspace-switcher.sh" ]] && mv "$REAL_HOME/workspace-switcher.sh" "$REAL_HOME/workspace-switcher.sh.legacy"

  case "$(basename "${SHELL:-zsh}")" in
    bash)
      block_set "$REAL_HOME/.bashrc"       "$S" "$E" "$pathline"$'\n''eval "$(ws init bash)"' 1
      block_set "$REAL_HOME/.bash_profile" "$S" "$E" "$pathline" 1 ;;
    *)
      block_set "$zd/.zshenv"   "$S" "$E" "$pathline" 1
      block_set "$zd/.zprofile" "$S" "$E" "$pathline" 1
      # appended: must run after any later `brew shellenv` / PATH edits in .zshrc
      block_set "$zd/.zshrc"    "$S" "$E" "$pathline"$'\n''eval "$(ws init zsh)"' 1 ;;
  esac
  echo "ws installed at $bin/ws; shell blocks updated (open a new terminal)"
}

# Adopt workspaces created by the old env.sh layout: match each profile to a folder.
cmd_migrate() {
  local d n dir moved=0
  ensure_lists
  for d in "$WS_DIR"/*/; do
    n="$(basename "$d")"
    [[ "$n" == shims ]] && continue
    [[ -f "${d}root" ]] && continue
    [[ -f "${d}env.sh" || -f "${d}profile.env" ]] || continue
    valid_name "$n" || continue
    dir="$(find_dir_ci "$n" || true)"
    if [[ -z "$dir" ]]; then warn "no folder for '$n' under $WS_ROOT; run: ws add $n --dir <folder>"; continue; fi
    echo "adopting '$n' -> $dir"
    cmd_add "$n" --dir "$dir" >/dev/null || warn "could not adopt $n"
    [[ -f "${d}env.sh" ]] && mv "${d}env.sh" "${d}env.sh.legacy"
    moved=$((moved + 1))
  done
  echo "migrated $moved workspace(s); your existing logins were kept"
  cmd_setup_shell
}

usage() { sed -n '2,15p' "$WS_SELF" | sed 's/^# \{0,1\}//'; }

main() {
  local c="${1:-status}"
  [[ $# -gt 0 ]] && shift
  case "$c" in
    add) cmd_add "$@" ;;
    rm|remove) cmd_rm "$@" ;;
    list|ls) cmd_list ;;
    status|st) cmd_status ;;
    doctor) cmd_doctor ;;
    which) cmd_which "$@" ;;
    exec|x) cmd_exec "$@" ;;
    shim) cmd_shim "$@" ;;
    shims) cmd_shims ;;
    tool) cmd_tool "$@" ;;
    share) cmd_share "$@" ;;
    init) cmd_init "$@" ;;
    setup-shell) cmd_setup_shell ;;
    migrate) cmd_migrate ;;
    version|--version) echo "ws $WS_VERSION" ;;
    help|-h|--help) usage ;;
    *) usage >&2; exit 2 ;;
  esac
}

main "$@"
