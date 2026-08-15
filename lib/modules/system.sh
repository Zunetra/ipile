#!/usr/bin/env bash
# System packages and build essentials. Sourced by the registry.

MODULE_TITLE="System Update & Essentials"
MODULE_EMOJI="📦"
MODULE_DESC="Base packages and build tools"

describe() {
  ui_info "Refreshes the package index for this machine's package manager."
  ui_info "Upgrades everything already installed."
  ui_info "Installs curl, wget, git, ca-certificates and a C toolchain."
  ui_info "On macOS it installs Homebrew first if it is missing."
  ui_info "Package names are translated per manager, so apt, dnf, pacman,"
  ui_info "apk, zypper and brew are all handled."
}

detect() {
  command -v curl >/dev/null 2>&1 || return 1
  command -v wget >/dev/null 2>&1 || return 1
  command -v git  >/dev/null 2>&1 || return 1
  if command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 \
    || command -v clang >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

apply() {
  os_ensure_brew || return 1

  ui_info "Refreshing the package index."
  # A third-party repo with a stale GPG key must not stop the whole run.
  os_pm_refresh || ui_warn "Index refresh reported a problem. Continuing."

  ui_info "Upgrading installed packages."
  os_pm_upgrade || ui_warn "Upgrade reported a problem. Continuing."

  ui_info "Installing essentials."
  os_pm_install curl wget git || return 1

  local certs build
  certs="$(os_pm_pkg ca-certificates)"
  [ -n "$certs" ] && { os_pm_install $certs || return 1; }

  build="$(os_pm_pkg build-essential)"
  if [ -n "$build" ]; then
    os_pm_install $build || return 1
  else
    ui_info "No separate build package on this manager. Skipping it."
  fi

  ui_ok "System packages are up to date."
  return 0
}

verify() {
  local missing=""
  local bin
  for bin in curl wget git; do
    command -v "$bin" >/dev/null 2>&1 || missing="${missing} ${bin}"
  done
  if [ -n "$missing" ]; then
    ui_err "Still missing:${missing}"
    return 1
  fi
  if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1 \
    && ! command -v clang >/dev/null 2>&1; then
    ui_warn "No C compiler on PATH. Native npm modules will not build."
    return 1
  fi
  return 0
}
