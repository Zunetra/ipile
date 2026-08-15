#!/usr/bin/env bash
# Read only. Touches nothing, installs nothing.
#
# Doctor calls the same verify() each module runs after applying itself,
# so the diagnostic and the installer can never disagree about what
# "installed" means. It then adds the checks that only make sense across
# modules: does signing actually verify, is every profile whole, did
# core.hooksPath break anything.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd -P)"
IPILE_HOME="$(dirname "$SCRIPT_DIR")"
IPILE_LIB="${IPILE_HOME}/lib"
IPILE_VAR="${IPILE_VAR:-${IPILE_HOME}/var}"
IPILE_VERSION="$(cat "${IPILE_HOME}/VERSION" 2>/dev/null || printf 'dev')"
IPILE_RUN_ID="doctor"
IPILE_DRY_RUN=0
IPILE_ASSUME_YES=1
export IPILE_HOME IPILE_LIB IPILE_VAR IPILE_VERSION IPILE_RUN_ID IPILE_DRY_RUN IPILE_ASSUME_YES

# shellcheck source=/dev/null
. "${IPILE_LIB}/core/ui.sh"
# shellcheck source=/dev/null
. "${IPILE_LIB}/core/fs.sh"
# shellcheck source=/dev/null
. "${IPILE_LIB}/core/os.sh"
# shellcheck source=/dev/null
. "${IPILE_LIB}/core/state.sh"
# shellcheck source=/dev/null
. "${IPILE_LIB}/core/identity.sh"
# shellcheck source=/dev/null
. "${IPILE_LIB}/core/registry.sh"

CHECK_NETWORK=0
[ "${1:-}" = "--network" ] && CHECK_NETWORK=1

PROBLEMS=0

ok()   { printf "  %b✓%b  %s\n" "$THEME_GREEN" "$NC" "$*"; }
bad()  { printf "  %b✗%b  %s\n" "$RED" "$NC" "$*"; PROBLEMS=$((PROBLEMS + 1)); }
warn() { printf "  %b!%b  %s\n" "$YELLOW" "$NC" "$*"; }
note() { printf "     %b%s%b\n" "$DIM" "$*" "$NC"; }

os_detect || exit 1

ui_banner "ipile doctor" "$IPILE_DISTRO"

# === Modules

echo -e "  ${BOLD}Modules${NC}"
echo ""
for id in $IPILE_MODULES; do
  registry_load "$id" >/dev/null 2>&1 || { bad "${id} failed to load"; continue; }
  if verify >/dev/null 2>&1; then
    ok "$(printf '%-14s %s' "$id" "$MODULE_TITLE")"
  else
    status=0
    detect >/dev/null 2>&1 || status=$?
    if [ "$status" -eq 1 ]; then
      warn "$(printf '%-14s %s' "$id" "not set up")"
    else
      bad "$(printf '%-14s %s' "$id" "set up but not verifying")"
    fi
  fi
done

# === Commit signing
#
# The check the old tool never had. Signing and verifying are separate
# settings, so a machine can sign every commit correctly and still report
# "No signature" forever.

echo ""
echo -e "  ${BOLD}Commit signing${NC}"
echo ""

fmt="$(git config --global gpg.format 2>/dev/null || true)"
signer="$(git config --global user.signingkey 2>/dev/null || true)"
allowed="$(git config --global gpg.ssh.allowedSignersFile 2>/dev/null || true)"
gpgsign="$(git config --global commit.gpgsign 2>/dev/null || true)"

if [ "$gpgsign" != "true" ]; then
  warn "Commit signing is off"
  note "Turn it on with: ipile git identity"
else
  ok "commit.gpgsign is on"

  [ "$fmt" = "ssh" ] && ok "gpg.format is ssh" || bad "gpg.format is '${fmt:-unset}', expected ssh"

  if [ -n "$signer" ] && [ -f "$signer" ]; then
    ok "Signing key exists: ${signer}"
  else
    bad "Signing key missing or unset: ${signer:-unset}"
  fi

  if [ -n "$allowed" ] && [ -f "$allowed" ]; then
    ok "allowed_signers exists: ${allowed}"
    email="$(git config --global user.email 2>/dev/null || true)"
    if [ -n "$email" ] && grep -q "^${email} " "$allowed" 2>/dev/null; then
      ok "Your email is listed in it, so verification will work"
    else
      bad "Your email is not in allowed_signers"
      note "git will sign correctly and still report 'No signature' on verify"
    fi
  else
    bad "No allowed_signers file"
    note "This is why 'git log --show-signature' says No signature"
    note "Fix with: ipile git identity"
  fi
