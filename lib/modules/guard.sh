#!/usr/bin/env bash
# Installs dev-guard, hardens npm's supply chain settings, and offers a
# daily sweep. The scanner itself lives once, in lib/assets/bin/dev-guard,
# and is installed unmodified so a machine that later drops ipile keeps a
# working `dev-guard` on its PATH.

MODULE_TITLE="Supply Chain Guard"
MODULE_EMOJI="🛡"
MODULE_DESC="dev-guard scanner, npm hardening, daily sweep"
MODULE_NEEDS="node"

DEV_GUARD_BIN="$HOME/.local/bin/dev-guard"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SYSTEMD_TIMER_WANTS="${SYSTEMD_USER_DIR}/timers.target.wants/dev-guard.timer"

describe() {
  cat <<'TXT'
  Installs dev-guard and hardens the settings that let a compromised
  package run code on install.

    - dev-guard, the backdoor scanner and cleaner, to ~/.local/bin
    - minimum-release-age=1440 in ~/.npmrc, unless something is already set
    - runs one full scan of your projects now, so you know where you stand
    - offers a daily sweep (systemd, Linux only) that reports findings by
      showing as failed -- opt in, never enabled silently

  Scanning never changes a file. Cleaning what it finds is a separate
  question this always asks by name, even when you passed --yes to skip
  everything else.
TXT
}

# === Shared helpers

guard_npmrc_hardened() {
  grep -qE '^(minimum-release-age|minimumReleaseAge)' "$HOME/.npmrc" 2>/dev/null
}

guard_harden_npmrc() {
  guard_npmrc_hardened && return 0
  printf 'minimum-release-age=1440\n' | fs_append_once "$HOME/.npmrc" "minimum-release-age"
  ui_ok "Set minimum-release-age=1440 in ~/.npmrc"
}

guard_timer_wanted() {
  [ "$(state_get guard_timer 2>/dev/null || printf 'off')" = "on" ]
}

guard_timer_installed() {
  fs_assets_match "systemd/dev-guard.service" "${SYSTEMD_USER_DIR}/dev-guard.service" \
    && fs_assets_match "systemd/dev-guard.timer" "${SYSTEMD_USER_DIR}/dev-guard.timer" \
    && [ -L "$SYSTEMD_TIMER_WANTS" ]
}

# The projects_root prompt itself lives in lib/core/projects.sh, shared
# with cleanup so the two modules ask once between them, not once each.

# guard_install_timer. Copies the units and enables them. A failure to
# enable is reported, not fatal: the units are still on disk, correct,
# and one command away from working.
guard_install_timer() {
  fs_mkdir "$SYSTEMD_USER_DIR" 755
  fs_install_asset "systemd/dev-guard.service" "${SYSTEMD_USER_DIR}/dev-guard.service"
  fs_install_asset "systemd/dev-guard.timer" "${SYSTEMD_USER_DIR}/dev-guard.timer"

  if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
    ui_dry "systemctl --user daemon-reload && enable --now dev-guard.timer"
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload 2>/dev/null
    if systemctl --user enable --now dev-guard.timer 2>/dev/null; then
      ui_ok "Daily sweep enabled. Check with: systemctl --user list-timers dev-guard.timer"
      return 0
    fi
  fi

  ui_warn "Units installed, but the timer could not be enabled here."
  ui_info "Enable it yourself: systemctl --user enable --now dev-guard.timer"
  return 0
}

detect() {
  local ok=1
  fs_assets_match "bin/dev-guard" "$DEV_GUARD_BIN" || ok=0
  guard_npmrc_hardened || ok=0
  if guard_timer_wanted; then
    guard_timer_installed || ok=0
  fi

  [ "$ok" -eq 1 ] && return 0
  fs_assets_match "bin/dev-guard" "$DEV_GUARD_BIN" && return 2
  return 1
}

apply() {
  guard_harden_npmrc

  fs_install_asset "bin/dev-guard" "$DEV_GUARD_BIN" 755
  ui_ok "dev-guard installed to ${DEV_GUARD_BIN}"

  local root
  if ! projects_root root; then
    ui_info "No projects folder yet, so there is nothing to scan. Run 'ipile guard' again once you have one."
    return 0
  fi

  echo ""
  ui_info "Running a full sweep of ${root} ..."
  bash "${IPILE_LIB}/assets/bin/dev-guard" --all --path "$root"
  local status=$?

  if [ "$status" -eq 2 ]; then
    ui_err "dev-guard could not run against ${root}"
    return 1
  fi

  if [ "$status" -ne 0 ]; then
    if [ "${IPILE_ASSUME_YES:-0}" = "1" ]; then
      ui_warn "Findings above. Not cleaning under --yes."
      ui_info "Clean them by hand: dev-guard --clean --yes --path ${root}"
    else
      echo ""
      if ui_confirm "Clean what was found?" "n"; then
        bash "${IPILE_LIB}/assets/bin/dev-guard" --scan --heuristics --clean --yes --path "$root"
      fi
    fi
  fi

  echo ""
  if [ "$IPILE_OS" = "mac" ]; then
    ui_info "The daily sweep is systemd-only for now. Run 'dev-guard --all' by hand on whatever schedule you like."
    state_set guard_timer "off"
  elif [ "${IPILE_ASSUME_YES:-0}" = "1" ]; then
    # A non-interactive run never grows a background job on its own.
    state_set guard_timer "off"
  elif ui_confirm "Also run a sweep automatically, once a day? (systemd user timer, ~/Projects only)" "n"; then
    guard_install_timer
    state_set guard_timer "on"
  else
    state_set guard_timer "off"
  fi

  return 0
}

verify() {
  fs_assets_match "bin/dev-guard" "$DEV_GUARD_BIN" || return 1
  guard_npmrc_hardened || return 1
  if guard_timer_wanted; then
    guard_timer_installed || return 1
  fi
  return 0
}
