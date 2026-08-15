#!/usr/bin/env bash
# What a previous run did. Plain key=value lines, because the whole point
# is that it stays readable and hand-editable.
#
# State records history, not truth. detect() always looks at the machine.
# This file only answers "when was this last applied, and by which
# version", which is what update and doctor need and cannot re-derive.

state_file() {
  printf '%s/state' "$IPILE_VAR"
}

state_init() {
  fs_mkdir "$IPILE_VAR" 700
  [ "${IPILE_DRY_RUN:-0}" = "1" ] && return 0
  [ -f "$(state_file)" ] || : > "$(state_file)"
}

state_get() {
  local key="$1"
  local file
  file="$(state_file)"
  [ -f "$file" ] || return 1
  local line
  line="$(grep "^${key}=" "$file" 2>/dev/null | tail -1 || true)"
  [ -n "$line" ] || return 1
  printf '%s' "${line#*=}"
}

state_set() {
  local key="$1"
  local value="$2"
  local file
  file="$(state_file)"

  if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
    ui_dry "state ${key}=${value}"
    return 0
  fi

  state_init
  local tmp="${file}.tmp"
  grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null || : > "$tmp"
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$file"
}

# state_record_module <id> <outcome>. Called by the runner, not by
# modules, so every module is recorded the same way whatever it does.
state_record_module() {
  local id="$1"
  local outcome="$2"
  state_set "module.${id}.outcome" "$outcome"
  state_set "module.${id}.at" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  state_set "module.${id}.version" "${IPILE_VERSION:-unknown}"
}

# === Run log
#
# A transcript per run, so "what did this change on my machine" has an
# answer that does not depend on scrollback.

log_init() {
  [ "${IPILE_DRY_RUN:-0}" = "1" ] && return 0
  fs_mkdir "${IPILE_VAR}/logs" 700
  IPILE_LOG="${IPILE_VAR}/logs/${IPILE_RUN_ID}.log"
  export IPILE_LOG
  {
    printf 'ipile %s\n' "${IPILE_VERSION:-unknown}"
    printf 'run    %s\n' "$IPILE_RUN_ID"
    printf 'os     %s (%s, pm=%s)\n' "$IPILE_OS" "$IPILE_DISTRO" "$IPILE_PM"
    printf 'user   %s\n' "$(whoami)"
    printf '\n'
  } > "$IPILE_LOG"
}

log_line() {
  [ -n "${IPILE_LOG:-}" ] || return 0
  printf '%s  %s\n' "$(date -u '+%H:%M:%S')" "$*" >> "$IPILE_LOG"
}
