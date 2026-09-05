#!/usr/bin/env bash
# Installs dev-cleanup and lets the user pick manual or automatic. The
# scanner lives once, in lib/assets/bin/dev-cleanup, same discipline as
# guard: dry run first, an explicit yes before anything is deleted.
#
# The scheduled unit's content depends on per-machine values (the age
# threshold, the interval, the projects root), so unlike guard's static
# systemd assets, this module generates the unit text itself and compares
# it in memory in detect() -- no shipped file to diff against.

MODULE_TITLE="Automated Cleanup"
MODULE_EMOJI="🧹"
MODULE_DESC="Reclaim disk from caches, build artifacts, agent sessions"
MODULE_NEEDS=""

DEV_CLEANUP_BIN="$HOME/.local/bin/dev-cleanup"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
CLEANUP_SERVICE="${SYSTEMD_USER_DIR}/dev-cleanup.service"
CLEANUP_TIMER="${SYSTEMD_USER_DIR}/dev-cleanup.timer"
CLEANUP_TIMER_WANTS="${SYSTEMD_USER_DIR}/timers.target.wants/dev-cleanup.timer"

describe() {
  cat <<'TXT'
  Installs dev-cleanup, then asks two questions: run it yourself or on a
  schedule, and how far back "untouched" reaches.

    - Runs once immediately either way, after listing what it would
      remove and asking before it deletes anything
    - Automatic mode (systemd, Linux only) needs your say-so twice: once
      to enable the timer, once more only if lingering (running while
      logged out) needs sudo
    - The age threshold is saved, so answering it once means a later
      --yes reuses it instead of asking again

  Never deletes without a separate confirmation, even under --yes. The
  scheduled run is the one exception, and only because scheduling it in
  the first place already was that confirmation.
TXT
}

# === Unit content, generated rather than shipped, since it bakes in
# per-machine values. detect() regenerates the same text to compare.

cleanup_service_content() {
  local age="$1" root="$2"
  cat <<EOF
[Unit]
Description=ipile dev-cleanup sweep

[Service]
Type=oneshot
ExecStart=${DEV_CLEANUP_BIN} --all --days ${age} --path ${root} --yes
Nice=10
IOSchedulingClass=idle
EOF
}

cleanup_timer_content() {
  local every="$1"
  cat <<EOF
[Unit]
Description=ipile dev-cleanup sweep, every ${every} day(s)

[Timer]
OnBootSec=10min
OnUnitActiveSec=${every}d
Persistent=true
RandomizedDelaySec=30m

[Install]
WantedBy=timers.target
EOF
}

# cleanup_timer_matches. True when the units on disk match what the
# current state would generate, and the timer is enabled. Read only.
cleanup_timer_matches() {
  local age every root
  age="$(state_get cleanup_age 2>/dev/null || printf '30')"
  every="$(state_get cleanup_every 2>/dev/null || printf '7')"
  root="$(state_get projects_root 2>/dev/null || printf '%s/Projects' "$HOME")"

  cleanup_service_content "$age" "$root" | cmp -s - "$CLEANUP_SERVICE" || return 1
  cleanup_timer_content "$every" | cmp -s - "$CLEANUP_TIMER" || return 1
  [ -L "$CLEANUP_TIMER_WANTS" ]
}

# === Scheduler readiness

cleanup_scheduler_ready() {
  command -v systemctl >/dev/null 2>&1 && command -v loginctl >/dev/null 2>&1
}

cleanup_online() {
  curl -s --head --connect-timeout 5 https://github.com >/dev/null 2>&1
}

# cleanup_install_timer <age> <every> <root>. Writes both units, enables
# the timer, and offers lingering so it still runs while logged out.
cleanup_install_timer() {
  local age="$1" every="$2" root="$3"

  fs_mkdir "$SYSTEMD_USER_DIR" 755
  cleanup_service_content "$age" "$root" | fs_write "$CLEANUP_SERVICE" 644
  cleanup_timer_content "$every" | fs_write "$CLEANUP_TIMER" 644

  if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
    ui_dry "systemctl --user daemon-reload && enable --now dev-cleanup.timer"
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload 2>/dev/null \
    && systemctl --user enable --now dev-cleanup.timer 2>/dev/null; then
    ui_ok "Automatic cleanup enabled, every ${every} day(s)."
    ui_info "Check with: systemctl --user list-timers dev-cleanup.timer"

    if command -v loginctl >/dev/null 2>&1 \
      && ! loginctl show-user "$(id -un)" 2>/dev/null | grep -q '^Linger=yes'; then
      if [ "${IPILE_ASSUME_YES:-0}" != "1" ] \
        && ui_confirm "Also let it run while you are logged out? (needs sudo)" "y"; then
        os_sudo loginctl enable-linger "$(id -un)"
      else
        ui_warn "Without lingering, the timer only fires while you are logged in."
      fi
    fi
    return 0
  fi

  ui_warn "Units written, but the timer could not be enabled here."
  ui_info "Enable it yourself: systemctl --user enable --now dev-cleanup.timer"
  return 0
}