fi

# === Identity profiles

echo ""
echo -e "  ${BOLD}Git profiles${NC}"
echo ""

if ident_scan; then
  echo ""
  if [ "${IDENT_SCAN_BROKEN:-0}" -gt 0 ]; then
    bad "${IDENT_SCAN_BROKEN} of ${IDENT_SCAN_COUNT} profile(s) are incomplete"
    note "Repair them with: ipile git accounts"
  else
    ok "All ${IDENT_SCAN_COUNT} profile(s) are complete"
  fi
else
  warn "No profiles configured"
  note "Add some with: ipile git accounts"
fi

# === Hooks
#
# core.hooksPath is global. Anything installed there that does not chain
# to the repository's own hook silently disables that hook everywhere,
# which is how husky and lefthook break machine wide.

echo ""
echo -e "  ${BOLD}Hooks${NC}"
echo ""

hooks_path="$(git config --global core.hooksPath 2>/dev/null || true)"
if [ -z "$hooks_path" ]; then
  warn "core.hooksPath is not set, so the identity hooks are not active"
else
  ok "core.hooksPath is ${hooks_path}"
  for h in $IPILE_GIT_HOOKS; do
    if [ -f "${hooks_path}/${h}" ]; then
      if [ -x "${hooks_path}/${h}" ]; then
        # The handover resolves the repo's hook via rev-parse --git-dir
        # rather than a literal .git/hooks path, so look for the variable
        # it lands in, not the path.
        # Case insensitive: the generated passthroughs use LOCAL_HOOK, the
        # two hand written hooks use a chain_local helper with a lowercase
        # local_hook inside it. Both are a valid handover.
        if grep -qiE 'local_hook|chain_local|\.git/hooks/' "${hooks_path}/${h}" 2>/dev/null; then
          ok "${h} installed and chains to the repository's own hook"
        else
          bad "${h} installed but does NOT chain"
          note "Repository-local ${h} hooks are being silently skipped"
        fi
      else
        bad "${h} exists but is not executable, so git ignores it"
      fi
    fi
  done
fi

# === Shell helpers

echo ""
echo -e "  ${BOLD}Shell helpers${NC}"
echo ""

found_helper=0
for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
  [ -f "$rc" ] || continue
  if grep -q 'gclone()' "$rc" 2>/dev/null; then
    ok "gclone in $(basename "$rc")"
    found_helper=1
  fi
  if grep -q 'gitprofile()' "$rc" 2>/dev/null; then
    ok "gitprofile in $(basename "$rc")"
  fi
done
[ "$found_helper" -eq 0 ] && warn "gclone and gitprofile are not in any rc file"

shell_name="$(basename "${SHELL:-}")"
case "$shell_name" in
  fish|nu)
    warn "Your shell is ${shell_name}, which cannot load these bash functions"
    ;;
esac

# === PATH

echo ""
echo -e "  ${BOLD}Environment${NC}"
echo ""

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ok "~/.local/bin is on PATH" ;;
  *) bad "~/.local/bin is not on PATH, so 'ipile' will vanish on a new shell" ;;
esac

os_is_wsl && warn "WSL: the ssh-agent does not persist across terminal restarts"
[ "$IPILE_PM" = "none" ] && bad "No supported package manager found on this system"

# === Network

if [ "$CHECK_NETWORK" -eq 1 ]; then
  echo ""
  echo -e "  ${BOLD}Connections${NC}"
  echo ""
  for full in $(ident_all_full_aliases 2>/dev/null); do
    result="$(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -T "git@${full}" 2>&1 || true)"
    if printf '%s' "$result" | grep -qE "successfully authenticated|Welcome to GitLab|logged in as"; then
      ok "${full} authenticates"
    else
      bad "${full} does not authenticate"
      note "Retry it with: ipile git accounts"
    fi
  done
else
  echo ""
  echo -e "  ${DIM}Connection tests skipped. Run 'ipile doctor --network' to include them.${NC}"
fi

# === Verdict

echo ""
ui_rule
if [ "$PROBLEMS" -eq 0 ]; then
  echo -e "  ${THEME_GREEN}${BOLD}No problems found.${NC}"
else
  echo -e "  ${BOLD}${PROBLEMS} problem(s) found.${NC}"
fi
ui_rule
echo ""

# Doctor reports, it does not gate. Exiting non-zero would break anyone
# running it in a shell with set -e just to look at the output.
exit 0
