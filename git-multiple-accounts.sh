#!/usr/bin/env bash
# ============================================================
# git-multiple-accounts.sh
# by Olorunshogo · https://github.com/Olorunshogo
# ============================================================
#
# WHAT THIS SCRIPT DOES
# ---------------------
# Sets up a complete multi-account Git workflow on a single machine.
# After running it you can hold N separate GitHub identities, clone repos
# as any of them, and have every commit automatically signed and attributed
# to the right person with zero manual switching.
#
# HOW IT WORKS
# ------------
# The glue is the SSH alias. Each account gets a named Host block in
# ~/.ssh/config that maps a custom alias (e.g. github-personal) to
# github.com with a dedicated key:
#
#   Host github-personal
#     HostName github.com
#     User git
#     IdentityFile ~/.ssh/id_ed25519_personal
#
# When you clone using gclone instead of git clone:
#
#   gclone https://github.com/musathedev/my-repo.git
#   → pick identity → rewrites to → github-personal:musathedev/my-repo.git
#
# That alias is now baked into .git/config. Every future push automatically
# uses the right SSH key. No manual switching, ever.
#
# IDENTITY MAP  (~/.gitidentities)
# ---------------------------------
# One line per account:
#
#   github-personal|Musa The Dev|musa@email.com
#   github-work|Moses Bamtefa|moses@work.com
#
# The hook system, gclone wrapper, and gitprofile helper all read from this
# single file. You can hand-edit it at any time to add, remove, or rename.
#
# COMMIT IDENTITY  (global pre-commit hook)
# ------------------------------------------
# ~/.git-hooks/pre-commit fires on every commit in every repo:
#
#   1. If local user.name is already set for this repo, exit 0 silently.
#   2. Read the remote URL. Parse the SSH alias from it.
#   3. Look the alias up in ~/.gitidentities.
#   4. Set git config --local user.name, user.email, and signingkey.
#   5. Print "Identity set: ..." once. Never prompts again for that repo.
#   6. If no alias found (HTTPS clone, brand new local repo): show a numbered
#      list and prompt once. Same result - identity set locally, never asks again.
#
# PUSH CONFIRMATION  (global pre-push hook)
# ------------------------------------------
# ~/.git-hooks/pre-push always prints before any push:
#
#   Pushing to origin as: Musa The Dev <musa@email.com>
#
# So you always know which identity is pushing without having to think about it.
#
# CLONE WRAPPER  (gclone shell function)
# ---------------------------------------
# gclone <url> [extra git clone args]
#   - Lists all identities from ~/.gitidentities with a numbered menu
#   - You pick one
#   - Rewrites the GitHub URL to use the matching SSH alias
#   - Clones and prints: Cloning as: Musa The Dev (github-personal)
#
# Works with both git@github.com: and https://github.com/ URLs.
# For non-GitHub hosts, clones as-is and identity is set on first commit.
#
# MANUAL FALLBACK  (gitprofile shell function)
# ---------------------------------------------
# For repos cloned before this system existed, or when you need to override:
#
#   gitprofile personal     activate that identity for the current shell
#   gitprofile              list available profiles and their status
#
# GLOBAL DEFAULT IDENTITY
# ------------------------
# You choose which profile is the global git default at the end of setup.
# Any repo that bypasses the hook system still commits under a known
# identity, never a blank name.
#
# SIGNED COMMITS
# --------------
# Each profile's SSH public key is registered as both an authentication key
# and a signing key on GitHub. Every commit and tag shows Verified on GitHub.
# The per-profile gitconfig files handle this per-identity:
#
#   ~/.gitconfig-personal  →  user.name, user.email, signingkey
#   ~/.gitconfig-work      →  user.name, user.email, signingkey
#
# The global ~/.gitconfig holds the default identity and all shared settings.
#
# EXISTING PROFILES
# -----------------
# If you run this script on a machine that already has ~/.gitconfig-* files
# from a previous run, it detects them, shows them, and lets you rename or
# keep each alias before adding new ones. No data is lost.
#
# PHASES
# ------
#   1.  Git check and install/upgrade
#   2.  Identity discovery + account setup (detects existing profiles)
#   3.  Hook system + gclone + gitprofile shell helpers
#   4.  Git globals (pull, push, aliases, rerere, diff, signing, etc.)
#   5.  Global config files (vscode, prettier, solhint, lintstaged, gitignore)
#   6.  Summary
#
# REQUIREMENTS
# ------------
#   - bash 4+  (macOS default is 3.x — install bash via brew first)
#   - git
#   - ssh / ssh-keygen
#   - curl (internet check)
# ============================================================

set -euo pipefail

# === Colors

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
THEME_GREEN='\033[38;2;1;102;48m'

# === Helpers

print_banner() {
  echo -e "${THEME_GREEN}"
  echo "  ╔══════════════════════════════════════════════════════════╗"
  echo "  ║                                                          ║"
  echo "  ║    Multi-Account Git Setup  ·  by Olorunshogo           ║"
  echo "  ║    SSH Keys · Identities · Hooks · Clone Wrapper        ║"
  echo "  ║                                                          ║"
  echo "  ╚══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

phase_start() {
  local step="$1"
  local total="$2"
  local emoji="$3"
  local title="$4"
  local desc="$5"
  echo ""
  echo -e "${THEME_GREEN}  ──────────────────────────────────────────────────────────${NC}"
  echo -e "  ${BOLD}${YELLOW}Phase ${step}/${total}${NC}  ${emoji}  ${BOLD}${title}${NC}"
  echo -e "  ${DIM}${desc}${NC}"
  echo -e "${THEME_GREEN}  ──────────────────────────────────────────────────────────${NC}"
  echo ""
}

phase_done() {
  local emoji="$1"
  local message="$2"
  echo ""
  echo -e "  ${THEME_GREEN}${BOLD}${emoji}  ${message}${NC}"
  echo ""
}

phase_prompt() {
  local skip_label="$1"
  echo ""
  echo -e "  ${YELLOW}[1]${NC}  Run this phase"
  echo -e "  ${YELLOW}[2]${NC}  Skip  ${DIM}(${skip_label})${NC}"
  echo ""
  local choice=""
  while true; do
    read -r -p "$(echo -e "  ${DIM}Choose [1/2] — press Enter to run:${NC} ")" choice
    case "${choice:-1}" in
      1) return 0 ;;
      2)
        echo ""
        echo -e "  ${DIM}↷  Skipped.${NC}"
        echo ""
        return 1 ;;
      *) echo -e "  ${DIM}Enter 1 to run or 2 to skip.${NC}" ;;
    esac
  done
}

pause_next() {
  local label="${1:-next phase}"
  read -r -p "$(echo -e "  ${DIM}Press Enter to continue to ${label}...${NC} ")" _
  echo ""
}

pause_start() {
  read -r -p "$(echo -e "  ${DIM}Press Enter to start...${NC} ")" _
  echo ""
}

collect_var() {
  local prompt="$1"
  local varname="$2"
  local value=""
  while [ -z "$value" ]; do
    read -r -p "$(echo -e "  ${YELLOW}${prompt}${NC} ")" value
    if [ -z "$value" ]; then
      echo -e "  ${DIM}This field is required.${NC}"
    fi
  done
  eval "${varname}=\"\${value}\""
}

step_info() {
  echo -e "  ${DIM}→ $*${NC}"
}

