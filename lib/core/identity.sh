#!/usr/bin/env bash
# Git identity profiles: discovery, reconciliation, key registration.
#
# THE HOOK LIST LIVES HERE
#
# Every client-side hook ipile installs, in one place, because both the
# git-hooks module and doctor need it and a list written twice is a list
# that drifts. doctor once checked eight of these while the module
# installed sixteen, and reported all green.
#
# Excluded on purpose: reference-transaction and post-index-change, which
# fire hundreds of times per fetch; the server-side hooks, which never run
# on a developer's machine; and fsmonitor-watchman, which core.fsmonitor
# selects rather than the hooks directory.
IPILE_GIT_HOOKS="pre-commit pre-push commit-msg prepare-commit-msg post-commit post-merge post-checkout pre-rebase post-rewrite pre-merge-commit applypatch-msg pre-applypatch post-applypatch pre-auto-gc push-to-checkout sendemail-validate"
#
# THE FOUR SOURCES OF TRUTH
#
# A fully configured profile exists in four independent places:
#
#   1. ~/.gitidentities            one line, read by the hooks and helpers
#   2. ~/.gitconfig-<alias>        name, email, signing key
#   3. ~/.ssh/config               a Host block mapping the alias to a host
#   4. ~/.ssh/id_ed25519_<alias>   the keypair itself
#
# They drift. A profile listed in ~/.gitidentities whose key was deleted,
# a Host block pointing at nothing, a keypair nobody references. The old
# script only globbed ~/.gitconfig-* and so could not see any of that.
# ident_scan looks at all four and reports per profile.
#
# THE IDENTITY FILE FORMAT
#
#   github-work|Moses Bamtefa|moses@work.com|github.com|mosesbam
#
# Fields 4 and 5 (host, username) are new and optional. Everything that
# reads this file uses cut -f1..3, so a file written by an older version
# still works and hooks written by an older version still parse ours.

IDENTITIES_FILE="$HOME/.gitidentities"
SSH_CONFIG="$HOME/.ssh/config"

ident_init() {
  fs_mkdir "$HOME/.ssh" 700
  if [ "${IPILE_DRY_RUN:-0}" != "1" ]; then
    touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    touch "$IDENTITIES_FILE"
  fi
}

# === Naming
#
# ident_host_label <host>. The prefix used for the SSH alias. The three
# common hosts keep their short names so "github-work" stays "github-work"
# for anyone upgrading. Anything else becomes its dashed domain, which is
# ugly but unambiguous and cannot collide.
ident_host_label() {
  case "$1" in
    github.com) printf 'github' ;;
    gitlab.com) printf 'gitlab' ;;
    bitbucket.org) printf 'bitbucket' ;;
    *) printf '%s' "$(printf '%s' "$1" | tr '.' '-')" ;;
  esac
}

ident_full_alias() {
  local host="$1"
  local alias="$2"
  printf '%s-%s' "$(ident_host_label "$host")" "$alias"
}

ident_key_path() {
  printf '%s/.ssh/id_ed25519_%s' "$HOME" "$1"
}

# ident_short_alias <full-alias>. Strips the host prefix back off.
ident_short_alias() {
  printf '%s' "${1#*-}"
}

# === Reading

ident_line() {
  local full="$1"
  [ -f "$IDENTITIES_FILE" ] || return 1
  grep "^${full}|" "$IDENTITIES_FILE" 2>/dev/null | head -1
}

ident_field() {
  local full="$1"
  local n="$2"
  local line
  line="$(ident_line "$full")" || return 1
  [ -n "$line" ] || return 1
  printf '%s' "$line" | cut -d'|' -f"$n"
}

ident_name() { ident_field "$1" 2; }
ident_email() { ident_field "$1" 3; }

ident_host() {
  local h
  h="$(ident_field "$1" 4)" || h=""
  [ -n "$h" ] && printf '%s' "$h" || printf 'github.com'
}

ident_username() { ident_field "$1" 5; }

