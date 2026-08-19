#!/usr/bin/env bash
# Node.js via nvm. Sourced by the registry.

MODULE_TITLE="Node.js via nvm"
MODULE_EMOJI="📦"
MODULE_DESC="nvm plus Node ${IPILE_NODE_VERSION} as the default"

# Both pins live in lib/manifest.sh. Read here, never redeclared, so
# there is exactly one place to change what lands on a machine.
NODE_VERSION="${IPILE_NODE_VERSION}"
NVM_VERSION="${IPILE_NVM_VERSION}"

NVM_HOME="${NVM_DIR:-$HOME/.nvm}"

describe() {
  ui_info "Installs nvm ${NVM_VERSION} into ${NVM_HOME}."
  ui_info "Installs Node.js ${NODE_VERSION} and sets it as the default alias."
  ui_info "Loads nvm into this shell so node and npm are on PATH for the"
  ui_info "rest of the run without opening a new terminal."
  ui_info "An existing nvm is reused, not reinstalled."
}

# node_major. Prints the major version of the node on PATH, or nothing.
node_major() {
  local raw
  raw="$(node -v 2>/dev/null)" || return 1
  raw="${raw#v}"
  printf '%s' "${raw%%.*}"
}

detect() {
  local major
  major="$(node_major 2>/dev/null)"
  if [ -z "$major" ]; then
    return 1
  fi
  if [ -d "$NVM_HOME" ] && [ "$major" -ge "$NODE_VERSION" ] 2>/dev/null; then
    return 0
  fi
  return 2
}

# Sourcing nvm.sh into the current shell is what lets the pkgmanagers
# module find corepack later in the same run.
node_load_nvm() {
  NVM_HOME="${NVM_DIR:-$HOME/.nvm}"
  export NVM_DIR="$NVM_HOME"
  if [ -s "${NVM_DIR}/nvm.sh" ]; then
    # shellcheck source=/dev/null
    . "${NVM_DIR}/nvm.sh"
  fi
  if [ -s "${NVM_DIR}/bash_completion" ]; then
    # shellcheck source=/dev/null
    . "${NVM_DIR}/bash_completion"
  fi
}

apply() {
  if [ -s "${NVM_HOME}/nvm.sh" ]; then
    ui_info "nvm is already installed at ${NVM_HOME}."
  else
    ui_info "Downloading and running the nvm ${NVM_VERSION} install script."
    run sh -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash" \
      || {
        ui_err "The nvm installer failed."
        return 1
      }
  fi

  node_load_nvm

  if ! command -v nvm >/dev/null 2>&1; then
    if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
      ui_dry "nvm install ${NODE_VERSION}"
      ui_dry "nvm alias default ${NODE_VERSION}"
      return 0
    fi
    ui_err "nvm did not load from ${NVM_HOME}."
    return 1
  fi

  ui_info "Installing Node.js ${NODE_VERSION}."
  run nvm install "$NODE_VERSION" || return 1
  run nvm use "$NODE_VERSION" || return 1
  run nvm alias default "$NODE_VERSION" || return 1

  if [ "${IPILE_DRY_RUN:-0}" != "1" ]; then
    ui_ok "node $(node -v 2>/dev/null)"
    ui_ok "npm  $(npm -v 2>/dev/null)"
  fi
  return 0
}

verify() {
  node_load_nvm
  command -v node >/dev/null 2>&1 || {
    ui_err "node is not on PATH."
    return 1
  }
  command -v npm >/dev/null 2>&1 || {
    ui_err "npm is not on PATH."
    return 1
  }

  local major
  major="$(node_major)"
  if [ -z "$major" ]; then
    ui_err "Could not read the node version."
    return 1
  fi
  if [ "$major" -lt "$NODE_VERSION" ] 2>/dev/null; then
    ui_warn "node is v${major}, expected ${NODE_VERSION} or newer."
    return 1
  fi
  return 0
}
