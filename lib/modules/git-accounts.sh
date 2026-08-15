#!/usr/bin/env bash
# Several git identities on one machine, with the right one selected
# automatically per repository.
#
# The glue is the SSH host alias. Each profile gets a Host block mapping
# a name like github-work to the real host with its own key. A repository
# cloned through that alias has it baked into .git/config, so every future
# push uses the right key with nothing to remember.
#
# This module is additive. It reads what is already on the machine first,
# reports what it found including anything broken, and only then asks how
# many more you want. Answering 0 is a supported path: running it purely
# to repair or rename what exists is a real use case.

MODULE_TITLE="Multiple git accounts"
MODULE_EMOJI="👥"
MODULE_DESC="Several identities, one per remote"
MODULE_NEEDS="git-install"

describe() {
  cat <<'TXT'
  Holds any number of git identities on one machine.

    - Reads every profile already configured and reports it, including
      profiles that are half set up and why
    - Adds as many new accounts as you ask for, and never touches the
      ones already there
    - Per account: SSH key, SSH config block, host registration, a
      connection test that retries until it passes, and a profile config
      with signing enabled
    - Picks which identity is the global default

  Answering 0 to "how many more" is fine. The scan and repair still run.

  Files it owns:
    ~/.gitidentities        one line per profile
    ~/.gitconfig-<alias>    that profile's name, email, signing key
    ~/.ssh/config           a Host block per profile
    ~/.ssh/id_ed25519_*     one keypair per profile
TXT
}

detect() {
  local count=0
  local full
  for full in $(ident_all_full_aliases 2>/dev/null); do
    count=$((count + 1))
    ident_is_complete "$full" || return 2
  done
  [ "$count" -gt 0 ] || return 1
  return 0
}

# === Existing profiles

# Folds a global identity that predates this tool into a named profile,
# so someone who ran plain git for years does not lose it or end up with
# it duplicated as a second account.
accounts_fold_orphan() {
  local name email alias full key
  name="$(git config --global user.name 2>/dev/null || true)"
  email="$(git config --global user.email 2>/dev/null || true)"

  [ -n "$name" ] && [ -n "$email" ] || return 0
  [ "$(ident_all_full_aliases | wc -l | tr -d ' ')" = "0" ] || return 0

  echo ""
  ui_info "Found a global git identity that is not yet a named profile:"
  ui_info "  ${name} <${email}>"
  echo ""
  ui_confirm "Turn it into a named profile so it can sit alongside the others?" "y" || return 0

  ui_ask "Give it a short alias (personal, work, client):" "personal" alias || return 1
  full="$(ident_full_alias "github.com" "$alias")"
  key="$(ident_key_path "$alias")"

  ident_write_gitconfig "$alias" "$name" "$email" "${key}.pub"
  ident_write_ssh_block "$full" "github.com" "$key"
  ident_write_map_line "$full" "$name" "$email" "github.com" ""
  ui_ok "Existing identity folded in as ${full}."
}

# Renaming moves all four sources together. Doing three of the four is
# what leaves the drift this module exists to report.
accounts_offer_rename() {
  local full="$1"
  local short new_short new_full host
  short="$(ident_short_alias "$full")"
  host="$(ident_host "$full")"

  ui_ask "Alias '${short}': press Enter to keep it, or type a new one:" "$short" new_short || return 0
  [ "$new_short" = "$short" ] && return 0

  new_full="$(ident_full_alias "$host" "$new_short")"
  ui_info "Renaming ${full} to ${new_full}..."

  [ -f "$HOME/.gitconfig-${short}" ] && \
    run mv "$HOME/.gitconfig-${short}" "$HOME/.gitconfig-${new_short}"

  local key new_key
  key="$(ident_key_path "$short")"
  new_key="$(ident_key_path "$new_short")"
  if [ -f "$key" ]; then
    run mv "$key" "$new_key"
    [ -f "${key}.pub" ] && run mv "${key}.pub" "${new_key}.pub"
  fi

  if fs_has_marker "$SSH_CONFIG" "Host ${full}"; then
    fs_backup "$SSH_CONFIG"
    fs_sed_inplace "s|Host ${full}$|Host ${new_full}|" "$SSH_CONFIG"
    fs_sed_inplace "s|id_ed25519_${short}|id_ed25519_${new_short}|g" "$SSH_CONFIG"
  fi

  if fs_has_marker "$IDENTITIES_FILE" "${full}|"; then
    fs_backup "$IDENTITIES_FILE"
    # The delimiter cannot be | here: the field separator is itself a pipe.
    fs_sed_inplace "s#^${full}|#${new_full}|#" "$IDENTITIES_FILE"
  fi

  ui_ok "Renamed to ${new_full}."
}

