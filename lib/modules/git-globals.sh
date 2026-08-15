#!/usr/bin/env bash
# Global git configuration: behaviour, colours and aliases. Sourced by
# the registry.

MODULE_TITLE="Git Globals"
MODULE_EMOJI="⚙️"
MODULE_DESC="Git config and 11 aliases"
MODULE_NEEDS="git-install"

# === Data
#
# One key/value pair per line, key and value separated by the first tab.
# A tab is used because several values contain spaces and bash 3.2 has no
# associative arrays.
git_globals_pairs() {
  printf '%s\n' \
    "init.defaultBranch	main" \
    "core.editor	code --wait" \
    "core.autocrlf	false" \
    "core.safecrlf	warn" \
    "pull.rebase	true" \
    "rebase.autoStash	true" \
    "push.default	current" \
    "push.autoSetupRemote	true" \
    "fetch.prune	true" \
    "merge.conflictstyle	diff3" \
    "diff.colorMoved	zebra" \
    "rerere.enabled	true" \
    "color.ui	auto" \
    "help.autocorrect	10" \
    "log.date	iso"
}

# The 11 aliases. The old dev-setup.sh shipped only 10 and dropped
# whoami; this list is the union and is now the only copy.
git_globals_aliases() {
  printf '%s\n' \
    "alias.lg	log --oneline --graph --all --decorate" \
    "alias.ll	log --pretty=format:'%C(yellow)%h%Creset %s %C(dim)(%ar)%Creset' --decorate" \
    "alias.st	status --short --branch" \
    "alias.co	checkout" \
    "alias.br	branch --sort=-committerdate" \
    "alias.undo	reset HEAD~1 --mixed" \
    "alias.unstage	reset HEAD --" \
    "alias.wip	!git add -A && git commit -m 'wip'" \
    "alias.unwip	reset HEAD~1 --mixed" \
    "alias.aliases	config --get-regexp ^alias\\." \
    "alias.whoami	!git config user.name && git config user.email"
}

# === Contract

describe() {
  ui_info "Sets git's global behaviour: rebase on pull, autostash, prune on"
  ui_info "fetch, push the current branch and create the remote branch,"
  ui_info "diff3 conflict markers, zebra moved-line colouring and rerere."
  ui_info "Sets core.editor to 'code --wait' and log.date to iso."
  ui_info "Installs 11 aliases: lg, ll, st, co, br, undo, unstage, wip,"
  ui_info "unwip, aliases and whoami."
  ui_info "Everything is written to ~/.gitconfig with git config --global,"
  ui_info "so nothing here is hidden in a file this tool owns."
}

detect() {
  local total=0
  local set_count=0
  local line key value current
  local all

  # A pipe would run the loop in a subshell and lose the counters, so the
  # list is materialised first and fed in as a here-document.
  all="$(git_globals_pairs; git_globals_aliases)"

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="${line%%	*}"
    value="${line#*	}"
    total=$((total + 1))
    current="$(git config --global --get "$key" 2>/dev/null)"
    [ "$current" = "$value" ] && set_count=$((set_count + 1))
  done <<EOF
$all
EOF

  [ "$set_count" -eq 0 ] && return 1
  [ "$set_count" -eq "$total" ] && return 0
  return 2
}

apply() {
  local line key value
  local all
  all="$(git_globals_pairs; git_globals_aliases)"

  ui_info "Applying git globals and aliases."

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="${line%%	*}"
    value="${line#*	}"
    run git config --global "$key" "$value" || return 1
  done <<EOF
$all
EOF

  ui_ok "Git globals, colours and 11 aliases applied."
  return 0
}

verify() {
  local missing=""
  local line key value current
  local all
  all="$(git_globals_pairs; git_globals_aliases)"

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="${line%%	*}"
    value="${line#*	}"
    current="$(git config --global --get "$key" 2>/dev/null)"
    [ "$current" = "$value" ] || missing="${missing} ${key}"
  done <<EOF
$all
EOF

  if [ -n "$missing" ]; then
    ui_err "Not set as expected:${missing}"
    return 1
  fi
  return 0
}