# sed -i is not portable between GNU and BSD (macOS).
sed_inplace() {
  if [ "$OS" = "mac" ]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# === Pre-flight

clear
print_banner

echo -e "  ${DIM}Running pre-flight checks...${NC}"
echo ""

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  OS="mac"
else
  echo -e "  ${YELLOW}⚠  Unsupported OS: ${OSTYPE}. Exiting.${NC}"
  exit 1
fi
echo -e "  ${THEME_GREEN}✓${NC}  OS detected: ${BOLD}${OS}${NC}"

if [ "$(id -u)" -eq 0 ]; then
  echo -e "  ${YELLOW}⚠  Running as root is not recommended. Continue anyway? (y/N) ${NC}"
  read -r _confirm
  [[ "$_confirm" =~ ^[Yy]$ ]] || exit 1
fi
echo -e "  ${THEME_GREEN}✓${NC}  User: ${BOLD}$(whoami)${NC}"

if ! curl -s --head --connect-timeout 5 https://google.com > /dev/null 2>&1; then
  echo -e "  ${YELLOW}⚠  No internet connection detected. Some steps may fail.${NC}"
else
  echo -e "  ${THEME_GREEN}✓${NC}  Internet: reachable"
fi

IDENTITIES_FILE="$HOME/.gitidentities"
GLOBAL_ALIAS=""

echo ""
echo -e "  ${BOLD}6 phases will run. Choose to run or skip each one.${NC}"
echo ""
pause_next "Phase 1"


# === Phase 1: Git

phase_start 1 6 "🔧" "Git" \
  "Checks whether Git is installed and up to date. Installs it if missing."

if phase_prompt "skip Git check"; then
  if [ "$OS" = "mac" ] && ! command -v brew &> /dev/null; then
    step_info "Homebrew not found — installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo -e "  ${THEME_GREEN}✓${NC}  Homebrew installed."
  fi

  if command -v git &> /dev/null; then
    step_info "Git found: $(git --version) — checking for updates..."
    if [ "$OS" = "linux" ]; then
      sudo apt-get install -y --only-upgrade git -qq 2>/dev/null || true
    elif [ "$OS" = "mac" ]; then
      brew upgrade git 2>/dev/null || true
    fi
    echo -e "  ${THEME_GREEN}✓${NC}  Git is up to date: $(git --version)"
  else
    step_info "Git not found — installing..."
    if [ "$OS" = "linux" ]; then
      sudo apt-get update -qq 2>/dev/null || true
      sudo apt-get install -y git -qq
    elif [ "$OS" = "mac" ]; then
      brew install git
    fi
    echo -e "  ${THEME_GREEN}✓${NC}  Git installed: $(git --version)"
  fi
  phase_done "✅" "Git is ready."
fi
pause_next "Phase 2 (Identity Setup)"


# === Phase 2: Identity Discovery + Account Setup

phase_start 2 6 "🔑" "Identity Discovery + Account Setup" \
  "Detects existing profiles, lets you rename them, and adds new accounts. Generates SSH keys, writes SSH config, and builds ~/.gitidentities."

if phase_prompt "skip identity setup"; then

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
SSH_CONFIG="$HOME/.ssh/config"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"
touch "$IDENTITIES_FILE"

# --- Detect existing profiles from previous runs
EXISTING_ALIASES=()
for f in "$HOME"/.gitconfig-*; do
  [ -f "$f" ] || continue
  alias_name="${f##*/.gitconfig-}"
  EXISTING_ALIASES+=("$alias_name")
done

TOTAL_EXISTING="${#EXISTING_ALIASES[@]}"

if [ "$TOTAL_EXISTING" -gt 0 ]; then
  echo ""
  echo -e "  ${BOLD}Found ${TOTAL_EXISTING} existing profile(s):${NC}"
  echo ""
  for ea in "${EXISTING_ALIASES[@]}"; do
    ex_name=$(git config -f "$HOME/.gitconfig-${ea}" user.name 2>/dev/null || echo "unknown")
    ex_email=$(git config -f "$HOME/.gitconfig-${ea}" user.email 2>/dev/null || echo "unknown")
    echo -e "    ${THEME_GREEN}→${NC}  alias=${BOLD}${ea}${NC}  name=${BOLD}${ex_name}${NC}  email=${BOLD}${ex_email}${NC}"
  done
  echo ""

  # Let user rename each existing profile
  NEW_ALIASES=()
  for ea in "${EXISTING_ALIASES[@]}"; do
    read -r -p "$(echo -e "  ${YELLOW}Alias '${ea}' — keep it or rename? (Enter to keep, or type new alias):${NC} ")" new_alias_input
    new_alias_input="${new_alias_input:-$ea}"

    if [ "$new_alias_input" != "$ea" ]; then
      step_info "Renaming '${ea}' to '${new_alias_input}'..."

      # Rename gitconfig file
      if [ -f "$HOME/.gitconfig-${ea}" ]; then
        mv "$HOME/.gitconfig-${ea}" "$HOME/.gitconfig-${new_alias_input}"
      fi

      # Rename SSH key files
      if [ -f "$HOME/.ssh/id_ed25519_${ea}" ]; then
        mv "$HOME/.ssh/id_ed25519_${ea}" "$HOME/.ssh/id_ed25519_${new_alias_input}"
        mv "$HOME/.ssh/id_ed25519_${ea}.pub" "$HOME/.ssh/id_ed25519_${new_alias_input}.pub"
      fi

      # Update SSH config block
      if grep -q "Host github-${ea}" "$SSH_CONFIG" 2>/dev/null; then
        sed_inplace "s/Host github-${ea}/Host github-${new_alias_input}/" "$SSH_CONFIG"
        sed_inplace "s/id_ed25519_${ea}/id_ed25519_${new_alias_input}/g" "$SSH_CONFIG"
      fi

      # Update identities file
      if grep -q "^github-${ea}|" "$IDENTITIES_FILE" 2>/dev/null; then
        sed_inplace "s/^github-${ea}|/github-${new_alias_input}|/" "$IDENTITIES_FILE"
      fi

      echo -e "  ${THEME_GREEN}✓${NC}  Renamed '${ea}' to '${new_alias_input}'"
      ea="$new_alias_input"
    fi

    NEW_ALIASES+=("$ea")

    # Ensure this profile is in the identities file
    ex_name=$(git config -f "$HOME/.gitconfig-${ea}" user.name 2>/dev/null || true)
    ex_email=$(git config -f "$HOME/.gitconfig-${ea}" user.email 2>/dev/null || true)
    if [ -n "$ex_name" ] && [ -n "$ex_email" ]; then
      if ! grep -q "^github-${ea}|" "$IDENTITIES_FILE" 2>/dev/null; then
        echo "github-${ea}|${ex_name}|${ex_email}" >> "$IDENTITIES_FILE"
        echo -e "  ${THEME_GREEN}✓${NC}  Added existing profile 'github-${ea}' to identity map."
      fi
    fi
  done

  EXISTING_ALIASES=("${NEW_ALIASES[@]}")
fi

# --- Check for orphan global identity (no profiles yet, but gitconfig has identity)
GLOBAL_EXISTING_NAME=$(git config --global user.name 2>/dev/null || true)
GLOBAL_EXISTING_EMAIL=$(git config --global user.email 2>/dev/null || true)

if [ -n "$GLOBAL_EXISTING_NAME" ] && [ "$TOTAL_EXISTING" -eq 0 ]; then
  echo ""
  echo -e "  ${BOLD}Found a global git identity with no profiles:${NC}"
  echo -e "    ${THEME_GREEN}→${NC}  ${GLOBAL_EXISTING_NAME} · ${GLOBAL_EXISTING_EMAIL}"
  echo ""
  collect_var "Give this identity an alias so it becomes a named profile (e.g. personal, work):" "ORPHAN_ALIAS"

  # Write a gitconfig for it
  ORPHAN_KEY="$HOME/.ssh/id_ed25519_${ORPHAN_ALIAS}"
  cat > "$HOME/.gitconfig-${ORPHAN_ALIAS}" << EOF
[user]
  name = ${GLOBAL_EXISTING_NAME}
  email = ${GLOBAL_EXISTING_EMAIL}
EOF

  if [ -f "${ORPHAN_KEY}.pub" ]; then
    cat >> "$HOME/.gitconfig-${ORPHAN_ALIAS}" << EOF
[gpg]
  format = ssh
[user]
  signingkey = ${ORPHAN_KEY}.pub
[commit]
  gpgsign = true
[tag]
  gpgsign = true
EOF
  fi

  # Add SSH config block if not present
  if ! grep -q "Host github-${ORPHAN_ALIAS}" "$SSH_CONFIG" 2>/dev/null; then
    cat >> "$SSH_CONFIG" << EOF

Host github-${ORPHAN_ALIAS}
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_${ORPHAN_ALIAS}
EOF
  fi

  # Add to identities file
  if ! grep -q "^github-${ORPHAN_ALIAS}|" "$IDENTITIES_FILE" 2>/dev/null; then
    echo "github-${ORPHAN_ALIAS}|${GLOBAL_EXISTING_NAME}|${GLOBAL_EXISTING_EMAIL}" >> "$IDENTITIES_FILE"
  fi

  EXISTING_ALIASES+=("$ORPHAN_ALIAS")
  TOTAL_EXISTING="${#EXISTING_ALIASES[@]}"
  echo -e "  ${THEME_GREEN}✓${NC}  Existing global identity folded in as 'github-${ORPHAN_ALIAS}'."
fi

# --- How many new accounts to add
echo ""
if [ "$TOTAL_EXISTING" -gt 0 ]; then
  echo -e "  ${BOLD}You currently have ${TOTAL_EXISTING} profile(s).${NC}"
else
  echo -e "  ${BOLD}No existing profiles found.${NC}"
fi
echo ""

NEW_COUNT=""
while true; do
  read -r -p "$(echo -e "  ${YELLOW}How many NEW accounts do you want to add? (0 to skip adding):${NC} ")" NEW_COUNT
  if [[ "$NEW_COUNT" =~ ^[0-9]+$ ]]; then
    break
  fi
  echo -e "  ${DIM}Please enter 0 or a positive number.${NC}"
done

ACCOUNT_COUNT="$NEW_COUNT"
ALL_ALIASES=("${EXISTING_ALIASES[@]+"${EXISTING_ALIASES[@]}"}")

# --- Collect and configure each new account
for (( i=1; i<=ACCOUNT_COUNT; i++ )); do
  echo ""
  echo -e "  ${BOLD}${YELLOW}── New Account ${i} of ${ACCOUNT_COUNT} ──────────────────────────────${NC}"
  echo ""
  collect_var "[Account ${i}] Alias for this account (e.g. personal, work, client):" "NEW_ALIAS_${i}"
  collect_var "[Account ${i}] Full name (appears on git commits):" "NEW_NAME_${i}"
  collect_var "[Account ${i}] GitHub username (e.g. Olorunshogo):" "NEW_UNAME_${i}"
  collect_var "[Account ${i}] Email address:" "NEW_EMAIL_${i}"
  echo ""
done

# Confirm new accounts before processing
if [ "$ACCOUNT_COUNT" -gt 0 ]; then
  echo ""
  echo -e "  ${DIM}New accounts to be added:${NC}"
  echo ""
  for (( i=1; i<=ACCOUNT_COUNT; i++ )); do
    eval "A=\$NEW_ALIAS_${i}"
    eval "N=\$NEW_NAME_${i}"
    eval "U=\$NEW_UNAME_${i}"
    eval "E=\$NEW_EMAIL_${i}"
    echo -e "    ${THEME_GREEN}[${i}]${NC}  alias=${BOLD}${A}${NC}  name=${BOLD}${N}${NC}  github=${BOLD}${U}${NC}  email=${BOLD}${E}${NC}"
  done
  echo ""
  pause_start

  for (( i=1; i<=ACCOUNT_COUNT; i++ )); do
    eval "ALIAS=\$NEW_ALIAS_${i}"
    eval "GIT_NAME=\$NEW_NAME_${i}"
    eval "GIT_USERNAME=\$NEW_UNAME_${i}"
    eval "GIT_EMAIL=\$NEW_EMAIL_${i}"

    echo ""
    echo -e "${THEME_GREEN}  ──────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Configuring: ${YELLOW}${ALIAS}${NC}  (${GIT_NAME} · ${GIT_USERNAME})"
    echo -e "${THEME_GREEN}  ──────────────────────────────────────────────────────────${NC}"
    echo ""

    # SSH key
    KEY_FILE="$HOME/.ssh/id_ed25519_${ALIAS}"
    PUB_FILE="${KEY_FILE}.pub"

    if [ -f "$PUB_FILE" ]; then
      echo -e "  ${YELLOW}⚠${NC}  Key already exists at ${KEY_FILE}"
      read -r -p "$(echo -e "  ${YELLOW}Regenerate it? This overwrites the existing key. (y/N):${NC} ")" _regen
      if [[ "${_regen,,}" == "y" ]]; then
        ssh-keygen -t ed25519 -C "${GIT_EMAIL}" -f "${KEY_FILE}" -N ""
        echo -e "  ${THEME_GREEN}✓${NC}  New key generated."
      else
        step_info "Reusing existing key at ${KEY_FILE}"
      fi
    else
      step_info "Generating ed25519 SSH key for ${ALIAS}..."
      ssh-keygen -t ed25519 -C "${GIT_EMAIL}" -f "${KEY_FILE}" -N ""
      echo -e "  ${THEME_GREEN}✓${NC}  Key generated at ${KEY_FILE}"
    fi

    # SSH config entry
    if grep -q "Host github-${ALIAS}" "$SSH_CONFIG" 2>/dev/null; then
      step_info "SSH config entry for github-${ALIAS} already exists — skipping."
    else
      cat >> "$SSH_CONFIG" << EOF

Host github-${ALIAS}
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_${ALIAS}
EOF
      echo -e "  ${THEME_GREEN}✓${NC}  SSH config block added: Host github-${ALIAS}"
    fi

    # Show public key and wait for GitHub registration
    echo ""
    echo -e "${THEME_GREEN}  ──────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Public SSH key for ${YELLOW}${ALIAS}${NC}${BOLD} (${GIT_USERNAME})${NC}"
    echo -e "${THEME_GREEN}  ──────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${CYAN}"
    cat "$PUB_FILE"
    echo -e "${NC}"
    echo -e "${THEME_GREEN}  ──────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${BOLD}Add this key to GitHub for ${YELLOW}${GIT_USERNAME}${NC}${BOLD} (as both Auth + Signing key):${NC}"
    echo ""
    echo -e "    ${YELLOW}1.${NC}  Go to  ${BOLD}https://github.com/settings/keys${NC}  (logged in as ${GIT_USERNAME})"
    echo -e "    ${YELLOW}2.${NC}  Click  ${BOLD}New SSH key${NC}"
    echo -e "    ${YELLOW}3.${NC}  Title: ${DIM}$(hostname) — ${ALIAS}${NC}    Type: ${DIM}Authentication Key${NC}"
    echo -e "    ${YELLOW}4.${NC}  Paste the key above → ${BOLD}Add SSH key${NC}"
    echo -e "    ${YELLOW}5.${NC}  Click  ${BOLD}New SSH key${NC}  again"
    echo -e "    ${YELLOW}6.${NC}  Title: ${DIM}$(hostname) — ${ALIAS} (signing)${NC}    Type: ${DIM}Signing Key${NC}"
    echo -e "    ${YELLOW}7.${NC}  Paste the same key → ${BOLD}Add SSH key${NC}"
    echo ""
    echo -e "  ${DIM}When both keys are added, type ${BOLD}done${NC}${DIM} below and press Enter.${NC}"
    echo ""

    DONE_INPUT=""
    while [[ "${DONE_INPUT,,}" != "done" ]]; do
      read -r -p "$(echo -e "  ${YELLOW}Type 'done' when both keys are added for ${ALIAS}:${NC} ")" DONE_INPUT
      [[ "${DONE_INPUT,,}" != "done" ]] && echo -e "  ${DIM}Type the word done and press Enter.${NC}"
    done
    echo ""

    # Start ssh-agent and add key
    step_info "Adding key to ssh-agent..."
    eval "$(ssh-agent -s)" > /dev/null
    ssh-add "$KEY_FILE"

    # Test connection
    echo ""
    step_info "Testing SSH connection for github-${ALIAS}..."
    SSH_RESULT=$(ssh -T "git@github-${ALIAS}" 2>&1 || true)
    echo -e "  ${DIM}${SSH_RESULT}${NC}"

    if echo "$SSH_RESULT" | grep -q "successfully authenticated"; then
      echo -e "  ${THEME_GREEN}✓${NC}  GitHub SSH verified for ${ALIAS} (${GIT_USERNAME})"
    else
      echo -e "  ${YELLOW}⚠${NC}  Could not verify. Test manually: ssh -T git@github-${ALIAS}"
    fi

    # Per-profile gitconfig
    PROFILE_CONFIG="$HOME/.gitconfig-${ALIAS}"
    cat > "$PROFILE_CONFIG" << EOF
[user]
  name = ${GIT_NAME}
  email = ${GIT_EMAIL}
  signingkey = ${PUB_FILE}
[gpg]
  format = ssh
[commit]
  gpgsign = true
[tag]
  gpgsign = true
EOF
    echo -e "  ${THEME_GREEN}✓${NC}  Per-profile gitconfig written: ${PROFILE_CONFIG}"

    # Add to identities map
    if ! grep -q "^github-${ALIAS}|" "$IDENTITIES_FILE" 2>/dev/null; then
      echo "github-${ALIAS}|${GIT_NAME}|${GIT_EMAIL}" >> "$IDENTITIES_FILE"
      echo -e "  ${THEME_GREEN}✓${NC}  Identity map updated."
    fi

    ALL_ALIASES+=("$ALIAS")
  done
fi

# --- Pick the global default identity
ALL_FINAL=()
while IFS= read -r line; do
  [ -n "$line" ] || continue
  ALL_FINAL+=("$line")
done < "$IDENTITIES_FILE"

if [ "${#ALL_FINAL[@]}" -gt 0 ]; then
  echo ""
  echo -e "${THEME_GREEN}  ──────────────────────────────────────────────────────────${NC}"
  echo -e "  ${BOLD}Which profile should be the global git default?${NC}"
  echo -e "  ${DIM}(Used for any repo that has no per-repo identity set yet)${NC}"
  echo -e "${THEME_GREEN}  ──────────────────────────────────────────────────────────${NC}"
  echo ""

  for idx in "${!ALL_FINAL[@]}"; do
    G_ALIAS=$(echo "${ALL_FINAL[$idx]}" | cut -d'|' -f1)
    G_NAME=$(echo "${ALL_FINAL[$idx]}" | cut -d'|' -f2)
    G_EMAIL=$(echo "${ALL_FINAL[$idx]}" | cut -d'|' -f3)
    echo -e "  ${YELLOW}[$((idx+1))]${NC}  ${BOLD}${G_NAME}${NC} · ${G_EMAIL}  ${DIM}(${G_ALIAS})${NC}"
  done
  echo ""

  GLOBAL_CHOICE=""
  while true; do
    read -r -p "$(echo -e "  ${YELLOW}Choose [1-${#ALL_FINAL[@]}]:${NC} ")" GLOBAL_CHOICE
    if [[ "$GLOBAL_CHOICE" =~ ^[0-9]+$ ]] && \
       [ "$GLOBAL_CHOICE" -ge 1 ] && \
       [ "$GLOBAL_CHOICE" -le "${#ALL_FINAL[@]}" ]; then
      break
    fi
    echo -e "  ${DIM}Enter a number between 1 and ${#ALL_FINAL[@]}.${NC}"
  done

  GLOBAL_LINE="${ALL_FINAL[$((GLOBAL_CHOICE-1))]}"
  GLOBAL_ALIAS=$(echo "$GLOBAL_LINE" | cut -d'|' -f1)
  GLOBAL_NAME=$(echo "$GLOBAL_LINE" | cut -d'|' -f2)
  GLOBAL_EMAIL=$(echo "$GLOBAL_LINE" | cut -d'|' -f3)
  GLOBAL_ALIAS_LABEL=$(echo "$GLOBAL_ALIAS" | sed 's/github-//')
  GLOBAL_KEY="$HOME/.ssh/id_ed25519_${GLOBAL_ALIAS_LABEL}.pub"

  git config --global user.name "$GLOBAL_NAME"
  git config --global user.email "$GLOBAL_EMAIL"
  git config --global gpg.format ssh
  if [ -f "$GLOBAL_KEY" ]; then
    git config --global user.signingkey "$GLOBAL_KEY"
  fi
  git config --global commit.gpgsign true
  git config --global tag.gpgsign true

  echo ""
  echo -e "  ${THEME_GREEN}✓${NC}  Global identity set: ${BOLD}${GLOBAL_NAME}${NC} · ${GLOBAL_EMAIL}  ${DIM}(${GLOBAL_ALIAS})${NC}"
fi

phase_done "✅" "All accounts configured. SSH keys active. Identity map written."
fi
pause_next "Phase 3 (Hook System)"


# === Phase 3: Hook System + Shell Helpers

phase_start 3 6 "🪝" "Hook System + Shell Helpers" \
  "Installs global pre-commit and pre-push hooks. Adds gclone and gitprofile shell functions."

if phase_prompt "skip hook system"; then

mkdir -p "$HOME/.git-hooks"

# --- pre-commit hook
cat > "$HOME/.git-hooks/pre-commit" << 'HOOKEOF'
#!/usr/bin/env bash
# Global pre-commit hook — sets per-repo git identity on first commit.
# Managed by git-multiple-accounts.sh. Edit ~/.gitidentities to add/remove profiles.

IDENTITIES_FILE="$HOME/.gitidentities"
THEME_GREEN='\033[38;2;1;102;48m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Skip if local identity already set for this repo
LOCAL_NAME=$(git config --local user.name 2>/dev/null || true)
[ -n "$LOCAL_NAME" ] && exit 0

# Try to auto-detect from remote alias
REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
DETECTED_ALIAS=""

if [ -n "$REMOTE_URL" ]; then
  # Matches format: github-personal:user/repo.git
  DETECTED_ALIAS=$(echo "$REMOTE_URL" | sed -n 's/^\(github-[^:]*\):.*/\1/p')
fi

set_identity() {
  local alias_label name email
  alias_label=$(echo "$1" | sed 's/github-//')
  name="$2"
  email="$3"
  local key_pub="$HOME/.ssh/id_ed25519_${alias_label}.pub"

  git config --local user.name "$name"
  git config --local user.email "$email"
  if [ -f "$key_pub" ]; then
    git config --local gpg.format ssh
    git config --local user.signingkey "$key_pub"
    git config --local commit.gpgsign true
    git config --local tag.gpgsign true
  fi
  printf '\n  \033[38;2;1;102;48m✓\033[0m  Identity set: %s <%s> \033[2m(%s)\033[0m\n\n' "$name" "$email" "$1"
}

# Auto-set from detected alias
if [ -n "$DETECTED_ALIAS" ] && [ -f "$IDENTITIES_FILE" ]; then
  IDENTITY=$(grep "^${DETECTED_ALIAS}|" "$IDENTITIES_FILE" 2>/dev/null | head -1 || true)
  if [ -n "$IDENTITY" ]; then
    D_NAME=$(echo "$IDENTITY" | cut -d'|' -f2)
    D_EMAIL=$(echo "$IDENTITY" | cut -d'|' -f3)
    set_identity "$DETECTED_ALIAS" "$D_NAME" "$D_EMAIL"
    [ -x ".git/hooks/pre-commit" ] && .git/hooks/pre-commit
    exit 0
  fi
fi

# Fallback: prompt user to pick
[ ! -f "$IDENTITIES_FILE" ] && exit 0

LINES=()
while IFS= read -r line; do
  [ -n "$line" ] || continue
  LINES+=("$line")
done < "$IDENTITIES_FILE"

[ "${#LINES[@]}" -eq 0 ] && exit 0

printf '\n  No identity detected for this repo. Who is committing?\n\n'
for idx in "${!LINES[@]}"; do
  F_NAME=$(echo "${LINES[$idx]}" | cut -d'|' -f2)
  F_EMAIL=$(echo "${LINES[$idx]}" | cut -d'|' -f3)
  F_ALIAS=$(echo "${LINES[$idx]}" | cut -d'|' -f1)
  printf '  [%d]  %s <%s>  \033[2m(%s)\033[0m\n' "$((idx+1))" "$F_NAME" "$F_EMAIL" "$F_ALIAS"
done
printf '\n'

CHOICE=""
while true; do
  read -r -p "  Choose [1-${#LINES[@]}]: " CHOICE
  if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#LINES[@]}" ]; then
    break
  fi
  printf '  Please enter a number between 1 and %d.\n' "${#LINES[@]}"
done

SELECTED="${LINES[$((CHOICE-1))]}"
SEL_ALIAS=$(echo "$SELECTED" | cut -d'|' -f1)
SEL_NAME=$(echo "$SELECTED" | cut -d'|' -f2)
SEL_EMAIL=$(echo "$SELECTED" | cut -d'|' -f3)

set_identity "$SEL_ALIAS" "$SEL_NAME" "$SEL_EMAIL"
[ -x ".git/hooks/pre-commit" ] && .git/hooks/pre-commit
HOOKEOF
chmod +x "$HOME/.git-hooks/pre-commit"
echo -e "  ${THEME_GREEN}✓${NC}  ~/.git-hooks/pre-commit written and marked executable."

# --- pre-push hook
cat > "$HOME/.git-hooks/pre-push" << 'HOOKEOF'
#!/usr/bin/env bash
# Global pre-push hook — shows which identity is pushing.
# Managed by git-multiple-accounts.sh.

REMOTE="$1"
P_NAME=$(git config user.name 2>/dev/null || echo "unknown")
P_EMAIL=$(git config user.email 2>/dev/null || echo "unknown")
printf '\n  \033[38;2;1;102;48m→\033[0m  Pushing to \033[1m%s\033[0m as: %s <%s>\n\n' "$REMOTE" "$P_NAME" "$P_EMAIL"
HOOKEOF
chmod +x "$HOME/.git-hooks/pre-push"
echo -e "  ${THEME_GREEN}✓${NC}  ~/.git-hooks/pre-push written and marked executable."

# Register global hooks path
git config --global core.hooksPath "$HOME/.git-hooks"
echo -e "  ${THEME_GREEN}✓${NC}  core.hooksPath set to ~/.git-hooks"

# --- Shell helpers: gclone and gitprofile
SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then
  SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
  SHELL_RC="$HOME/.bashrc"
fi

if [ -n "$SHELL_RC" ]; then

  if ! grep -q "gclone()" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << 'SHELLEOF'

# gclone — clone a GitHub repo as a specific identity
# Usage: gclone <github-url> [extra git clone args]
gclone() {
  local url="${1:-}"
  if [ -z "$url" ]; then
    echo "Usage: gclone <github-url> [extra args]"
    return 1
  fi

  local IDENTITIES_FILE="$HOME/.gitidentities"
  if [ ! -f "$IDENTITIES_FILE" ]; then
    echo "No identities found. Run git-multiple-accounts.sh first."
    return 1
  fi

  local LINES=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    LINES+=("$line")
  done < "$IDENTITIES_FILE"

  if [ "${#LINES[@]}" -eq 0 ]; then
    echo "No identities configured in $IDENTITIES_FILE."
    return 1
  fi

  echo ""
  echo "  Clone as which identity?"
  echo ""
  local idx
  for idx in "${!LINES[@]}"; do
    local G_ALIAS G_NAME G_EMAIL
    G_ALIAS=$(echo "${LINES[$idx]}" | cut -d'|' -f1)
    G_NAME=$(echo "${LINES[$idx]}" | cut -d'|' -f2)
    G_EMAIL=$(echo "${LINES[$idx]}" | cut -d'|' -f3)
    printf '  [%d]  %s <%s>  \033[2m(%s)\033[0m\n' "$((idx+1))" "$G_NAME" "$G_EMAIL" "$G_ALIAS"
  done
  echo ""

  local CHOICE=""
  while true; do
    read -r -p "  Choose [1-${#LINES[@]}]: " CHOICE
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#LINES[@]}" ]; then
      break
    fi
    printf '  Please enter a number between 1 and %d.\n' "${#LINES[@]}"
  done

  local SELECTED="${LINES[$((CHOICE-1))]}"
  local SEL_ALIAS SEL_NAME REPO_PATH REWRITTEN
  SEL_ALIAS=$(echo "$SELECTED" | cut -d'|' -f1)
  SEL_NAME=$(echo "$SELECTED" | cut -d'|' -f2)

  # Rewrite GitHub URL to use the SSH alias
  if echo "$url" | grep -qE "git@github\.com:|https://github\.com/"; then
    REPO_PATH=$(echo "$url" | sed 's|git@github\.com:||;s|https://github\.com/||')
    [[ "$REPO_PATH" != *.git ]] && REPO_PATH="${REPO_PATH}.git"
    REWRITTEN="${SEL_ALIAS}:${REPO_PATH}"
  else
    echo "  Non-GitHub URL — cloning as-is. Identity will be set on first commit."
    REWRITTEN="$url"
  fi

  echo ""
  printf '  \033[38;2;1;102;48m✓\033[0m  Cloning as: \033[1m%s\033[0m \033[2m(%s)\033[0m\n' "$SEL_NAME" "$SEL_ALIAS"
  echo "  URL: $REWRITTEN"
  echo ""

  git clone "$REWRITTEN" "${@:2}"
}
SHELLEOF
    echo -e "  ${THEME_GREEN}✓${NC}  gclone() added to ${SHELL_RC}"
  else
    step_info "gclone() already present in ${SHELL_RC} — skipping."
  fi

  if ! grep -q "gitprofile()" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << 'SHELLEOF'

# gitprofile — manually switch git identity for the current shell session
# Usage: gitprofile <alias>   or   gitprofile (lists all)
gitprofile() {
  local alias="${1:-}"
  local IDENTITIES_FILE="$HOME/.gitidentities"

  if [ -z "$alias" ]; then
    echo ""
    echo "  Available git profiles:"
    echo ""
    local CURRENT_NAME CURRENT_EMAIL
    CURRENT_NAME=$(git config --global user.name 2>/dev/null || echo "")
    CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      local G_ALIAS G_NAME G_EMAIL MARKER
      G_ALIAS=$(echo "$line" | cut -d'|' -f1)
      G_NAME=$(echo "$line" | cut -d'|' -f2)
      G_EMAIL=$(echo "$line" | cut -d'|' -f3)
      MARKER=""
      [ "$G_NAME" = "$CURRENT_NAME" ] && [ "$G_EMAIL" = "$CURRENT_EMAIL" ] && MARKER=" (active)"
      printf '  %-20s  %s <%s>%s\n' "$G_ALIAS" "$G_NAME" "$G_EMAIL" "$MARKER"
    done < "$IDENTITIES_FILE"
    echo ""
    return 0
  fi

  local config="$HOME/.gitconfig-$(echo "$alias" | sed 's/github-//')"
  if [ ! -f "$config" ]; then
    local alias_label
    alias_label=$(echo "$alias" | sed 's/github-//')
    config="$HOME/.gitconfig-${alias_label}"
  fi

  if [ ! -f "$config" ]; then
    echo "Unknown profile: $alias"
    echo "Run 'gitprofile' to list available profiles."
    return 1
  fi

  export GIT_AUTHOR_NAME=$(git config -f "$config" user.name)
  export GIT_AUTHOR_EMAIL=$(git config -f "$config" user.email)
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
  export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
  printf '\n  \033[38;2;1;102;48m✓\033[0m  Git profile active: %s <%s>\n\n' "$GIT_AUTHOR_NAME" "$GIT_AUTHOR_EMAIL"
}
SHELLEOF
    echo -e "  ${THEME_GREEN}✓${NC}  gitprofile() added to ${SHELL_RC}"
  else
    step_info "gitprofile() already present in ${SHELL_RC} — skipping."
  fi

else
  echo -e "  ${YELLOW}⚠${NC}  Could not find ~/.zshrc or ~/.bashrc. Add gclone/gitprofile manually."
fi

phase_done "✅" "Hook system installed. gclone and gitprofile shell helpers added."
fi
pause_next "Phase 4 (Git Globals)"


# === Phase 4: Git Globals

phase_start 4 6 "⚙️" "Git Globals" \
  "Applies the full CoreDev git config: pull, push, rebase, aliases, rerere, diff, colors, and more."

if phase_prompt "skip git globals"; then

step_info "Applying git globals..."

# Core
git config --global init.defaultBranch main
git config --global core.editor "code --wait"
git config --global core.autocrlf false
git config --global core.safecrlf warn

# Pull / push / fetch
git config --global pull.rebase true
git config --global rebase.autoStash true
git config --global push.default current
git config --global push.autoSetupRemote true
git config --global fetch.prune true

# Merge and diff
git config --global merge.conflictstyle diff3
git config --global diff.colorMoved zebra
git config --global rerere.enabled true

# Colors and UX
git config --global color.ui auto
git config --global help.autocorrect 10
git config --global log.date iso

# Aliases
git config --global alias.lg \
  "log --oneline --graph --all --decorate"
git config --global alias.ll \
  "log --pretty=format:'%C(yellow)%h%Creset %s %C(dim)(%ar)%Creset' --decorate"
git config --global alias.st  "status --short --branch"
git config --global alias.co  "checkout"
git config --global alias.br  "branch --sort=-committerdate"
git config --global alias.undo "reset HEAD~1 --mixed"
git config --global alias.unstage "reset HEAD --"
git config --global alias.wip  "!git add -A && git commit -m 'wip'"
git config --global alias.unwip "reset HEAD~1 --mixed"
git config --global alias.aliases "config --get-regexp ^alias\\."
git config --global alias.whoami "!git config user.name && git config user.email"

echo -e "  ${THEME_GREEN}✓${NC}  Git globals, aliases, and signing config applied."

phase_done "✅" "Git globals ready."
fi
pause_next "Phase 5 (Global Config Files)"


# === Phase 5: Global Config Files

phase_start 5 6 "📁" "Global Config Files" \
  "Writes ~/.vscode/settings.json · ~/.vscode/extensions.json · ~/.prettierrc · ~/.solhint.json · ~/.lintstagedrc.json · ~/.gitignore_global"

if phase_prompt "skip global config files"; then

mkdir -p ~/.vscode

# --- VS Code settings
step_info "Writing ~/.vscode/settings.json..."
cat << 'EOF' > ~/.vscode/settings.json
{
  // === Editor core
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.formatOnSave": true,
  "editor.formatOnPaste": false,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": "explicit",
    "source.organizeImports": "never"
  },
  "editor.tabSize": 2,
  "editor.insertSpaces": true,
  "editor.detectIndentation": false,
  "editor.rulers": [100],
  "editor.wordWrap": "off",
  "editor.linkedEditing": true,
  "editor.bracketPairColorization.enabled": true,
  "editor.guides.bracketPairs": "active",
  "editor.inlayHints.enabled": "on",
  "editor.suggest.preview": true,
  "editor.acceptSuggestionOnEnter": "smart",
  "editor.quickSuggestionsDelay": 100,
  "editor.stickyScroll.enabled": true,

  // === Files
  "files.eol": "\n",
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "files.trimFinalNewlines": true,
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 300,
  "files.exclude": {
    "**/.git": true,
    "**/.DS_Store": true,
    "**/node_modules": true,
    "**/target": true,
    "**/artifacts": true,
    "**/out": true,
    "**/.next": true,
    "**/.nuxt": true,
    "**/.output": true
  },
  "files.watcherExclude": {
    "**/.git/objects/**": true,
    "**/.next/**": true,
    "**/node_modules/**": true,
    "**/target/**": true
  },

  // === Search
  "search.exclude": {
    "**/node_modules": true,
    "**/package-lock.json": true,
    "**/.next": true,
    "**/target": true
  },

  // === TypeScript
  "typescript.tsdk": "node_modules/typescript/lib",
  "typescript.enablePromptUseWorkspaceTsdk": true,
  "typescript.preferences.importModuleSpecifier": "non-relative",
  "typescript.preferences.quoteStyle": "single",
  "typescript.updateImportsOnFileMove.enabled": "always",
  "typescript.inlayHints.parameterNames.enabled": "literals",
  "typescript.inlayHints.variableTypes.enabled": false,
  "typescript.inlayHints.functionLikeReturnTypes.enabled": false,

  // === ESLint
  "eslint.enable": true,
  "eslint.validate": ["javascript", "javascriptreact", "typescript", "typescriptreact"],
  "eslint.workingDirectories": [{ "mode": "auto" }],
  "eslint.run": "onSave",

  // === Prettier
  "prettier.requireConfig": true,
  "prettier.configPath": ".prettierrc",
  "prettier.useEditorConfig": false,
  "prettier.printWidth": 100,
  "prettier.tabWidth": 2,
  "prettier.singleQuote": true,
  "prettier.trailingComma": "all",
  "prettier.semi": true,
  "prettier.arrowParens": "always",
  "prettier.bracketSpacing": true,
  "[javascript]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[javascriptreact]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[typescript]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[typescriptreact]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[json]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[jsonc]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[css]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[markdown]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.wordWrap": "on"
  },
  "[solidity]": {
    "editor.defaultFormatter": "NomicFoundation.hardhat-solidity"
  },
  "[rust]": {
    "editor.defaultFormatter": "rust-lang.rust-analyzer",
    "editor.formatOnSave": true
  },

  // === Tailwind CSS
  "tailwindCSS.experimental.classRegex": [
    ["cn\\(([^)]*)\\)", "(?:'|\"|`)([^']*)(?:'|\"|`)"],
    ["cva\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]"],
    ["cx\\(([^)]*)\\)", "(?:'|\"|`)([^']*)(?:'|\"|`)"]
  ],
  "tailwindCSS.includeLanguages": {
    "typescript": "javascript",
    "typescriptreact": "javascript"
  },
  "tailwindCSS.validate": true,

  // === Solidity
  "solidity.compileUsingRemoteVersion": "v0.8.24",
  "solidity.formatter": "prettier",
  "solidity.linter": "solhint",

  // === Rust
  "rust-analyzer.check.command": "clippy",
  "rust-analyzer.checkOnSave": true,
  "rust-analyzer.procMacro.enable": true,
  "rust-analyzer.cargo.features": "all",

  // === Terminal
  "terminal.integrated.defaultProfile.linux": "bash",

  // === Git
  "git.autofetch": true,
  "git.confirmSync": false,
  "git.enableSmartCommit": true,

  // === Misc
  "emmet.includeLanguages": {
    "typescriptreact": "html"
  },
  "npm.packageManager": "pnpm",
  "explorer.fileNesting.enabled": true,
  "explorer.fileNesting.patterns": {
    "*.ts": "${capture}.js, ${capture}.d.ts",
    "*.tsx": "${capture}.module.css",
    "package.json": "package-lock.json, .npmrc, .nvmrc, .node-version, pnpm-lock.yaml",
    "next.config.*": "next-env.d.ts",
    "nuxt.config.*": ".nuxtrc",
    "tailwind.config.*": "postcss.config.*",
    ".eslintrc.*": ".eslintignore, .prettierrc, .prettierignore, .editorconfig, .lintstagedrc*"
  },

  "cSpell.words": []
}
EOF
echo -e "  ${THEME_GREEN}✓${NC}  ~/.vscode/settings.json written"

# --- VS Code extensions
step_info "Writing ~/.vscode/extensions.json..."
cat << 'EOF' > ~/.vscode/extensions.json
{
  "recommendations": [
    // === Core formatting and linting
    "esbenp.prettier-vscode",
    "dbaeumer.vscode-eslint",

    // === TypeScript and React
    "ms-vscode.vscode-typescript-next",
    "dsznajder.es7-react-js-snippets",
    "christian-kohler.path-intellisense",

    // === Vue / Nuxt
    "Vue.volar",
    "antfu.unocss",

    // === Tailwind CSS
    "bradlc.vscode-tailwindcss",

    // === Next.js
    "nextjs.vscode-nextjs",

    // === Solidity / Web3
    "NomicFoundation.hardhat-solidity",
    "tintinweb.solidity-visual-auditor",

    // === Rust
    "rust-lang.rust-analyzer",
    "tamasfe.even-better-toml",

    // === Cairo / Starknet
    "starkware.cairo1",

    // === Git
    "eamodio.gitlens",
    "mhutchie.git-graph",

    // === DX utilities
    "streetsidesoftware.code-spell-checker",
    "usernamehw.errorlens",
    "antfu.iconify",
    "mikestead.dotenv",
    "naumovs.color-highlight",

    // === Editor polish
    "pkief.material-icon-theme"
  ],
  "unwantedRecommendations": [
    "hookyqr.beautify",
    "ms-vscode.vscode-typescript-tslint-plugin"
  ]
}
EOF
echo -e "  ${THEME_GREEN}✓${NC}  ~/.vscode/extensions.json written"

# --- Prettier
step_info "Writing ~/.prettierrc..."
cat << 'EOF' > ~/.prettierrc
{
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2,
  "semi": true,
  "arrowParens": "always",
  "endOfLine": "lf",
  "bracketSpacing": true,
  "plugins": ["prettier-plugin-solidity"]
}
EOF
echo -e "  ${THEME_GREEN}✓${NC}  ~/.prettierrc written"

# --- Solhint
step_info "Writing ~/.solhint.json..."
cat << 'EOF' > ~/.solhint.json
{
  "extends": "solhint:recommended",
  "rules": {
    "compiler-version": ["warn", ">=0.8.0"],
    "func-visibility": ["error", { "ignoreConstructors": true }],
    "max-line-length": ["warn", 120],
    "reason-string": ["warn", { "maxLength": 64 }],
    "no-console": "off",
    "no-empty-blocks": "off",
    "not-rely-on-time": "off"
  }
}
EOF
echo -e "  ${THEME_GREEN}✓${NC}  ~/.solhint.json written"

# --- Lint-staged
step_info "Writing ~/.lintstagedrc.json..."
cat << 'EOF' > ~/.lintstagedrc.json
{
  "*.{js,jsx,ts,tsx,json,css,scss,md}": ["prettier --write"],
  "*.sol": ["prettier --write", "solhint --fix"]
}
EOF
echo -e "  ${THEME_GREEN}✓${NC}  ~/.lintstagedrc.json written"

# --- Global gitignore
step_info "Writing ~/.gitignore_global..."
cat << 'EOF' > ~/.gitignore_global

# === Linux
.fuse_hidden*
.directory
.Trash-*
.nfs*

# === macOS
.DS_Store
.AppleDouble
.LSOverride
Icon
._*
.DocumentRevisions-V100
.fseventsd
.Spotlight-V100
.TemporaryItems
.Trashes
.VolumeIcon.icns
.com.apple.timemachine.donotpresent
.AppleDB
.AppleDesktop
Network Trash Folder
Temporary Items
.apdisk
*.icloud

# === Windows
Thumbs.db
Desktop.ini

# === VSCode
.vscode/*
!.vscode/settings.json
!.vscode/tasks.json
!.vscode/launch.json
!.vscode/extensions.json
!.vscode/*.code-snippets
.vscode-test
.history
*.vsix

# === JetBrains / IntelliJ
.idea/*
!.idea/codeStyles
!.idea/runConfigurations
*.iml
modules.xml
*.ipr
*.iws

# === Sublime Text
*.tmlanguage.cache
*.tmPreferences.cache
*.stTheme.cache
*.sublime-workspace
Package Control.cache/
Package Control.ca-certs/
Package Control.ca-bundle
Package Control.merged-ca-bundle
Package Control.user-ca-bundle
oscrypto-ca-bundle.crt
bh_unicode_properties.cache
GitHub.sublime-settings

# === Vim
[._]*.s[a-v][a-z]
[._]*.sw[a-p]
Session.vim
Sessionx.vim
.netrwhist
[._]*.un~

# === Version control merge artifacts
*.orig
*.BACKUP.*
*.BASE.*
*.LOCAL.*
*.REMOTE.*
*_BACKUP_*.txt
*_BASE_*.txt
*_LOCAL_*.txt
*_REMOTE_*.txt

# === Environment and Secrets
.env
.env.*
.env.local
.env.*.local
.env.production
.env.staging
.env.development
.env.test
!.env.example

# Private keys / crypto material
*.pem
*.key
*.p12
*.pfx
*.crt
*.csr

# Wallet / keystore
keystore/
wallets/
*.keystore
*.mnemonic

# SSH
**/.ssh/id_*
**/.ssh/*_id_*
**/.ssh/known_hosts

# === Node / JS / TS
node_modules/
.npm
.pnp
.pnp.js
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*
lerna-debug.log*
.pnpm-debug.log*
.parcel-cache
.nyc_output
.eslintcache
.stylelintcache
coverage/
*.lcov
*.tsbuildinfo

# === Next.js
.next/
.next/cache
out/
.vercel

# === Nuxt
.nuxt
.nuxt-*
.output
.gen
dist/

# === Remix
.cache
/public/build

# === Rust
target/
debug/
**/*.rs.bk
rust-project.json
*.profraw
*.profdata

# === Solidity / Web3

# Hardhat
artifacts/
cache/
typechain/
coverage/

# Foundry
out/
broadcast/
forge-cache/

# Truffle
build
build_webpack
.truffle-solidity-loader
blockchain/geth/**
blockchain/keystore/**
blockchain/history

# Geth
/geth
/keystore
history

# ABI exports
*.abi
*.bin

# === Redis
dump.rdb
*.rdb

# === Databases
*.accdb
*.db
*.dbf
*.mdb
*.sqlite3
*.db-shm
*.db-wal
*.mdf
*.ldf
*.ndf

# === Python / Django
__pycache__/
*.py[cod]
*.so
.venv
venv/
env/
ENV/
.pytest_cache/
.mypy_cache/
.coverage
htmlcov/
db.sqlite3
media/

# === Go
*.test
go.work
go.sum

# === Java
*.class
*.jar
*.war
*.ear
*.nar
hs_err_pid*
replay_pid*

# === C# / .NET
[Dd]ebug/
[Rr]elease/
x64/
x86/
*.user
*.suo
*.pdb
*.cache
.vs/

# === Flutter / Dart
.dart_tool/
.packages
.pub-cache/
.flutter-plugins
.flutter-plugins-dependencies
build/
doc/api/

# === Laravel / PHP
/vendor/
storage/*.key
public/storage
public/hot
.phpunit.result.cache

# === Ruby / Rails
*.gem
.bundle
/vendor/bundle
/log/*
/tmp/*
!/log/.keep
!/tmp/.keep

# === WordPress
/wp-admin/
/wp-includes/
/wp-content/uploads/
wp-config.php
.htaccess

# === Build output / generic
obj/
*.log
*.tmp
*.pid
*.seed
*.tgz

# === Docker
docker-compose.override.yml
docker-compose.local.yml
docker-compose.*.local.yml
.docker.env
.env.docker
.env.docker.local
*.pid
*.cid
*.sock
docker.log
docker-*.log
.docker/
docker-data/
docker-tmp/

# === Package managers
package-lock.json
pnpm-lock.yaml
.yarn/
.yarn-cache/
.yarnrc.yml
.pnp.*
.yarn-integrity
bun.lockb
.turbo/

# === Java / Gradle
.gradle/
gradle-app.setting

# === Lighthouse CI
.lighthouseci/

EOF
echo -e "  ${THEME_GREEN}✓${NC}  ~/.gitignore_global written"

step_info "Registering global gitignore..."
git config --global core.excludesfile ~/.gitignore_global
echo -e "  ${THEME_GREEN}✓${NC}  core.excludesfile set."

phase_done "✅" "All global config files written."
fi
pause_next "Phase 6 (Summary)"


# === Phase 6: Summary

echo ""
echo -e "${THEME_GREEN}  ╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${THEME_GREEN}  ║${NC}  ${BOLD}${GREEN}  Setup Complete!${NC}                                       ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  ${THEME_GREEN}✓${NC}  Git       —  $(git --version 2>/dev/null | cut -d' ' -f3 || echo 'installed')                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  ${THEME_GREEN}✓${NC}  Hooks     —  pre-commit · pre-push (in ~/.git-hooks)   ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  ${THEME_GREEN}✓${NC}  Helpers   —  gclone · gitprofile (in shell RC)         ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  ${THEME_GREEN}✓${NC}  Aliases   —  lg · ll · st · co · br · undo · wip       ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"

# Profiles panel
ALL_SUMMARY=()
while IFS= read -r line; do
  [ -n "$line" ] || continue
  ALL_SUMMARY+=("$line")
done < "$IDENTITIES_FILE"

if [ "${#ALL_SUMMARY[@]}" -gt 0 ]; then
  echo -e "${THEME_GREEN}  ╠══════════════════════════════════════════════════════════╣${NC}"
  echo -e "${THEME_GREEN}  ║${NC}  ${BOLD}Configured profiles:${NC}                                     ${THEME_GREEN}║${NC}"
  echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"

  GLOBAL_DISPLAY_NAME=$(git config --global user.name 2>/dev/null || true)

  for entry in "${ALL_SUMMARY[@]}"; do
    S_ALIAS=$(echo "$entry" | cut -d'|' -f1)
    S_NAME=$(echo "$entry" | cut -d'|' -f2)
    S_EMAIL=$(echo "$entry" | cut -d'|' -f3)
    S_LABEL=$(echo "$S_ALIAS" | sed 's/github-//')
    GLOBAL_MARKER=""
    [ "$S_NAME" = "$GLOBAL_DISPLAY_NAME" ] && GLOBAL_MARKER="  (global default)"

    echo -e "${THEME_GREEN}  ║${NC}  ${THEME_GREEN}✓${NC}  [${S_ALIAS}]${GLOBAL_MARKER}               ${THEME_GREEN}║${NC}"
    echo -e "${THEME_GREEN}  ║${NC}      ${S_NAME} · ${S_EMAIL}  ${THEME_GREEN}║${NC}"
    echo -e "${THEME_GREEN}  ║${NC}      Key:  ~/.ssh/id_ed25519_${S_LABEL}                    ${THEME_GREEN}║${NC}"
    echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"
  done
fi

echo -e "${THEME_GREEN}  ╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${THEME_GREEN}  ║${NC}  ${BOLD}How to use:${NC}                                              ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  Clone any GitHub repo (picks identity interactively):   ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}    gclone https://github.com/<user>/<repo>               ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  The pre-commit hook sets identity on first commit.      ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  The pre-push hook confirms who is pushing.              ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  Manual switch (current shell session only):             ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}    gitprofile <alias>                                    ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}    gitprofile            (list all profiles)              ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  See who is committing in this repo:                     ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}    git whoami                                            ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${THEME_GREEN}  ║${NC}  ${BOLD}Next steps:${NC}                                              ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  1.  Restart your terminal (loads gclone, gitprofile)    ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  2.  Restart VS Code if it was open                      ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  3.  Install recommended VS Code extensions:             ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}        code --install-extension esbenp.prettier-vscode   ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}        code --install-extension dbaeumer.vscode-eslint   ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}        code --install-extension rust-lang.rust-analyzer  ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}        code --install-extension Vue.volar                ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}        code --install-extension starkware.cairo1         ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  4.  Edit ~/.gitidentities to add/remove profiles later  ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${MAGENTA}${BOLD}Happy hacking. — Olorunshogo${NC}"
echo ""
