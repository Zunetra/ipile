#!/usr/bin/env bash
# The module registry and runner.
#
# THE MODULE CONTRACT
#
# Every file in lib/modules/ defines exactly this surface:
#
#   MODULE_TITLE   short name shown in the menu
#   MODULE_EMOJI   one character shown beside it
#   MODULE_DESC    one line: what this changes on your machine
#   MODULE_NEEDS   optional, space separated module ids this one requires
#
#   describe()     prints the detail shown when the user asks for it
#   detect()       0 = already applied, 1 = not applied, 2 = partial
#   apply()        do it
#   verify()       0 = provably working. Also used by doctor.
#
# Modules are sourced one at a time and their functions are redefined by
# the next source. That is deliberate: a module cannot call into another
# module's internals, only into core, so there is one place a shared
# behaviour can live and it is lib/core.

# The canonical order. Dependencies run before dependents.
IPILE_MODULES="system rust node pkgmanagers git-install git-identity git-accounts git-hooks git-globals dotfiles guard cleanup"

# The user asked to stop. A distinct code rather than an exit, so core
# never decides how the program ends: the runner propagates it and the
# dispatcher still prints the summary, which is where the run log and the
# backup directory are named.
REGISTRY_QUIT=10

registry_ids() {
  printf '%s\n' $IPILE_MODULES
}

registry_exists() {
  [ -f "${IPILE_LIB}/modules/${1}.sh" ]
}

# registry_load <id>. Sources the module, replacing whatever was loaded.
registry_load() {
  local id="$1"
  if ! registry_exists "$id"; then
    ui_err "Unknown module: ${id}"
    return 1
  fi

  # Clear the previous module so a missing function is a loud failure
  # rather than the last module's implementation running again.
  unset -f describe detect apply verify 2>/dev/null || true
  MODULE_TITLE=""
  MODULE_EMOJI=""
  MODULE_DESC=""
  MODULE_NEEDS=""

  # shellcheck source=/dev/null
  . "${IPILE_LIB}/modules/${id}.sh"

  local fn
  for fn in describe detect apply verify; do
    if ! command -v "$fn" >/dev/null 2>&1; then
      ui_err "Module ${id} does not define ${fn}()"
      return 1
    fi
  done
}

registry_status_label() {
  case "$1" in
    0) printf 'installed' ;;
    2) printf 'partial' ;;
    *) printf 'not set up' ;;
  esac
}

registry_status_colour() {
  case "$1" in
    0) printf '%b' "$THEME_GREEN" ;;
    2) printf '%b' "$YELLOW" ;;
    *) printf '%b' "$DIM" ;;
  esac
}

# === The runner

# registry_run_one <id>. Loads, detects, prompts, applies, verifies,
# records. The prompt is what makes every step skippable, and detect() is
# what stops it asking about work that is already done.
registry_run_one() {
  local id="$1"

  registry_load "$id" || return 1

  local status=0
  detect || status=$?

  ui_heading "$MODULE_EMOJI" "$MODULE_TITLE" "$MODULE_DESC"

  local colour
  colour="$(registry_status_colour "$status")"
  echo -e "  Status: ${colour}$(registry_status_label "$status")${NC}"

  # An already-applied module is offered, not forced. Re-running is safe
  # and is how someone repairs a machine, so it stays reachable.
  local default_run="y"
  if [ "$status" -eq 0 ]; then
    default_run="n"
  fi

  # In --only mode the named modules run without a second confirmation,
  # but a module pulled in as a dependency was never asked for by name,
  # so it still gets a prompt.
  local auto_run=0
  if [ "${IPILE_ONLY_MODE:-0}" = "1" ]; then
    case "${IPILE_ONLY_EXPLICIT:- }" in
      *" $id "*)
        auto_run=1
        ;;
      *)
        # A dependency that is already satisfied is why it was pulled in
        # at all. Nothing to do, and no reason to interrupt.
        if [ "$status" -eq 0 ]; then
          ui_skip "${MODULE_TITLE} is already in place."
          return 0
        fi
        ;;
    esac
  fi

  if [ "$auto_run" -eq 0 ]; then
    local choice=""
    echo ""
    if [ "$status" -eq 0 ]; then
      ui_menu choice "Skip, this is already done" "Run it again anyway" \
        "Show me what it does" "!Quit, stop the whole run"
      case "$choice" in
        1)
          ui_skip "Skipped ${id}."
          state_record_module "$id" "skipped"
          return 0
          ;;
        3)
          echo ""
          describe
          echo ""
          if ! ui_confirm "Run it?" "$default_run"; then
            ui_skip "Skipped ${id}."
            state_record_module "$id" "skipped"
            return 0
          fi
          ;;
        4) return "$REGISTRY_QUIT" ;;
      esac
    else
      ui_menu choice "Run it" "Skip it" "Show me what it does first" \
        "!Quit, stop the whole run"
      case "$choice" in
        2)
          ui_skip "Skipped ${id}."
          state_record_module "$id" "skipped"
          return 0
          ;;
        3)
          echo ""
          describe
          echo ""
          if ! ui_confirm "Run it?" "$default_run"; then
            ui_skip "Skipped ${id}."
            state_record_module "$id" "skipped"
            return 0
          fi
          ;;
        4) return "$REGISTRY_QUIT" ;;
      esac
    fi
  fi

  echo ""
  log_line "module ${id}: apply start (status was $(registry_status_label "$status"))"

  # A module failing is reported and the run continues. One broken step
  # must not cost the user the other nine.
  if apply; then
    # A dry run changed nothing, so verify() is guaranteed to fail and
    # reporting that as a problem would be a lie.
    if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
      ui_info "Dry run: ${MODULE_TITLE} would be applied. Not verified."
      log_line "module ${id}: dry-run"
    elif verify; then
      ui_done "${MODULE_TITLE} is set up."
      state_record_module "$id" "applied"
      log_line "module ${id}: applied and verified"
    else
      ui_warn "${MODULE_TITLE} ran, but verification did not pass."
      ui_info "Run 'ipile doctor' after finishing for the detail."
      state_record_module "$id" "unverified"
      log_line "module ${id}: applied but verify failed"
    fi
  else
    ui_err "${MODULE_TITLE} failed. Nothing was rolled back."
    ui_info "Files changed before the failure are backed up in $(fs_backup_dir)"
    state_record_module "$id" "failed"
    log_line "module ${id}: FAILED"
    IPILE_HAD_FAILURE=1
  fi

  return 0
}

