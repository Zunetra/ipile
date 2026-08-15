#!/usr/bin/env bash
# Global git hooks and the two shell helpers. Sourced by the registry.

MODULE_TITLE="Hook System & Shell Helpers"
MODULE_EMOJI="🪝"
MODULE_DESC="Global hooks, gclone, gitprofile"
MODULE_NEEDS="git-install"

GIT_HOOKS_DIR="${HOME}/.git-hooks"

# The hook types that get a bare passthrough. core.hooksPath is global:
# once it is set git stops reading .git/hooks at all, so every type we do
# not install and chain is a type that never runs again on this machine.
# That is what silently breaks husky, lefthook and commitlint, so the
# list below exists to keep them working.
GIT_HOOKS_PASSTHROUGH="commit-msg prepare-commit-msg post-commit post-merge post-checkout pre-rebase"

# === Contract

describe() {
  ui_info "Writes ~/.git-hooks and points git's global core.hooksPath at it."
  ui_info "pre-commit sets this repo's identity the first time you commit,"
  ui_info "reading ~/.gitidentities and using the remote's SSH alias when it"
  ui_info "can, asking you when it cannot."
  ui_info "pre-push prints which identity is about to push."
  ui_info "Both then run the repository's own hook of the same name if it has"
  ui_info "one, so husky, lefthook and commitlint keep working."
  ui_info "The other common hook types get a passthrough for the same reason:"
  ui_info "  ${GIT_HOOKS_PASSTHROUGH}"
  ui_info "Finally it adds gclone and gitprofile to every shell rc file you"
  ui_info "have, so both are available in bash and zsh."
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
#!/usr/bin/env bash
# Installed by ipile. core.hooksPath is global, so a hook type we do not
# install here would never run again in any repository on this machine.
# --git-dir, not --git-path hooks: the latter honours core.hooksPath and
# would resolve straight back to this file.
LOCAL_HOOK="\$(git rev-parse --git-dir 2>/dev/null || echo .git)/hooks/${name}"
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
    ui_info "Add gclone and gitprofile by hand from ${IPILE_LIB}/assets/shell/"
    return 0
  fi

  for rc in $(fs_shell_rcs); do
    added=0
    if { printf '\n'; cat "${IPILE_LIB}/assets/shell/gclone.sh"; } | fs_append_once "$rc" "gclone()"; then
      ui_ok "gclone() added to ${rc}"
      added=1
    fi
    if { printf '\n'; cat "${IPILE_LIB}/assets/shell/gitprofile.sh"; } | fs_append_once "$rc" "gitprofile()"; then
      ui_ok "gitprofile() added to ${rc}"
      added=1
    fi
    [ "$added" -eq 0 ] && ui_info "${rc} already has both helpers."
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
    if fs_has_marker "$rc" "gclone()" && fs_has_marker "$rc" "gitprofile()"; then
      found=0
      break
    fi
  done
  if [ "$found" -ne 0 ]; then
    ui_warn "gclone and gitprofile are not in any rc file yet."
    return 1
  fi
  return 0
}
