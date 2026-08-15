#!/usr/bin/env bash
# Global git hooks and the shell helpers. Sourced by the registry.

MODULE_TITLE="Hook System & Shell Helpers"
MODULE_EMOJI="🪝"
MODULE_DESC="Global hooks, gclone, gremote, gitprofile"
MODULE_NEEDS="git-install"

GIT_HOOKS_DIR="${HOME}/.git-hooks"

# Shell helpers, as "file:marker" pairs. gitidentity is first because it
# holds the functions the other two call.
GIT_SHELL_HELPERS="gitidentity:_ipile_identities_file() gclone:gclone() gremote:gremote() gitprofile:gitprofile()"

# The hook types that get a bare passthrough. core.hooksPath is global:
# once it is set git stops reading .git/hooks at all, so every type we do
# not install and chain is a type that never runs again on this machine.
# That is what silently breaks husky, lefthook and commitlint, so the
# list below exists to keep them working.
# Everything in IPILE_GIT_HOOKS except the two that carry real logic and
# ship as assets. Derived, so the two lists cannot disagree.
GIT_HOOKS_PASSTHROUGH="$(printf '%s\n' $IPILE_GIT_HOOKS | grep -vxE 'pre-commit|pre-push' | tr '\n' ' ')"

# Two client-side hooks are deliberately left out, and the reason is
# measured rather than assumed. reference-transaction fired 202 times
# during a single fetch of 100 refs, and twice per commit. Even with the
# cheap passthrough below, that is roughly 750ms added to a fetch that
# otherwise takes 37ms. post-index-change is the same shape, once per
# index write. The cost is constant and paid by everyone; the benefit is
# a hook almost nobody defines. Anyone who needs them can unset
# core.hooksPath for that repository.
#
# The server-side hooks (pre-receive, update, post-receive, post-update,
# proc-receive) never run on a developer's machine, and fsmonitor-watchman
# is selected by core.fsmonitor rather than found in the hooks directory.

# === Contract

describe() {
  ui_info "Writes ~/.git-hooks and points git's global core.hooksPath at it."
  ui_info "pre-commit sets this repo's identity the first time you commit,"
  ui_info "reading ~/.gitidentities and using the remote's SSH alias when it"
  ui_info "can, asking you when it cannot."
  ui_info "pre-push prints which identity is about to push, and warns when"
  ui_info "the commits going out were authored by a different one."
  ui_info "Both then run the repository's own hook of the same name if it has"
  ui_info "one, so husky, lefthook and commitlint keep working."
  ui_info "The other common hook types get a passthrough for the same reason:"
  ui_info "  ${GIT_HOOKS_PASSTHROUGH}"
  ui_info "Finally it adds gclone, gremote and gitprofile to every shell rc"
  ui_info "file you have, so all three are available in bash and zsh."
}

detect() {
  local total=0
  local have=0
  local name rc

  total=$((total + 1))
  [ "$(git config --global --get core.hooksPath 2>/dev/null)" = "$GIT_HOOKS_DIR" ] && have=$((have + 1))

  total=$((total + 1))
  fs_assets_match "hooks/pre-commit" "${GIT_HOOKS_DIR}/pre-commit" && have=$((have + 1))

  total=$((total + 1))
  fs_assets_match "hooks/pre-push" "${GIT_HOOKS_DIR}/pre-push" && have=$((have + 1))

  for name in $GIT_HOOKS_PASSTHROUGH; do
    total=$((total + 1))
    [ -x "${GIT_HOOKS_DIR}/${name}" ] && have=$((have + 1))
  done

  # The helpers count as present once any rc file has them.
  total=$((total + 2))
  for rc in $(fs_shell_rcs 2>/dev/null); do
    fs_has_marker "$rc" "gclone()" && { have=$((have + 1)); break; }
  done
  total=$((total + 1))
  for rc in $(fs_shell_rcs 2>/dev/null); do
    fs_has_marker "$rc" "gremote()" && { have=$((have + 1)); break; }
  done
  for rc in $(fs_shell_rcs 2>/dev/null); do
    fs_has_marker "$rc" "gitprofile()" && { have=$((have + 1)); break; }
  done

  [ "$have" -eq 0 ] && return 1
  [ "$have" -eq "$total" ] && return 0
  return 2
}