# ident_all_full_aliases. Every profile named anywhere, deduplicated.
# The union matters: a profile that exists only as an orphan key or only
# as a Host block still needs to show up in the report.
ident_all_full_aliases() {
  {
    if [ -f "$IDENTITIES_FILE" ]; then
      cut -d'|' -f1 "$IDENTITIES_FILE" 2>/dev/null | grep -v '^$' || true
    fi

    local f alias
    for f in "$HOME"/.gitconfig-*; do
      [ -f "$f" ] || continue
      alias="${f##*/.gitconfig-}"
      # A bare gitconfig carries no host, so assume the historical default.
      printf 'github-%s\n' "$alias"
    done

    if [ -f "$SSH_CONFIG" ]; then
      grep -E '^[[:space:]]*Host[[:space:]]+' "$SSH_CONFIG" 2>/dev/null \
        | awk '{print $2}' \
        | grep -E '^(github|gitlab|bitbucket|[a-z0-9-]+)-.+' || true
    fi
  } | sort -u | grep -v '^$'
}

# === Reconciliation
#
# ident_probe <full-alias>. Prints a four-character presence map:
#   I = in ~/.gitidentities   C = has ~/.gitconfig-<alias>
#   S = has an ssh Host block K = has a keypair
# A missing source prints a dot in its slot.
ident_probe() {
  local full="$1"
  local short
  short="$(ident_short_alias "$full")"
  local out=""

  ident_line "$full" >/dev/null 2>&1 && out="${out}I" || out="${out}."
  [ -f "$HOME/.gitconfig-${short}" ] && out="${out}C" || out="${out}."
  fs_has_marker "$SSH_CONFIG" "Host ${full}" && out="${out}S" || out="${out}."
  [ -f "$(ident_key_path "$short").pub" ] && out="${out}K" || out="${out}."

  printf '%s' "$out"
}

ident_is_complete() {
  [ "$(ident_probe "$1")" = "ICSK" ]
}

# ident_explain_probe <probe>. Turns the map into the sentence a user can
# act on. Silent when the profile is complete.
ident_explain_probe() {
  local p="$1"
  local missing=""
  case "$p" in *.*) ;; *) return 0 ;; esac

  [ "${p:0:1}" = "." ] && missing="${missing}, not in ~/.gitidentities"
  [ "${p:1:1}" = "." ] && missing="${missing}, no ~/.gitconfig file"
  [ "${p:2:1}" = "." ] && missing="${missing}, no SSH config block"
  [ "${p:3:1}" = "." ] && missing="${missing}, no SSH key on disk"
  printf '%s' "${missing#, }"
}

# ident_scan. The table printed before anything is asked. Returns the
# number of profiles found via IDENT_SCAN_COUNT and how many are broken
# via IDENT_SCAN_BROKEN.
ident_scan() {
  IDENT_SCAN_COUNT=0
  IDENT_SCAN_BROKEN=0

  local full probe name email why
  local found=""

  for full in $(ident_all_full_aliases); do
    found="yes"
    IDENT_SCAN_COUNT=$((IDENT_SCAN_COUNT + 1))
    probe="$(ident_probe "$full")"
    name="$(ident_name "$full" 2>/dev/null || true)"
    email="$(ident_email "$full" 2>/dev/null || true)"

    if [ -z "$name" ] && [ -f "$HOME/.gitconfig-$(ident_short_alias "$full")" ]; then
      name="$(git config -f "$HOME/.gitconfig-$(ident_short_alias "$full")" user.name 2>/dev/null || true)"
      email="$(git config -f "$HOME/.gitconfig-$(ident_short_alias "$full")" user.email 2>/dev/null || true)"
    fi

    if [ "$probe" = "ICSK" ]; then
      printf "  %b✓%b  %-22s %s %b<%s>%b\n" \
        "$THEME_GREEN" "$NC" "$full" "${name:-unknown}" "$DIM" "${email:-unknown}" "$NC"
    else
      IDENT_SCAN_BROKEN=$((IDENT_SCAN_BROKEN + 1))
      why="$(ident_explain_probe "$probe")"
      printf "  %b!%b  %-22s %s %b<%s>%b\n" \
        "$YELLOW" "$NC" "$full" "${name:-unknown}" "$DIM" "${email:-unknown}" "$NC"
      printf "     %b%s%b\n" "$DIM" "$why" "$NC"
    fi
  done

  [ -n "$found" ] || return 1
  return 0
}

# === Writing a profile

# ident_write_ssh_block <full-alias> <host> <key-path>
ident_write_ssh_block() {
  local full="$1"
  local host="$2"
  local key="$3"

  if fs_has_marker "$SSH_CONFIG" "Host ${full}"; then
    ui_info "SSH config already has a block for ${full}. Left alone."
    return 0
  fi

  printf '\nHost %s\n  HostName %s\n  User git\n  IdentityFile %s\n' \
    "$full" "$host" "${key/#$HOME/\~}" \
    | fs_append_once "$SSH_CONFIG" "Host ${full}"
  ui_ok "SSH config block added: Host ${full}"
}

