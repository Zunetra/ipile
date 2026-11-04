#!/usr/bin/env bash
# Pinned toolchain versions. Data, not logic.
# Sourced, never executed. Kept bash 3.2 safe.
#
# Every version this tool installs is declared here and nowhere else, so
# "what will land on my machine" is one file to read rather than a grep
# across lib/modules. A module that hardcodes a version instead of
# reading it from here is a bug.
#
# Bump a pin here, run 'pnpm dry' to see the effect, then release. The
# values are exported because modules run in the same shell but are
# sourced by the registry after this file.

# === Node.js
#
# Fixed to one major so every machine set up by this tool lands on the
# same runtime. LTS deliberately, not the newest release: even-numbered
# majors only become LTS in the October after they ship, and a machine
# bootstrap is the wrong place to run a Current release. Bump when the
# next LTS line is cut and the team has moved.
IPILE_NODE_VERSION="24"

# The nvm installer is fetched by tag, never from a moving branch, so a
# rerun months later installs what was tested rather than whatever main
# happens to hold.
IPILE_NVM_VERSION="v0.40.8"

# === Corepack shims
#
# Not hard pins. Corepack activates these once, and the packageManager
# field in each project pins the version that actually runs there, so
# holding a specific pnpm here would be overridden per repository
# anyway. Named regardless: a manifest that answers half the question
# sends people back to grepping the modules.
IPILE_PNPM_VERSION="latest"
IPILE_YARN_VERSION="stable"

# === Rust
#
# rustup's own channel name, not a version number. 'stable' tracks the
# six-week release train, which is what a Rust toolchain is expected to
# do; pinning an exact rustc would strand anyone whose project needs a
# newer one.
IPILE_RUST_TOOLCHAIN="stable"

export IPILE_NODE_VERSION IPILE_NVM_VERSION
export IPILE_PNPM_VERSION IPILE_YARN_VERSION
export IPILE_RUST_TOOLCHAIN