# Repairs the sources a profile is missing, without asking for anything
# it can read off the sources that do exist.
accounts_repair() {
  local full="$1"
  local short host probe name email
  short="$(ident_short_alias "$full")"
  host="$(ident_host "$full")"
  probe="$(ident_probe "$full")"

  [ "$probe" = "ICSK" ] && return 0

  name="$(ident_name "$full" 2>/dev/null || true)"
  email="$(ident_email "$full" 2>/dev/null || true)"
  if [ -z "$name" ] && [ -f "$HOME/.gitconfig-${short}" ]; then
    name="$(git config -f "$HOME/.gitconfig-${short}" user.name 2>/dev/null || true)"
    email="$(git config -f "$HOME/.gitconfig-${short}" user.email 2>/dev/null || true)"
  fi

  echo ""
  ui_warn "${full} is incomplete: $(ident_explain_probe "$probe")"
  ui_confirm "Repair it?" "y" || return 0

  [ -n "$name" ]  || ui_ask "Full name for ${full}:" "" name  || return 1
  [ -n "$email" ] || ui_ask "Email for ${full}:" "" email || return 1

  local key
  key="$(ident_key_path "$short")"

  [ "${probe:3:1}" = "." ] && ident_ensure_key "$key" "$email" "$full"
  [ "${probe:2:1}" = "." ] && ident_write_ssh_block "$full" "$host" "$key"
  [ "${probe:1:1}" = "." ] && ident_write_gitconfig "$short" "$name" "$email" "${key}.pub"
  [ "${probe:0:1}" = "." ] && ident_write_map_line "$full" "$name" "$email" "$host" ""

  ident_register_signer "$email" "${key}.pub"
  ui_ok "${full} repaired."
}

# === Adding

accounts_add_one() {
  local n="$1"
  local total="$2"
  local alias name username email host full key label

  echo ""
  ui_rule
  echo -e "  ${BOLD}New account ${n} of ${total}${NC}"
  ui_rule
  echo ""

  ui_ask "Short alias for this account (personal, work, client):" "" alias || return 1
  ui_ask "Full name, as it appears on commits:" "" name || return 1
  ui_ask "Git host:" "github.com" host || return 1
  ui_ask "Username on ${host}:" "" username || return 1
  ui_ask "Email address:" "" email || return 1

  full="$(ident_full_alias "$host" "$alias")"
  key="$(ident_key_path "$alias")"
  label="$(hostname 2>/dev/null || printf 'this machine') ${alias}"

  echo ""
  ui_info "Alias     ${full}"
  ui_info "Name      ${name}"
  ui_info "Host      ${host}"
  ui_info "Username  ${username}"
  ui_info "Email     ${email}"
  echo ""
  ui_confirm "Add this account?" "y" || {
    ui_skip "Skipped account ${n}."
    return 0
  }

  # An alias that already exists must not be silently overwritten. This
  # module's contract is that it never damages what is already there.
  if [ -f "$HOME/.gitconfig-${alias}" ] || fs_has_marker "$SSH_CONFIG" "Host ${full}"; then
    ui_warn "A profile called ${full} already exists."
    ui_confirm "Continue and update it in place?" "n" || {
      ui_skip "Left ${full} untouched."
      return 0
    }
  fi

  ident_ensure_key "$key" "$email" "$full" || return 1
  ident_write_ssh_block "$full" "$host" "$key"
  ident_add_to_agent "$key"

  if ! ident_gh_upload "${key}.pub" "$label"; then
    ident_manual_register "${key}.pub" "$host" "$username" "$label"
  fi

  ident_test_connection "$full" "${key}.pub" "$host" "$username" "$label" || true

  ident_write_gitconfig "$alias" "$name" "$email" "${key}.pub"
  ident_write_map_line "$full" "$name" "$email" "$host" "$username"
  ident_register_signer "$email" "${key}.pub"

  ui_ok "${full} is configured."
  return 0
}

