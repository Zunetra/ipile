#!/usr/bin/env bash
# The one place that knows where a user's projects live. Asked once, by
# whichever module needs it first -- guard or cleanup -- and shared from
# then on through state, so the two never ask the same question twice or
# land on different answers.

# projects_root <varname>. Eval-assigns into the caller's variable rather
# than printing on stdout: callers also call ui_info before this returns,
# and ui_info writes to stdout too, which would otherwise fold straight
# into a $(...) capture of this function's output.
projects_root() {
  local varname="$1"
  local __root=""

  __root="$(state_get projects_root 2>/dev/null || true)"
  if [ -n "$__root" ]; then
    eval "${varname}=\"\${__root}\""
    return 0
  fi

  # Nothing saved, no default on disk, and nobody to ask under --yes:
  # not having a projects folder yet is not a failure, just nothing to
  # act on yet.
  if [ "${IPILE_ASSUME_YES:-0}" = "1" ] && [ ! -d "$HOME/Projects" ]; then
    return 1
  fi

  ui_info "This works best from one folder that holds all your projects."
  ui_info "If yours are not together yet, move them under one first, e.g. ~/Projects."
  ui_info "Then, in another terminal: cd into that folder and run 'pwd', and paste the result below."
  ui_ask_valid "Where do your projects live?" "$HOME/Projects" __root \
    valid_dir "That is not a directory. cd into your projects folder, run pwd, and paste the result." || return 1

  state_set projects_root "$__root"
  eval "${varname}=\"\${__root}\""
}
