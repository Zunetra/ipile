#!/usr/bin/env bash
# Git itself. Identity, keys and signing live in the other git modules.

MODULE_TITLE="Git"
MODULE_EMOJI="🔧"
MODULE_DESC="Installs or upgrades git"

describe() {
  ui_info "Installs git when it is missing."
  ui_info "Upgrades it when it is already there, which is never fatal if"
  ui_info "the package manager has nothing newer."
  ui_info "Identity, SSH keys, signing and global config are handled by"
  ui_info "the other git modules."
}

detect() {
  command -v git >/dev/null 2>&1 && return 0
  return 1
}

apply() {
  os_ensure_brew || return 1

  if command -v git >/dev/null 2>&1; then
    ui_info "Git found: $(git --version 2>/dev/null). Checking for updates."
    os_upgrade_one git
  else
    ui_info "Git not found. Installing it."
    os_pm_install git || {
      ui_err "Could not install git."
      return 1
    }
  fi

  if [ "${IPILE_DRY_RUN:-0}" != "1" ]; then
    if command -v git >/dev/null 2>&1; then
      ui_ok "$(git --version)"
    else
      ui_err "git is still not on PATH."
      return 1
    fi
  fi
  return 0
}

verify() {
  command -v git >/dev/null 2>&1 || {
    ui_err "git is not on PATH."
    return 1
  }
  git --version >/dev/null 2>&1 || return 1
  return 0
}