apply() {
  local name rc added

  fs_mkdir "$GIT_HOOKS_DIR" 755 || return 1

  ui_info "Writing ${GIT_HOOKS_DIR}/pre-commit"
  fs_install_asset "hooks/pre-commit" "${GIT_HOOKS_DIR}/pre-commit" 755 || return 1

  ui_info "Writing ${GIT_HOOKS_DIR}/pre-push"
  fs_install_asset "hooks/pre-push" "${GIT_HOOKS_DIR}/pre-push" 755 || return 1

  # Four lines each, so they are generated rather than shipped as assets.
  for name in $GIT_HOOKS_PASSTHROUGH; do
    fs_write "${GIT_HOOKS_DIR}/${name}" 755 <<EOF || return 1
#!/bin/sh
# Installed by ipile. core.hooksPath is global, so a hook type we do not
# install here would never run again in any repository on this machine.
#
# sh rather than bash, and the git dir resolved by inspection rather than
# by asking git, because this runs on every hook of every git command.
# Shelling out to 'git rev-parse --git-dir' here doubled the wall time of
# a commit when measured. Hooks run from the top of the working tree, so
# .git is a directory in the common case, a file holding a gitdir line in
# a worktree or submodule, and absent in a bare repo, which is the only
# case that still has to ask.
#
# --git-dir, not --git-path hooks: the latter honours core.hooksPath and
# would resolve straight back to this file.
if [ -d .git ]; then
  d=.git
elif [ -f .git ]; then
  d=\$(sed -n 's/^gitdir: //p' .git)
else
  d=\$(git rev-parse --git-dir 2>/dev/null || echo .git)
fi
LOCAL_HOOK="\${d}/hooks/${name}"
[ -x "\$LOCAL_HOOK" ] && [ ! "\$LOCAL_HOOK" -ef "\$0" ] && exec "\$LOCAL_HOOK" "\$@"
exit 0
EOF
  done
  ui_ok "Hooks written: pre-commit, pre-push and ${GIT_HOOKS_PASSTHROUGH}"

  run git config --global core.hooksPath "$GIT_HOOKS_DIR" || return 1
  ui_ok "core.hooksPath points at ${GIT_HOOKS_DIR}"

  # === Shell helpers

  fs_warn_unsupported_shells

  if ! fs_shell_rcs >/dev/null 2>&1; then
    ui_warn "No ~/.zshrc, ~/.bashrc or ~/.bash_profile found."
    ui_info "Add the helpers by hand from ${IPILE_LIB}/assets/shell/"
    return 0
  fi

  local helper file marker
  for rc in $(fs_shell_rcs); do
    added=0
    for helper in $GIT_SHELL_HELPERS; do
      file="${helper%%:*}"
      marker="${helper#*:}"
      if { printf '\n'; cat "${IPILE_LIB}/assets/shell/${file}.sh"; } | fs_append_once "$rc" "$marker"; then
        ui_ok "${marker} added to ${rc}"
        added=1
      fi
    done
    [ "$added" -eq 0 ] && ui_info "${rc} already has every helper."
  done

  ui_info "Open a new shell, or source your rc file, to use them."
  return 0
}

verify() {
  local name

  if [ "$(git config --global --get core.hooksPath 2>/dev/null)" != "$GIT_HOOKS_DIR" ]; then
    ui_err "core.hooksPath is not ${GIT_HOOKS_DIR}"
    return 1
  fi

  for name in pre-commit pre-push $GIT_HOOKS_PASSTHROUGH; do
    if [ ! -x "${GIT_HOOKS_DIR}/${name}" ]; then
      ui_err "Missing or not executable: ${GIT_HOOKS_DIR}/${name}"
      return 1
    fi
  done

  local found=1
  local rc
  for rc in $(fs_shell_rcs 2>/dev/null); do
    if fs_has_marker "$rc" "gclone()" && fs_has_marker "$rc" "gremote()" &&
       fs_has_marker "$rc" "gitprofile()" && fs_has_marker "$rc" "_ipile_identities_file()"; then
      found=0
      break
    fi
  done
  if [ "$found" -ne 0 ]; then
    ui_warn "The shell helpers are not in any rc file yet."
    return 1
  fi
  return 0
}
