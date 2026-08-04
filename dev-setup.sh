#!/usr/bin/env bash
set -euo pipefail

# === Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
# Theme green — matches the portfolio accent (#016630) via 24-bit ANSI
THEME_GREEN='\033[38;2;1;102;48m'

# === Helpers

print_banner() {
  echo -e "${THEME_GREEN}"
  echo "  ╔══════════════════════════════════════════════════════════╗"
  echo "  ║                                                          ║"
  echo "  ║    CoreDev Machine Setup  ·  by Olorunshogo             ║"
  echo "  ║    Rust · Node.js 24 · pnpm · Git · SSH · Configs       ║"
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
  echo -e "  ${BOLD}${YELLOW}Step ${step}/${total}${NC}  ${emoji}  ${BOLD}${title}${NC}"
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

pause_next() {
  local label="${1:-next step}"
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
      echo -e "  ${DIM}This field is required — please enter a value.${NC}"
    fi
  done
  eval "${varname}=\"\${value}\""
}

confirm_vars() {
  echo ""
  echo -e "  ${DIM}Captured:${NC}"
  local i
  for i in "$@"; do
    echo -e "    ${THEME_GREEN}→${NC}  ${i}"
  done
  echo ""
  pause_start
}

step_info() {
  echo -e "  ${DIM}→ $*${NC}"
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

# === Pre-flight

clear
print_banner

echo -e "  ${DIM}Running pre-flight checks...${NC}"
echo ""

# OS detection
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  OS="mac"
else
  echo -e "  ${YELLOW}⚠  Unsupported OS: ${OSTYPE}. Exiting.${NC}"
  exit 1
fi
echo -e "  ${THEME_GREEN}✓${NC}  OS detected: ${BOLD}${OS}${NC}"

# Not root
if [ "$(id -u)" -eq 0 ]; then
  echo -e "  ${YELLOW}⚠  Running as root is not recommended. Continue anyway? (y/N) ${NC}"
  read -r _confirm
  [[ "$_confirm" =~ ^[Yy]$ ]] || exit 1
fi
echo -e "  ${THEME_GREEN}✓${NC}  User: ${BOLD}$(whoami)${NC}"

# Internet
if ! curl -s --head --connect-timeout 5 https://google.com > /dev/null 2>&1; then
  echo -e "  ${YELLOW}⚠  No internet connection detected. Some steps may fail.${NC}"
else
  echo -e "  ${THEME_GREEN}✓${NC}  Internet: reachable"
fi

GIT_NAME=""
GIT_USERNAME=""
GIT_EMAIL=""

echo ""
echo -e "  ${BOLD}6 phases will run. Choose to run or skip each one.${NC}"
echo ""
pause_next "Phase 1"


# === Phase 1: System Update & Essentials

phase_start 1 6 "📦" "System Update & Essentials" \
  "Updates system packages and installs: curl, wget, git, build-essential, ca-certificates"

if phase_prompt "skip system update"; then
  if [ "$OS" = "linux" ]; then
    step_info "Running apt-get update (GPG warnings on third-party repos are non-fatal)..."
    sudo apt-get update -qq 2>/dev/null || sudo apt-get update -qq || true
    step_info "Upgrading installed packages..."
    sudo apt-get upgrade -y -qq
    step_info "Installing essentials..."
    sudo apt-get install -y curl wget git build-essential ca-certificates
  elif [ "$OS" = "mac" ]; then
    if ! command -v brew &> /dev/null; then
      step_info "Homebrew not found. Installing..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    step_info "Running brew update & upgrade..."
    brew update
    brew upgrade
    step_info "Installing essentials..."
    brew install curl wget git
  fi

  phase_done "✅" "System updated. curl, wget, git, and build tools are ready."
fi
pause_next "Phase 2 (Rust)"


# === Phase 2: Rust via rustup

phase_start 2 6 "🦀" "Rust via rustup" \
  "Installs rustup, the stable toolchain, rustfmt, and clippy. Sources Cargo env for this session."

if phase_prompt "skip Rust installation"; then
  step_info "Downloading and running rustup installer..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

  step_info "Loading Cargo environment into current shell..."
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"

  step_info "Adding rustfmt and clippy components..."
  rustup component add rustfmt clippy

  echo ""
  echo -e "  ${DIM}Versions installed:${NC}"
  echo -e "    ${THEME_GREEN}→${NC}  $(rustc --version)"
  echo -e "    ${THEME_GREEN}→${NC}  $(cargo --version)"

  phase_done "✅" "Rust installed successfully with rustfmt & clippy."
fi
pause_next "Phase 3 (Node.js)"


# === Phase 3: Node.js 24 via nvm

phase_start 3 6 "📦" "Node.js 24 via nvm" \
  "Installs nvm v0.40.4, then Node.js 24 (Active LTS). Sets node 24 as the default alias."

if phase_prompt "skip Node.js installation"; then
  step_info "Downloading and running nvm install script..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash

  step_info "Loading nvm into the current shell session..."
  export NVM_DIR="$HOME/.nvm"
  # shellcheck source=/dev/null
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  # shellcheck source=/dev/null
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

  step_info "Installing Node.js 24 (Active LTS)..."
  nvm install 24
  nvm use 24
  nvm alias default 24

  echo ""
  echo -e "  ${DIM}Versions installed:${NC}"
  echo -e "    ${THEME_GREEN}→${NC}  node  $(node -v)"
  echo -e "    ${THEME_GREEN}→${NC}  npm   $(npm -v)"

  phase_done "✅" "Node.js 24 installed and set as the default."
fi
pause_next "Phase 4 (pnpm & yarn)"


# === Phase 4: Corepack + pnpm + yarn

phase_start 4 6 "⚡" "Corepack · pnpm · yarn" \
  "Enables Corepack (ships with Node 16+) and activates the latest pnpm and stable yarn. No global npm install needed."

if phase_prompt "skip Corepack and pnpm setup"; then
  step_info "Enabling Corepack..."
  corepack enable

  step_info "Activating pnpm@latest..."
  corepack prepare pnpm@latest --activate

  step_info "Activating yarn@stable..."
  corepack prepare yarn@stable --activate

  echo ""
  echo -e "  ${DIM}Versions active:${NC}"
  echo -e "    ${THEME_GREEN}→${NC}  npm   $(npm -v)"
  echo -e "    ${THEME_GREEN}→${NC}  pnpm  $(pnpm -v)"
  echo -e "    ${THEME_GREEN}→${NC}  yarn  $(yarn -v)"

  phase_done "✅" "Corepack enabled. npm, pnpm, and yarn are all active."
fi
pause_next "Phase 5 (Git + SSH)"


# === Phase 5: Git + SSH + Commit Signing

phase_start 5 6 "🔧" "Git · SSH · Commit Signing" \
  "Checks and updates Git, configures identity, generates an ed25519 SSH key, registers it with GitHub, and enables SSH commit signing."

if phase_prompt "skip Git and SSH setup"; then

# Git check/update
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
    sudo apt-get install -y git -qq
  elif [ "$OS" = "mac" ]; then
    brew install git
  fi
  echo -e "  ${THEME_GREEN}✓${NC}  Git installed: $(git --version)"
fi

echo ""
echo -e "  ${DIM}A few details are needed before this phase continues.${NC}"
echo ""

collect_var "Please enter your full name (appears on every git commit):" GIT_NAME
collect_var "Please enter your GitHub username (e.g. Olorunshogo):" GIT_USERNAME
collect_var "Please enter your email address (used for git identity and SSH key):" GIT_EMAIL

confirm_vars \
  "Name      →  ${GIT_NAME}" \
  "Username  →  ${GIT_USERNAME}" \
  "Email     →  ${GIT_EMAIL}"

step_info "Configuring Git global identity..."
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
echo -e "  ${THEME_GREEN}✓${NC}  Git identity set."

# SSH Key
echo ""
KEY_FILE="$HOME/.ssh/id_ed25519"
PUB_FILE="${KEY_FILE}.pub"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -f "$PUB_FILE" ]; then
  step_info "Existing ed25519 key found at ${KEY_FILE} — reusing it."
elif [ -f "$HOME/.ssh/id_rsa.pub" ]; then
  step_info "Existing RSA key found — reusing it instead of generating a new one."
  KEY_FILE="$HOME/.ssh/id_rsa"
  PUB_FILE="${KEY_FILE}.pub"
else
  step_info "No existing key found. Generating a new ed25519 SSH key..."
  ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$KEY_FILE" -N ""
  echo -e "  ${THEME_GREEN}✓${NC}  Key generated at ${KEY_FILE}"
fi

echo ""
echo -e "${THEME_GREEN}  ──────────────────────────────────────────────────────────${NC}"
echo -e "  ${BOLD}Your public SSH key${NC}"
echo -e "${THEME_GREEN}  ──────────────────────────────────────────────────────────${NC}"
echo ""
echo -e "${CYAN}"
cat "$PUB_FILE"
echo -e "${NC}"
echo -e "${THEME_GREEN}  ──────────────────────────────────────────────────────────${NC}"
echo ""
echo -e "  ${BOLD}Add this key to GitHub now:${NC}"
echo ""
echo -e "    ${YELLOW}1.${NC}  Go to  ${BOLD}https://github.com/settings/keys${NC}"
echo -e "    ${YELLOW}2.${NC}  Click  ${BOLD}New SSH key${NC}"
echo -e "    ${YELLOW}3.${NC}  Set    ${BOLD}Title${NC}  to something like  ${DIM}$(hostname) — ed25519${NC}"
echo -e "    ${YELLOW}4.${NC}  Set    ${BOLD}Key type${NC}  to  ${DIM}Authentication Key${NC}"
echo -e "    ${YELLOW}5.${NC}  Paste  the key printed above into the  ${BOLD}Key${NC}  field"
echo -e "    ${YELLOW}6.${NC}  Click  ${BOLD}Add SSH key${NC}"
echo ""
echo -e "  ${DIM}When you are done, type  ${BOLD}done${NC}${DIM}  below and press Enter.${NC}"
echo ""

DONE_INPUT=""
while [[ "${DONE_INPUT,,}" != "done" ]]; do
  read -r -p "$(echo -e "  ${YELLOW}Type 'done' and press Enter when the key is added:${NC} ")" DONE_INPUT
  if [[ "${DONE_INPUT,,}" != "done" ]]; then
    echo -e "  ${DIM}Type the word  done  and press Enter.${NC}"
  fi
done
echo ""

step_info "Starting ssh-agent and adding key..."
eval "$(ssh-agent -s)" > /dev/null
ssh-add "$KEY_FILE"

echo ""
step_info "Testing GitHub SSH connection..."
SSH_RESULT=$(ssh -T git@github.com 2>&1 || true)
echo -e "  ${DIM}${SSH_RESULT}${NC}"

if echo "$SSH_RESULT" | grep -q "successfully authenticated"; then
  echo -e "  ${THEME_GREEN}✓${NC}  GitHub SSH connection verified."
else
  echo -e "  ${YELLOW}⚠  Could not verify GitHub connection — you can test manually with: ssh -T git@github.com${NC}"
fi

echo ""
step_info "Enabling SSH commit signing..."
git config --global gpg.format ssh
git config --global user.signingkey "$PUB_FILE"
git config --global commit.gpgsign true
git config --global tag.gpgsign true
echo -e "  ${THEME_GREEN}✓${NC}  Every commit and tag will show Verified on GitHub."

echo ""
step_info "Applying CoreDev git globals..."

# Identity & core
git config --global init.defaultBranch main
git config --global core.editor "code --wait"
git config --global core.autocrlf false
git config --global core.safecrlf warn

# Pull, push, rebase
git config --global pull.rebase true
git config --global rebase.autoStash true
git config --global push.default current
git config --global push.autoSetupRemote true
git config --global fetch.prune true

# Merge & diff
git config --global merge.conflictstyle diff3
git config --global diff.colorMoved zebra
git config --global rerere.enabled true

# Colors & UX
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

echo -e "  ${THEME_GREEN}✓${NC}  Git aliases and CoreDev globals applied."

  phase_done "✅" "Git identity set. SSH key active. Commit signing enabled. Aliases ready."
fi
pause_next "Phase 6 (Global Configs)"


# === Phase 6: Global Config Files

phase_start 6 6 "📁" "Global Config Files" \
  "Writes ~/.vscode/settings.json · ~/.prettierrc · ~/.solhint.json · ~/.lintstagedrc.json · ~/.gitignore_global"

if phase_prompt "skip global config files"; then

mkdir -p ~/.vscode

# VS Code settings
step_info "Writing ~/.vscode/settings.json..."
cat << 'EOF' > ~/.vscode/settings.json
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": "explicit"
  },
  "editor.tabSize": 2,
  "editor.rulers": [100],
  "editor.bracketPairColorization.enabled": true,
  "editor.guides.bracketPairs": "active",
  "editor.stickyScroll.enabled": true,
  "editor.inlayHints.enabled": "on",
  "editor.linkedEditing": true,
  "editor.suggest.preview": true,
  "editor.acceptSuggestionOnEnter": "smart",
  "eslint.validate": [
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact"
  ],
  "eslint.run": "onSave",
  "typescript.tsdk": "node_modules/typescript/lib",
  "typescript.enablePromptUseWorkspaceTsdk": true,
  "typescript.preferences.quoteStyle": "single",
  "typescript.updateImportsOnFileMove.enabled": "always",
  "typescript.inlayHints.parameterNames.enabled": "literals",
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
  "prettier.requireConfig": true,
  "prettier.printWidth": 100,
  "prettier.tabWidth": 2,
  "prettier.singleQuote": true,
  "prettier.trailingComma": "all",
  "prettier.semi": true,
  "prettier.bracketSpacing": true,
  "solidity.compileUsingRemoteVersion": "v0.8.24",
  "solidity.formatter": "prettier",
  "solidity.linter": "solhint",
  "rust-analyzer.check.command": "clippy",
  "rust-analyzer.checkOnSave": true,
  "rust-analyzer.procMacro.enable": true,
  "rust-analyzer.cargo.features": "all",
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "files.trimFinalNewlines": true,
  "files.eol": "\n",
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
    "**/node_modules/**": true,
    "**/target/**": true
  },
  "search.exclude": {
    "**/node_modules": true,
    "**/package-lock.json": true,
    "**/target": true,
    "**/.next": true
  },
  "explorer.fileNesting.enabled": true,
  "explorer.fileNesting.patterns": {
    "*.ts": "${capture}.js, ${capture}.d.ts",
    "package.json": "package-lock.json, .npmrc, .nvmrc, .node-version, pnpm-lock.yaml",
    ".eslintrc.*": ".eslintignore, .prettierrc, .prettierignore, .editorconfig",
    "next.config.*": "next-env.d.ts",
    "nuxt.config.*": ".nuxtrc"
  },
  "npm.packageManager": "pnpm",
  "git.autofetch": true,
  "git.confirmSync": false,
  "git.enableSmartCommit": true
}
EOF
echo -e "  ${THEME_GREEN}✓${NC}  ~/.vscode/settings.json written"