# cleanup_disable_timer. Switching back to manual removes what automatic
# mode installed rather than leaving a timer nothing points at.
cleanup_disable_timer() {
  [ -f "$CLEANUP_TIMER" ] || return 0
  if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
    ui_dry "systemctl --user disable --now dev-cleanup.timer"
    return 0
  fi
  command -v systemctl >/dev/null 2>&1 && systemctl --user disable --now dev-cleanup.timer 2>/dev/null
  run rm -f "$CLEANUP_SERVICE" "$CLEANUP_TIMER"
}

# === Mode and run

# cleanup_ask_mode <varname>.
cleanup_ask_mode() {
  local varname="$1"
  local __mode

  if [ "${IPILE_ASSUME_YES:-0}" = "1" ]; then
    __mode="$(state_get cleanup_mode 2>/dev/null || printf 'manual')"
  else
    local choice
    echo ""
    ui_menu choice "Run it myself, whenever I ask" "Run it automatically, on a schedule"
    case "$choice" in
      2) __mode="auto" ;;
      *) __mode="manual" ;;
    esac
  fi
  eval "${varname}=\"\${__mode}\""
}

# cleanup_apply_auto <root>. Asks the interval, gates the scheduler
# install on connectivity, installs the timer. Returns 1 to tell the
# caller to fall back to manual -- offline, or systemd unavailable even
# after trying to install it, is not a failure, just a different plan.
cleanup_apply_auto() {
  local root="$1"
  local every
  ui_ask_int "Run it automatically how often, in days?" \
    "$(state_get cleanup_every 2>/dev/null || printf '7')" every

  if ! cleanup_scheduler_ready && cleanup_online; then
    ui_info "Installing systemd user tooling..."
    os_pm_install systemd >/dev/null 2>&1 || true
  fi

  if ! cleanup_scheduler_ready; then
    ui_warn "No connection, or systemd is unavailable here. Running once instead of scheduling."
    ui_info "Run 'ipile cleanup' again once you are online to turn on the timer."
    return 1
  fi

  state_set cleanup_every "$every"
  state_set cleanup_mode "auto"
  cleanup_install_timer "$(state_get cleanup_age 2>/dev/null || printf '30')" "$every" "$root"
  return 0
}

# cleanup_run_now <age> <root>. Always previews. Deletes only after a
# separate confirm -- never under --dry-run, never under --yes either,
# matching guard's rule that --yes skips prompts about running, not
# prompts about deleting.
cleanup_run_now() {
  local age="$1" root="$2"

  echo ""
  ui_info "Running a sweep of ${root}, things untouched for ${age}+ days..."
  bash "${IPILE_LIB}/assets/bin/dev-cleanup" --all --days "$age" --path "$root"

  [ "${IPILE_DRY_RUN:-0}" = "1" ] && return 0

  if [ "${IPILE_ASSUME_YES:-0}" = "1" ]; then
    ui_warn "Not deleting under --yes."
    ui_info "Run by hand: dev-cleanup --all --days ${age} --path ${root} --yes"
    return 0
  fi

  echo ""
  if ui_confirm "Delete what was listed above?" "n"; then
    bash "${IPILE_LIB}/assets/bin/dev-cleanup" --all --days "$age" --path "$root" --yes
  fi
}

detect() {
  fs_assets_match "bin/dev-cleanup" "$DEV_CLEANUP_BIN" || return 1

  local mode
  mode="$(state_get cleanup_mode 2>/dev/null || true)"
  [ -n "$mode" ] || return 2

  if [ "$mode" = "auto" ]; then
    cleanup_timer_matches && return 0
    return 2
  fi

  return 0
}

apply() {
  fs_install_asset "bin/dev-cleanup" "$DEV_CLEANUP_BIN" 755
  ui_ok "dev-cleanup installed to ${DEV_CLEANUP_BIN}"

  local mode
  cleanup_ask_mode mode

  local age
  ui_ask_int "Delete things untouched for how many days?" \
    "$(state_get cleanup_age 2>/dev/null || printf '30')" age
  state_set cleanup_age "$age"

  local root=""
  if ! projects_root root; then
    ui_info "No projects folder yet, so there is nothing to clean. Run 'ipile cleanup' again once you have one."
  fi

  if [ "$mode" = "auto" ] && [ "$IPILE_OS" = "mac" ]; then
    ui_warn "Automatic scheduling is systemd-only for now. Running manually instead."
    mode="manual"
  fi

  if [ "$mode" = "auto" ] && [ -n "$root" ]; then
    cleanup_apply_auto "$root" || mode="manual"
  elif [ "$mode" = "auto" ]; then
    # Automatic mode needs a root even before the first sweep, since the
    # timer's ExecStart bakes one in. Default to the usual spot rather
    # than blocking scheduling on a question already declined once.
    cleanup_apply_auto "$HOME/Projects" || mode="manual"
  fi

  if [ "$mode" = "manual" ]; then
    state_set cleanup_mode "manual"
    cleanup_disable_timer
  fi

  [ -n "$root" ] && cleanup_run_now "$age" "$root"

  return 0
}

verify() {
  fs_assets_match "bin/dev-cleanup" "$DEV_CLEANUP_BIN" || return 1

  local mode
  mode="$(state_get cleanup_mode 2>/dev/null || true)"
  [ -n "$mode" ] || return 1

  if [ "$mode" = "auto" ]; then
    cleanup_timer_matches || return 1
  fi

  return 0
}
