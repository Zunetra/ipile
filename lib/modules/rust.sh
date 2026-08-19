#!/usr/bin/env bash
# Rust toolchain via rustup. Sourced by the registry.

MODULE_TITLE="Rust via rustup"
MODULE_EMOJI="🦀"
MODULE_DESC="rustup, ${IPILE_RUST_TOOLCHAIN}, rustfmt, clippy"

describe() {
  ui_info "Installs rustup and the ${IPILE_RUST_TOOLCHAIN} toolchain from sh.rustup.rs."
  ui_info "Adds the rustfmt and clippy components."
  ui_info "Loads \$HOME/.cargo/env into this shell so cargo is on PATH for"
  ui_info "the rest of the run without opening a new terminal."
  ui_info "An existing rustup is reused, not reinstalled."
}

# rust_has_component <name>. Silent by design, detect() calls it.
#
# Invoking rustup at all creates RUSTUP_HOME if it does not exist, which
# would make detect() write to disk. detect() has to be side-effect free
# for --dry-run to mean anything, so bail out before touching rustup when
# its home is absent. No home means no components either way.
rust_has_component() {
  [ -d "${RUSTUP_HOME:-$HOME/.rustup}" ] || return 1
  rustup component list --installed 2>/dev/null | grep -q "^${1}"
}

detect() {
  if command -v rustc >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1; then
    if command -v rustup >/dev/null 2>&1; then
      if rust_has_component rustfmt && rust_has_component clippy; then
        return 0
      fi
      return 2
    fi
    # rustc from a distro package has no rustup and no component control.
    return 2
  fi
  return 1
}

# Sourcing cargo's env into the current shell is what lets later modules
# and the verify step below see cargo without a fresh login shell.
rust_load_env() {
  if [ -s "$HOME/.cargo/env" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.cargo/env"
  fi
}

apply() {
  if command -v rustup >/dev/null 2>&1; then
    ui_info "rustup is already installed. Updating the ${IPILE_RUST_TOOLCHAIN} toolchain."
    run rustup update "${IPILE_RUST_TOOLCHAIN}" || ui_warn "Toolchain update reported a problem."
  else
    ui_info "Downloading and running the rustup installer."
    run sh -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y" \
      || {
        ui_err "The rustup installer failed."
        return 1
      }
  fi

  rust_load_env

  if ! command -v rustup >/dev/null 2>&1; then
    if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
      ui_dry "rustup component add rustfmt clippy"
      return 0
    fi
    ui_err "rustup is not on PATH after install."
    return 1
  fi

  ui_info "Adding the rustfmt and clippy components."
  run rustup component add rustfmt clippy || return 1

  if [ "${IPILE_DRY_RUN:-0}" != "1" ]; then
    ui_ok "$(rustc --version 2>/dev/null)"
    ui_ok "$(cargo --version 2>/dev/null)"
  fi
  return 0
}

verify() {
  rust_load_env
  command -v rustc >/dev/null 2>&1 || {
    ui_err "rustc is not on PATH."
    return 1
  }
  command -v cargo >/dev/null 2>&1 || {
    ui_err "cargo is not on PATH."
    return 1
  }
  rustc --version >/dev/null 2>&1 || return 1
  cargo --version >/dev/null 2>&1 || return 1
  if command -v rustup >/dev/null 2>&1; then
    rust_has_component rustfmt || {
      ui_warn "rustfmt is not installed."
      return 1
    }
    rust_has_component clippy || {
      ui_warn "clippy is not installed."
      return 1
    }
  fi
  return 0
}