# registry_expand <id...>. Adds whatever the requested modules depend on.
#
# Without this, 'ipile git accounts' on a machine with no git would walk
# a user through generating keys and then fail on the first git config,
# because --only runs exactly what it was given and nothing else. A
# module that cannot work alone has to say so, and the runner has to
# honour it.
registry_expand() {
  local wanted=" $* "
  local changed=1
  local id need

  while [ "$changed" -eq 1 ]; do
    changed=0
    for id in $wanted; do
      registry_exists "$id" || continue
      # Read MODULE_NEEDS without disturbing the caller's loaded module.
      need="$(
        MODULE_NEEDS=""
        # shellcheck source=/dev/null
        . "${IPILE_LIB}/modules/${id}.sh" >/dev/null 2>&1
        printf '%s' "$MODULE_NEEDS"
      )"
      for dep in $need; do
        case "$wanted" in
          *" $dep "*) ;;
          *)
            wanted="${wanted}${dep} "
            changed=1
            ;;
        esac
      done
    done
  done

  # Emit in canonical order so dependencies run before dependents.
  for id in $IPILE_MODULES; do
    case "$wanted" in
      *" $id "*) printf '%s\n' "$id" ;;
    esac
  done
}

# registry_run <id...>. Runs a list in the canonical order regardless of
# the order the caller passed them.
registry_run() {
  local requested=" $* "
  local id
  local ran=0

  local rc
  for id in $IPILE_MODULES; do
    case "$requested" in
      *" $id "*)
        rc=0
        registry_run_one "$id" || rc=$?
        if [ "$rc" -eq "$REGISTRY_QUIT" ]; then
          ui_skip "Stopped at ${id}. Nothing after it was run."
          log_line "run stopped by the user at ${id}"
          return "$REGISTRY_QUIT"
        fi
        ran=$((ran + 1))
        ;;
    esac
  done

  if [ "$ran" -eq 0 ]; then
    ui_warn "Nothing to run."
    return 1
  fi
  return 0
}

# registry_overview. The status table. Reads every module once without
# changing anything, which is also exactly what doctor needs.
registry_overview() {
  local id status colour
  echo ""
  echo -e "  ${BOLD}Modules${NC}"
  echo ""
  for id in $IPILE_MODULES; do
    registry_load "$id" >/dev/null 2>&1 || continue
    status=0
    detect >/dev/null 2>&1 || status=$?
    colour="$(registry_status_colour "$status")"
    printf "  %b%-12s%b  %-34s %b%s%b\n" \
      "$BOLD" "$id" "$NC" \
      "$MODULE_DESC" \
      "$colour" "$(registry_status_label "$status")" "$NC"
  done
  echo ""
}