# === The global default
#
# Any repository that bypasses the hook system still has to commit under
# a known identity rather than a blank name.
accounts_pick_default() {
  local lines=""
  local count=0
  local full name email choice

  for full in $(ident_all_full_aliases); do
    name="$(ident_name "$full" 2>/dev/null || true)"
    email="$(ident_email "$full" 2>/dev/null || true)"
    [ -n "$name" ] || continue
    count=$((count + 1))
    lines="${lines}${full}|${name}|${email}
"
  done

  [ "$count" -gt 0 ] || return 0

  echo ""
  ui_rule
  echo -e "  ${BOLD}Which profile is the global default?${NC}"
  echo -e "  ${DIM}Used by any repository that has no identity of its own yet.${NC}"
  ui_rule
  echo ""

  # Built as two parallel indexed arrays rather than one associative
  # array, because macOS ships bash 3.2 and has no associative arrays.
  local menu_labels=()
  local menu_aliases=()
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    menu_aliases+=("$(printf '%s' "$l" | cut -d'|' -f1)")
    menu_labels+=("$(printf '%s' "$l" | cut -d'|' -f2) <$(printf '%s' "$l" | cut -d'|' -f3)>")
  done <<EOF
$lines
EOF

  ui_menu choice "${menu_labels[@]}"

  local picked="${menu_aliases[$((choice - 1))]}"
  local short
  short="$(ident_short_alias "$picked")"
  name="$(ident_name "$picked")"
  email="$(ident_email "$picked")"
  local pub
  pub="$(ident_key_path "$short").pub"

  run git config --global user.name "$name"
  run git config --global user.email "$email"
  run git config --global gpg.format ssh
  if [ -f "$pub" ]; then
    run git config --global user.signingkey "$pub"
    ident_register_signer "$email" "$pub"
  fi
  run git config --global commit.gpgsign true
  run git config --global tag.gpgsign true

  ui_ok "Global default: ${name} <${email}>  (${picked})"
}

# === apply

apply() {
  ident_init

  echo ""
  echo -e "  ${BOLD}Profiles already on this machine${NC}"
  echo ""

  if ident_scan; then
    echo ""
    ui_info "${IDENT_SCAN_COUNT} profile(s) found, ${IDENT_SCAN_BROKEN} incomplete."
  else
    ui_info "None found."
  fi
  echo ""

  accounts_fold_orphan || return 1

  local full
  if [ "$(ident_all_full_aliases | wc -l | tr -d ' ')" != "0" ]; then
    if ui_confirm "Rename any of the existing profiles?" "n"; then
      for full in $(ident_all_full_aliases); do
        accounts_offer_rename "$full"
      done
    fi

    if [ "${IDENT_SCAN_BROKEN:-0}" -gt 0 ]; then
      for full in $(ident_all_full_aliases); do
        accounts_repair "$full" || return 1
      done
    fi
  fi

  echo ""
  local count
  ui_ask_int "How many NEW accounts do you want to add? (0 to add none)" "0" count

  local i=1
  while [ "$i" -le "$count" ]; do
    accounts_add_one "$i" "$count" || return 1
    i=$((i + 1))
  done

  accounts_pick_default

  echo ""
  ui_info "Clone as a chosen identity with:  gclone <url>"
  ui_info "See who a repository commits as:  git whoami"
  ui_info "List profiles:                    gitprofile"

  return 0
}

verify() {
  local count=0
  local full
  for full in $(ident_all_full_aliases 2>/dev/null); do
    count=$((count + 1))
  done
  [ "$count" -gt 0 ] || return 1
  [ -f "$IDENTITIES_FILE" ] || return 1
  return 0
}