# Prettier
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

# Solhint
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

# Lint-staged
step_info "Writing ~/.lintstagedrc.json..."
cat << 'EOF' > ~/.lintstagedrc.json
{
  "*.{js,jsx,ts,tsx,json,css,scss,md}": ["prettier --write"],
  "*.sol": ["prettier --write", "solhint --fix"]
}
EOF
echo -e "  ${THEME_GREEN}✓${NC}  ~/.lintstagedrc.json written"

# Global gitignore
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

# === Sublime
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

# === Environment & Secrets
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
out/
.vercel
.next/cache

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


# === Final Summary

echo ""
echo -e "${THEME_GREEN}  ╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${THEME_GREEN}  ║${NC}  ${BOLD}${GREEN}  Setup Complete!${NC}                                       ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  ${THEME_GREEN}✓${NC}  Rust     —  $(rustc --version 2>/dev/null | cut -d' ' -f2 || echo 'installed')$(printf '%*s' 1 '')                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  ${THEME_GREEN}✓${NC}  Node.js  —  $(node -v 2>/dev/null || echo 'installed')$(printf '%*s' 1 '')                             ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  ${THEME_GREEN}✓${NC}  pnpm     —  $(pnpm -v 2>/dev/null || echo 'installed')$(printf '%*s' 1 '')                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  ${THEME_GREEN}✓${NC}  Git      —  $(git --version 2>/dev/null | cut -d' ' -f3 || echo 'installed')$(printf '%*s' 1 '')                       ${THEME_GREEN}║${NC}"
if [ -n "$GIT_USERNAME" ]; then
  echo -e "${THEME_GREEN}  ║${NC}  ${THEME_GREEN}✓${NC}  GitHub   —  ${GIT_USERNAME} · ${GIT_EMAIL}$(printf '%*s' 1 '')  ${THEME_GREEN}║${NC}"
  echo -e "${THEME_GREEN}  ║${NC}  ${THEME_GREEN}✓${NC}  Signing  —  SSH commit signing active                  ${THEME_GREEN}║${NC}"
else
  echo -e "${THEME_GREEN}  ║${NC}  ${DIM}↷${NC}  GitHub   —  skipped                                  ${THEME_GREEN}║${NC}"
fi
echo -e "${THEME_GREEN}  ║${NC}  ${THEME_GREEN}✓${NC}  Aliases  —  lg, ll, st, co, br, undo, unstage, wip     ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${THEME_GREEN}  ║${NC}  ${BOLD}Next steps:${NC}                                              ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  1.  Restart your terminal                               ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  2.  Restart VS Code if it was open                      ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}  3.  Install VS Code extensions:                         ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}      code --install-extension rust-lang.rust-analyzer    ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}      code --install-extension esbenp.prettier-vscode     ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}      code --install-extension dbaeumer.vscode-eslint     ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}      code --install-extension NomicFoundation.hardhat-solidity  ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}      code --install-extension Vue.volar                  ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}      code --install-extension starkware.cairo1           ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ║${NC}                                                          ${THEME_GREEN}║${NC}"
echo -e "${THEME_GREEN}  ╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${MAGENTA}${BOLD}Happy hacking. — Olorunshogo${NC}"
echo ""