# ident_write_gitconfig <short-alias> <name> <email> <pub-key>
ident_write_gitconfig() {
  local short="$1"
  local name="$2"
  local email="$3"
  local pub="$4"

  {
    printf '[user]\n  name = %s\n  email = %s\n' "$name" "$email"
    if [ -f "$pub" ] || [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
      printf '  signingkey = %s\n[gpg]\n  format = ssh\n[commit]\n  gpgsign = true\n[tag]\n  gpgsign = true\n' "$pub"
    fi
  } | fs_write "$HOME/.gitconfig-${short}" 644

  ui_ok "Profile config written: ~/.gitconfig-${short}"
}

# ident_write_map_line <full-alias> <name> <email> <host> <username>
ident_write_map_line() {
  local full="$1"
  printf '%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" \
    | fs_append_once "$IDENTITIES_FILE" "${full}|" \
    && ui_ok "Identity map updated." || true
}

# === allowed_signers
#
# Signing and verifying are separate settings. Without this file git signs
# correctly and then reports "No signature" on verify, which reads as a
# signing failure and sends people chasing a problem they do not have.
# The old git-multiple-accounts.sh never wrote it, so a multi-account
# machine always had this bug. Every path that enables signing calls this.
ident_register_signer() {
  local email="$1"
  local pub="$2"
  local file="$HOME/.ssh/allowed_signers"

  [ -f "$pub" ] || return 0

  if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
    ui_dry "register ${email} in ~/.ssh/allowed_signers"
    return 0
  fi

  touch "$file"
  chmod 600 "$file"
  local line
  line="$(printf '%s %s' "$email" "$(cat "$pub")")"
  if ! grep -qxF "$line" "$file" 2>/dev/null; then
    fs_backup "$file"
    printf '%s\n' "$line" >>"$file"
  fi
  run git config --global gpg.ssh.allowedSignersFile "$file"
}

# === Key generation

# ident_ensure_key <key-path> <email> <label>
# Never clobbers silently. An existing key is reused unless the user says
# otherwise, and the prompt defaults to reusing it.
ident_ensure_key() {
  local key="$1"
  local email="$2"
  local label="$3"
  local pub="${key}.pub"

  if [ -f "$pub" ]; then
    ui_warn "A key already exists at ${key}"
    if ui_confirm "Regenerate it? This destroys the existing key and any access it has." "n"; then
      fs_backup "$key"
      fs_backup "$pub"
      run ssh-keygen -t ed25519 -C "$email" -f "$key" -N "" -q
      ui_ok "New key generated for ${label}."
    else
      ui_info "Reusing the existing key at ${key}"
    fi
    return 0
  fi

  local passphrase=""
  # An empty passphrase is the convenient default and was the only option
  # before. Offering the choice is what makes the tool usable by anyone
  # whose policy forbids unencrypted private keys.
  if ui_confirm "Protect this key with a passphrase?" "n"; then
    ui_info "ssh-keygen will prompt for it twice."
    run ssh-keygen -t ed25519 -C "$email" -f "$key" -q
  else
    run ssh-keygen -t ed25519 -C "$email" -f "$key" -N "$passphrase" -q
  fi
  ui_ok "Key generated at ${key}"
}

ident_add_to_agent() {
  local key="$1"
  if ! ssh-add -l >/dev/null 2>&1; then
    eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
  fi
  run ssh-add "$key" >/dev/null 2>&1 || ui_warn "Could not add the key to ssh-agent. Not fatal."

  if os_is_wsl; then
    ui_warn "On WSL the ssh-agent does not survive a terminal restart."
    ui_info "Add 'eval \$(ssh-agent -s) && ssh-add ${key}' to your shell rc if pushes stop working."
  fi
}

# === Registering the key with the host

ident_print_key() {
  local pub="$1"
  echo ""
  ui_rule
  echo -e "${CYAN}"
  cat "$pub" 2>/dev/null || ui_dry "print ${pub}"
  echo -e "${NC}"
  ui_rule
  echo ""
}

ident_keys_url() {
  case "$1" in
    github.com) printf 'https://github.com/settings/keys' ;;
    gitlab.com) printf 'https://gitlab.com/-/user_settings/ssh_keys' ;;
    bitbucket.org) printf 'https://bitbucket.org/account/settings/ssh-keys/' ;;
    *) printf 'https://%s (your account SSH key settings)' "$1" ;;
  esac
}

