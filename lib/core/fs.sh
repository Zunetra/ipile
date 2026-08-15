#!/usr/bin/env bash
# File mutation helpers. Every write to a user's home directory goes
# through this file, which is what makes --dry-run and backups possible
# without each module remembering to opt in.

# run <cmd...>. The single choke point for anything that changes state.
run() {
  if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
    ui_dry "$*"
    return 0
  fi
  "$@"
}

# === Backups
#
# One directory per invocation, so a run can be reviewed or reversed as a
# unit. Created lazily: a run that changes nothing leaves no directory.

fs_backup_dir() {
  printf '%s/backups/%s' "$IPILE_VAR" "$IPILE_RUN_ID"
}

# fs_backup <path>. Copies a file aside before it is overwritten. A path
# that does not exist yet needs no backup and is not an error.
fs_backup() {
  local target="$1"
  [ -e "$target" ] || return 0

  local dir
  dir="$(fs_backup_dir)"

  if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
    ui_dry "backup ${target} -> ${dir}/"
    return 0
  fi

  mkdir -p "$dir"
  # Flatten the path into the filename so ~/.ssh/config and ~/config
  # cannot collide inside one backup directory.
  local flat
  flat="$(printf '%s' "${target#$HOME/}" | tr '/' '_')"
  cp -p "$target" "${dir}/${flat}"
  printf '%s\n' "$target" >> "${dir}/MANIFEST"
}

# === Writing

# fs_write <dest> <mode>, content on stdin. Backs up first, always.
fs_write() {
  local dest="$1"
  local mode="${2:-644}"

  fs_backup "$dest"

  if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
    cat >/dev/null
    ui_dry "write ${dest} (mode ${mode})"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"
  cat > "$dest"
  chmod "$mode" "$dest"
}

# fs_install_asset <asset-name> <dest> [mode]. Copies a file out of
# lib/assets, which is the only place a config file's content is written
# down. Two modules installing the same asset install the same bytes.
fs_install_asset() {
  local asset="$1"
  local dest="$2"
  local mode="${3:-644}"
  local src="${IPILE_LIB}/assets/${asset}"

  if [ ! -f "$src" ]; then
    ui_err "Missing asset: ${asset}"
    return 1
  fi

  fs_write "$dest" "$mode" < "$src"
}

# fs_assets_match <asset-name> <dest>. True when the file on disk is
# byte-identical to the shipped asset. This is how dotfiles detect().
fs_assets_match() {
  local src="${IPILE_LIB}/assets/$1"
  local dest="$2"
  [ -f "$src" ] && [ -f "$dest" ] && cmp -s "$src" "$dest"
}

# === Appending
#
# Appending is always guarded. A block the tool already wrote is never
# written twice, and a block someone else wrote is never rewritten.

# fs_append_once <file> <marker>, content on stdin.
# The marker is grepped for as a fixed string.
fs_append_once() {
  local file="$1"
  local marker="$2"

  if [ -f "$file" ] && grep -qF "$marker" "$file" 2>/dev/null; then
    cat >/dev/null
    return 1
  fi

  if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
    cat >/dev/null
    ui_dry "append to ${file} (marker: ${marker})"
    return 0
  fi

  fs_backup "$file"
  mkdir -p "$(dirname "$file")"
  cat >> "$file"
  return 0
}

fs_has_marker() {
  local file="$1"
  local marker="$2"
  [ -f "$file" ] && grep -qF "$marker" "$file" 2>/dev/null
}

# === Portability

# sed -i is not portable between GNU and BSD.
fs_sed_inplace() {
  if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
    ui_dry "sed -i $*"
    return 0
  fi
  if [ "$IPILE_OS" = "mac" ]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

fs_mkdir() {
  local dir="$1"
  local mode="${2:-755}"
  if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
    [ -d "$dir" ] || ui_dry "mkdir -p ${dir} (mode ${mode})"
    return 0
  fi
  mkdir -p "$dir"
  chmod "$mode" "$dir"
}

# === Shell rc files
#
# fs_shell_rcs. Prints every rc file worth writing a shell function into,
# one per line. Unlike the old scripts this is not "zsh or else bash": a
# user with both gets both, so the helpers work in whichever shell they
# open next.
fs_shell_rcs() {
  local found=0
  local rc
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$rc" ]; then
      printf '%s\n' "$rc"
      found=1
    fi
  done
  # A login-only macOS setup often has .bash_profile and no .bashrc.
  if [ "$found" -eq 0 ] && [ -f "$HOME/.bash_profile" ]; then
    printf '%s\n' "$HOME/.bash_profile"
    found=1
  fi
  [ "$found" -eq 1 ]
}

# fs_warn_unsupported_shells. fish and nushell cannot source a bash
# function, and silently doing nothing is how the old script lost people.
fs_warn_unsupported_shells() {
  local shell_name
  shell_name="$(basename "${SHELL:-}")"
  case "$shell_name" in
    fish|nu)
      ui_warn "Your shell is ${shell_name}. The gclone and gitprofile helpers are bash functions and will not load there."
      ui_info "Everything else on this machine still works. Only the two helpers are affected."
      ;;
  esac
}
