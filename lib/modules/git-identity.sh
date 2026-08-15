#!/usr/bin/env bash
# One identity, one key, signing that actually verifies.
#
# This is the single account path. Someone who holds several identities
# wants git-accounts instead, and running both is fine: this module sets
# the global default that git-accounts later lets you choose between.

MODULE_TITLE="Git identity and SSH key"
MODULE_EMOJI="🔑"
MODULE_DESC="Your name, email, SSH key, signing"
MODULE_NEEDS="git-install"

describe() {
  cat <<'TXT'
  Sets your global git identity and gives you a working SSH key.

    - git config --global user.name and user.email
    - An ed25519 SSH key, with an optional passphrase
    - Registers the key with your git host, as both an authentication
      key and a signing key
    - Tests the connection, and retries with you until it works
    - Enables SSH commit and tag signing
    - Writes ~/.ssh/allowed_signers so local verification works too

  An existing key is reused, never overwritten without asking.
TXT
}

detect() {
  local name email fmt signer allowed
  name="$(git config --global user.name 2>/dev/null || true)"
  email="$(git config --global user.email 2>/dev/null || true)"

  [ -n "$name" ] && [ -n "$email" ] || return 1

  fmt="$(git config --global gpg.format 2>/dev/null || true)"
  signer="$(git config --global user.signingkey 2>/dev/null || true)"
  allowed="$(git config --global gpg.ssh.allowedSignersFile 2>/dev/null || true)"

  # Identity without signing, or signing without an allowed signers file,
  # is the half configured state the old script left people in.
  [ "$fmt" = "ssh" ] && [ -n "$signer" ] || return 2
  [ -n "$allowed" ] && [ -f "$allowed" ] || return 2

  return 0
}

apply() {
  ident_init

  local name email username host
  name="$(git config --global user.name 2>/dev/null || true)"
  email="$(git config --global user.email 2>/dev/null || true)"

  ui_ask "Your full name, as it should appear on commits:" "$name" name || return 1
  ui_ask "Your email address:" "$email" email || return 1
  ui_ask "Your git host:" "github.com" host || return 1
  ui_ask "Your username on ${host}:" "" username || return 1

  echo ""
  ui_info "Name      ${name}"
  ui_info "Email     ${email}"
  ui_info "Host      ${host}"
  ui_info "Username  ${username}"
  echo ""
  ui_confirm "Is that right?" "y" || {
    ui_warn "Nothing was changed. Run this module again to retry."
    return 1
  }

  run git config --global user.name "$name"
  run git config --global user.email "$email"
  ui_ok "Git identity set."

  # An existing key is worth more than a new one: it may already be
  # registered on hosts this tool knows nothing about.
  local key pub
  key="$HOME/.ssh/id_ed25519"
  if [ ! -f "${key}.pub" ] && [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    ui_info "No ed25519 key, but an RSA key exists. Reusing it."
    key="$HOME/.ssh/id_rsa"
  else
    ident_ensure_key "$key" "$email" "your identity" || return 1
  fi
  pub="${key}.pub"

  ident_add_to_agent "$key"

  local label
  label="$(hostname 2>/dev/null || printf 'this machine')"

  if ! ident_gh_upload "$pub" "$label"; then
    ident_manual_register "$pub" "$host" "$username" "$label"
  fi

  # The single account path talks to the host directly. There is no SSH
  # alias to go through, because there is only one key.
  ident_test_connection "$host" "$pub" "$host" "$username" "$label" || true

  ui_info "Enabling SSH commit signing..."
  run git config --global gpg.format ssh
  run git config --global user.signingkey "$pub"
  run git config --global commit.gpgsign true
  run git config --global tag.gpgsign true
  ident_register_signer "$email" "$pub"
  ui_ok "Commits and tags are signed, and verify locally."

  return 0
}

verify() {
  local name signer allowed
  name="$(git config --global user.name 2>/dev/null || true)"
  [ -n "$name" ] || return 1

  signer="$(git config --global user.signingkey 2>/dev/null || true)"
  [ -n "$signer" ] && [ -f "$signer" ] || return 1

  allowed="$(git config --global gpg.ssh.allowedSignersFile 2>/dev/null || true)"
  [ -n "$allowed" ] && [ -f "$allowed" ] || return 1

  return 0
}