# ident_gh_upload <pub> <label>. Uses the gh CLI when it is authenticated,
# which turns a six step copy and paste into one call. Returns non-zero
# whenever the manual path is still needed, so the caller always has a
# fallback.
ident_gh_upload() {
  local pub="$1"
  local label="$2"

  command -v gh >/dev/null 2>&1 || return 1
  gh auth status >/dev/null 2>&1 || return 1

  ui_info "The gh CLI is authenticated. It can register this key for you."
  ui_confirm "Upload the key with gh instead of pasting it by hand?" "y" || return 1

  local ok=0
  run gh ssh-key add "$pub" --title "$label" --type authentication || ok=1
  run gh ssh-key add "$pub" --title "${label} (signing)" --type signing || ok=1

  if [ "$ok" -eq 0 ]; then
    ui_ok "Key registered as both an authentication key and a signing key."
    return 0
  fi

  ui_warn "gh could not add the key. Falling back to the manual steps."
  return 1
}

# ident_manual_register <pub> <host> <username> <label>
# Both registrations are spelled out. A key added only as an
# authentication key authenticates fine and then fails to sign, which is
# the single most common way this setup ends up half working.
ident_manual_register() {
  local pub="$1"
  local host="$2"
  local username="$3"
  local label="$4"

  ident_print_key "$pub"

  echo -e "  ${BOLD}Add this key to ${host}${username:+ as ${username}}, twice:${NC}"
  echo ""
  echo -e "    ${YELLOW}1.${NC}  Open  ${BOLD}$(ident_keys_url "$host")${NC}"
  echo -e "    ${YELLOW}2.${NC}  Add it once with type ${BOLD}Authentication Key${NC}, title ${DIM}${label}${NC}"
  echo -e "    ${YELLOW}3.${NC}  Add the same key again with type ${BOLD}Signing Key${NC}, title ${DIM}${label} (signing)${NC}"
  echo ""
  echo -e "  ${DIM}Authentication lets you push. Signing is what makes commits show as verified."
  echo -e "  Adding only the first is the usual reason signing silently fails.${NC}"
  echo ""

  ui_type_word "done" "Type 'done' when both are added:"
}

# === Connection test with retry
#
# The old script warned once and moved on, leaving a half configured
# profile with no signal that anything was left to do. This loops until it
# passes or the user explicitly gives up.
#
# ident_test_connection <full-alias> <pub> <host> <username> <label>
# Returns 0 if verified, 1 if the user chose to move on unverified.
ident_test_connection() {
  local full="$1"
  local pub="$2"
  local host="$3"
  local username="$4"
  local label="$5"

  if [ "${IPILE_DRY_RUN:-0}" = "1" ]; then
    ui_dry "ssh -T git@${full}"
    return 0
  fi

  local result choice
  while true; do
    ui_info "Testing the SSH connection for ${full}..."
    result="$(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -T "git@${full}" 2>&1 || true)"
    echo -e "  ${DIM}${result}${NC}"

    if printf '%s' "$result" | grep -qE "successfully authenticated|Welcome to GitLab|logged in as"; then
      ui_ok "Connection verified for ${full}."
      return 0
    fi

    if [ "${IPILE_ASSUME_YES:-0}" = "1" ]; then
      ui_warn "Could not verify ${full}. Continuing because this is a non-interactive run."
      return 1
    fi

    echo ""
    ui_warn "Could not verify ${full}."
    echo ""
    ui_menu choice \
      "I have added the key now, test again" \
      "Show me the public key again" \
      "Show me the registration steps again" \
      "Regenerate the keypair and start this profile over" \
      "Continue without verifying, I will fix it later"

    case "$choice" in
      1) echo "" ;;
      2) ident_print_key "$pub" ;;
      3) ident_manual_register "$pub" "$host" "$username" "$label" ;;
      4)
        local key="${pub%.pub}"
        fs_backup "$key"
        fs_backup "$pub"
        run ssh-keygen -t ed25519 -C "$username" -f "$key" -N "" -q
        ui_ok "New key generated."
        ident_add_to_agent "$key"
        ident_manual_register "$pub" "$host" "$username" "$label"
        ;;
      5)
        ui_warn "Moving on. Test it yourself later with: ssh -T git@${full}"
        return 1
        ;;
    esac
  done
}
