#!/usr/bin/env bash
# Global editor and linter config files. Sourced by the registry.
#
# The content of every file lives in lib/assets and nowhere else. This
# module only decides where each asset lands, which is what stops the
# same JSON drifting between two copies of it.

MODULE_TITLE="Global Config Files"
MODULE_EMOJI="📁"
MODULE_DESC="Editor and formatter config files"
MODULE_NEEDS="git-install"

# === Data
#
# One "asset destination" pair per line. Neither side contains a space.
dotfiles_pairs() {
  printf '%s\n' \
    "vscode-settings.json ${HOME}/.vscode/settings.json" \
    "vscode-extensions.json ${HOME}/.vscode/extensions.json" \
    "prettierrc.json ${HOME}/.prettierrc" \
    "solhint.json ${HOME}/.solhint.json" \
    "lintstagedrc.json ${HOME}/.lintstagedrc.json" \
    "gitignore_global ${HOME}/.gitignore_global"
}

# === Contract

describe() {
  ui_info "Writes six global config files from the shipped assets:"
  ui_info "  ~/.vscode/settings.json     editor, formatter and language defaults"
  ui_info "  ~/.vscode/extensions.json   the recommended extension set"
  ui_info "  ~/.prettierrc               formatting rules"
  ui_info "  ~/.solhint.json             Solidity linting rules"
  ui_info "  ~/.lintstagedrc.json        what runs on staged files"
  ui_info "  ~/.gitignore_global         ignores that belong on the machine"
  ui_info "Then points git's core.excludesfile at ~/.gitignore_global."
  ui_info "Anything already at those paths is backed up before it is replaced."
}

detect() {
  local total=0
  local matched=0
  local asset dest
  local all
  all="$(dotfiles_pairs)"

  while IFS=' ' read -r asset dest; do
    [ -n "$asset" ] || continue
    total=$((total + 1))
    fs_assets_match "$asset" "$dest" && matched=$((matched + 1))
  done <<EOF
$all
EOF

  [ "$matched" -eq 0 ] && return 1
  [ "$matched" -eq "$total" ] || return 2

  # All six match, but the module is only fully applied once git is
  # actually reading the global ignore file.
  [ "$(git config --global --get core.excludesfile 2>/dev/null)" = "${HOME}/.gitignore_global" ] || return 2
  return 0
}

apply() {
  local asset dest
  local all
  all="$(dotfiles_pairs)"

  fs_mkdir "${HOME}/.vscode" || return 1

  while IFS=' ' read -r asset dest; do
    [ -n "$asset" ] || continue
    ui_info "Writing ${dest}"
    fs_install_asset "$asset" "$dest" || return 1
  done <<EOF
$all
EOF

  run git config --global core.excludesfile "${HOME}/.gitignore_global" || return 1
  ui_ok "Global config files written and core.excludesfile set."
  return 0
}

verify() {
  local missing=""
  local asset dest
  local all
  all="$(dotfiles_pairs)"

  while IFS=' ' read -r asset dest; do
    [ -n "$asset" ] || continue
    fs_assets_match "$asset" "$dest" || missing="${missing} ${dest}"
  done <<EOF
$all
EOF

  if [ -n "$missing" ]; then
    ui_err "Not written as expected:${missing}"
    return 1
  fi

  if [ "$(git config --global --get core.excludesfile 2>/dev/null)" != "${HOME}/.gitignore_global" ]; then
    ui_err "core.excludesfile does not point at ~/.gitignore_global"
    return 1
  fi
  return 0
}
