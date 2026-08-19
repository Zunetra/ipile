#!/usr/bin/env bash
# Global git configuration: behaviour, colours and aliases. Sourced by
# the registry.

MODULE_TITLE="Git Globals"
MODULE_EMOJI="⚙️"
MODULE_DESC="Git config and 11 aliases"
MODULE_NEEDS="git-install"

# === Version gate
#
# ipile installs onto whatever git the distro shipped, and Ubuntu 22.04 is
# still on 2.34. A key git does not understand is not ignored: it fails at
# the moment you need it, during a merge or a rebase, which is the worst
# possible time to discover a config file is wrong. So anything newer than
# roughly 2020 is gated and falls back.

# git_globals_atleast <major> <minor>. True when the installed git is at
# least that version.
git_globals_atleast() {
  local ver major minor
  ver="$(git --version 2>/dev/null | sed -n 's/^git version \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p')"
  [ -n "$ver" ] || return 1
  major="${ver%% *}"
  minor="${ver##* }"
  [ "$major" -gt "$1" ] && return 0
  [ "$major" -eq "$1" ] && [ "$minor" -ge "$2" ]
}

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
    "pull.rebase	false" \
    "rebase.autoStash	true" \
    "merge.autoStash	true" \
    "push.default	current" \
    "push.autoSetupRemote	true" \
    "push.followTags	true" \
    "fetch.prune	true" \
    "fetch.parallel	0" \
    "diff.colorMoved	zebra" \
    "diff.algorithm	histogram" \
    "diff.mnemonicPrefix	true" \
    "rerere.enabled	true" \
    "rerere.autoUpdate	true" \
    "commit.verbose	true" \
    "branch.sort	-committerdate" \
    "tag.sort	version:refname" \
    "column.ui	auto" \
    "transfer.fsckObjects	true" \
    "fetch.fsckObjects	true" \
    "color.ui	auto" \
    "log.date	iso"

  # zdiff3 is diff3 with the lines both sides share hoisted out of the
  # conflict, so the markers cover only what actually disagrees.
  if git_globals_atleast 2 35; then
    printf '%s\n' "merge.conflictstyle	zdiff3"
  else
    printf '%s\n' "merge.conflictstyle	diff3"
  fi

  # 'prompt' asks before running the correction. A number is a countdown
  # after which git runs it on your behalf, which is the one behaviour
  # this tool should not ship: 0 still suggests, it just will not act.
  if git_globals_atleast 2 42; then
    printf '%s\n' "help.autocorrect	prompt"
  else
    printf '%s\n' "help.autocorrect	0"
  fi

  # Rebasing a stack of branches moves every branch in it, instead of
  # leaving the intermediate ones on abandoned commits.
  git_globals_atleast 2 38 && printf '%s\n' "rebase.updateRefs	true"

  # The built-in filesystem monitor, and the bundle of large-repo index
  # settings that goes with it.
  git_globals_atleast 2 37 && printf '%s\n' "core.fsmonitor	true"
  git_globals_atleast 2 24 && printf '%s\n' "feature.manyFiles	true"

  return 0
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
  ui_info "Sets git's global behaviour: autostash on rebase and merge, prune"
  ui_info "on fetch, push the current branch and create the remote branch,"
  ui_info "push annotated tags with it, three-way conflict markers, zebra"
  ui_info "moved-line colouring, histogram diffs and rerere with autoupdate."
  ui_info "Rejects malformed objects on fetch and push (fsckObjects)."
  ui_info "Shows the diff while you write a commit message, sorts branches"
  ui_info "by date and tags by version, and lists them in columns."
  ui_info "Sets core.editor to 'code --wait' and log.date to iso."
  ui_info "A mistyped command is suggested, never run for you."
  ui_info "Anything needing a newer git than this machine has is skipped or"
  ui_info "falls back, so an older distro gets a working config, not a broken"
  ui_info "one. This git is $(git --version 2>/dev/null | sed 's/^git version //')."
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
  all="$(
    git_globals_pairs
    git_globals_aliases
  )"

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
  all="$(
    git_globals_pairs
    git_globals_aliases
  )"

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
  all="$(
    git_globals_pairs
    git_globals_aliases
  )"

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
