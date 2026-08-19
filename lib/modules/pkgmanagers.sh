#!/usr/bin/env bash
# Corepack, pnpm and yarn. Sourced by the registry.

MODULE_TITLE="Corepack, pnpm, yarn"
MODULE_EMOJI="⚡"
MODULE_DESC="pnpm and yarn through Corepack"
MODULE_NEEDS="node"

describe() {
  ui_info "Enables Corepack, which ships with Node 16 and newer."
  ui_info "Activates pnpm@${IPILE_PNPM_VERSION} and yarn@${IPILE_YARN_VERSION} through Corepack."
  ui_info "Nothing is installed globally with npm, so the shims stay"
  ui_info "pinned per project by the packageManager field."
  ui_info "Requires the node module to have run first."
}

# Loading nvm here matters because a fresh nvm install in the same run is
# only on PATH for shells that have sourced it.
pkg_load_nvm() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "${NVM_DIR}/nvm.sh" ]; then
    # shellcheck source=/dev/null
    . "${NVM_DIR}/nvm.sh"
  fi
}

detect() {
  local found=0
  local total=3
  command -v corepack >/dev/null 2>&1 && found=$((found + 1))
  command -v pnpm >/dev/null 2>&1 && found=$((found + 1))
  command -v yarn >/dev/null 2>&1 && found=$((found + 1))

  [ "$found" -eq "$total" ] && return 0
  [ "$found" -gt 0 ] && return 2
  return 1
}

apply() {
  pkg_load_nvm

  if ! command -v corepack >/dev/null 2>&1; then
    if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
      ui_dry "corepack enable"
      ui_dry "corepack prepare pnpm@${IPILE_PNPM_VERSION} --activate"
      ui_dry "corepack prepare yarn@${IPILE_YARN_VERSION} --activate"
      return 0
    fi
    ui_err "corepack is not on PATH. Run the node module first."
    return 1
  fi

  ui_info "Enabling Corepack."
  run corepack enable || return 1

  ui_info "Activating pnpm@${IPILE_PNPM_VERSION}."
  run corepack prepare "pnpm@${IPILE_PNPM_VERSION}" --activate || return 1

  ui_info "Activating yarn@${IPILE_YARN_VERSION}."
  run corepack prepare "yarn@${IPILE_YARN_VERSION}" --activate || return 1

  if [ "${IPILE_DRY_RUN:-0}" != "1" ]; then
    ui_ok "npm  $(npm -v 2>/dev/null)"
    ui_ok "pnpm $(pnpm -v 2>/dev/null)"
    ui_ok "yarn $(yarn -v 2>/dev/null)"
  fi
  return 0
}

verify() {
  pkg_load_nvm
  local bin
  for bin in corepack pnpm yarn; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      ui_err "${bin} is not on PATH."
      return 1
    fi
  done
  pnpm -v >/dev/null 2>&1 || {
    ui_err "pnpm does not run."
    return 1
  }
  yarn -v >/dev/null 2>&1 || {
    ui_err "yarn does not run."
    return 1
  }
  return 0
}
