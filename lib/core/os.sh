#!/usr/bin/env bash
# OS and package manager detection. Sourced, never executed.
#
# Sets: IPILE_OS  (linux|mac)
#       IPILE_PM  (apt|dnf|pacman|apk|zypper|brew|none)
#       IPILE_DISTRO (best effort label, informational only)

os_detect() {
  case "$OSTYPE" in
    linux-gnu*) IPILE_OS="linux" ;;
    darwin*) IPILE_OS="mac" ;;
    *)
      ui_err "Unsupported OS: ${OSTYPE}"
      return 1
      ;;
  esac

  IPILE_DISTRO="$IPILE_OS"
  if [ "$IPILE_OS" = "linux" ] && [ -r /etc/os-release ]; then
    IPILE_DISTRO="$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-linux}")"
  elif [ "$IPILE_OS" = "mac" ]; then
    IPILE_DISTRO="macOS $(sw_vers -productVersion 2>/dev/null || printf 'unknown')"
  fi

  if [ "$IPILE_OS" = "mac" ]; then
    IPILE_PM="brew"
  elif command -v apt-get >/dev/null 2>&1; then
    IPILE_PM="apt"
  elif command -v dnf >/dev/null 2>&1; then
    IPILE_PM="dnf"
  elif command -v pacman >/dev/null 2>&1; then
    IPILE_PM="pacman"
  elif command -v apk >/dev/null 2>&1; then
    IPILE_PM="apk"
  elif command -v zypper >/dev/null 2>&1; then
    IPILE_PM="zypper"
  else
    IPILE_PM="none"
  fi

  export IPILE_OS IPILE_PM IPILE_DISTRO
  return 0
}

# True when this looks like WSL. ssh-agent does not persist there and the
# clipboard behaves differently, so callers warn rather than assume.
os_is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
  grep -qi microsoft /proc/version 2>/dev/null && return 0
  return 1
}

os_needs_sudo() {
  [ "$IPILE_OS" = "linux" ] && [ "$(id -u)" -ne 0 ]
}

# os_sudo <cmd...>. Prefixes sudo only where it is actually needed.
os_sudo() {
  if os_needs_sudo; then
    run sudo "$@"
  else
    run "$@"
  fi
}

# os_pm_refresh. Update the package index.
os_pm_refresh() {
  case "$IPILE_PM" in
    apt) os_sudo apt-get update -qq ;;
    dnf) os_sudo dnf -q makecache ;;
    pacman) os_sudo pacman -Syy --noconfirm ;;
    apk) os_sudo apk update -q ;;
    zypper) os_sudo zypper --non-interactive refresh ;;
    brew) run brew update ;;
    none) ui_warn "No supported package manager found. Skipping refresh." ;;
  esac
}

# os_pm_upgrade. Upgrade everything already installed.
os_pm_upgrade() {
  case "$IPILE_PM" in
    apt) os_sudo apt-get upgrade -y -qq ;;
    dnf) os_sudo dnf -y -q upgrade ;;
    pacman) os_sudo pacman -Su --noconfirm ;;
    apk) os_sudo apk upgrade -q ;;
    zypper) os_sudo zypper --non-interactive update ;;
    brew) run brew upgrade ;;
    none) ui_warn "No supported package manager found. Skipping upgrade." ;;
  esac
}

# os_pm_install <package...>. Package names that differ per manager are
# translated by os_pm_pkg before they get here.
os_pm_install() {
  [ $# -eq 0 ] && return 0
  case "$IPILE_PM" in
    apt) os_sudo apt-get install -y -qq "$@" ;;
    dnf) os_sudo dnf -y -q install "$@" ;;
    pacman) os_sudo pacman -S --needed --noconfirm "$@" ;;
    apk) os_sudo apk add -q "$@" ;;
    zypper) os_sudo zypper --non-interactive install "$@" ;;
    brew) run brew install "$@" ;;
    none)
      ui_warn "No supported package manager. Install these yourself: $*"
      return 0
      ;;
  esac
}

# os_pm_pkg <logical-name>. Maps a logical package to this manager's name.
# Prints nothing when the manager has no such package, which is the signal
# to skip it rather than fail the whole install.
os_pm_pkg() {
  local logical="$1"
  case "$logical" in
    build-essential)
      case "$IPILE_PM" in
        apt) printf 'build-essential' ;;
        dnf) printf 'gcc gcc-c++ make' ;;
        pacman) printf 'base-devel' ;;
        apk) printf 'build-base' ;;
        zypper) printf 'gcc gcc-c++ make' ;;
        brew) printf '' ;;
      esac
      ;;
    ca-certificates)
      case "$IPILE_PM" in
        brew) printf '' ;;
        *) printf 'ca-certificates' ;;
      esac
      ;;
    *) printf '%s' "$logical" ;;
  esac
}

# os_upgrade_one <package>. Upgrade a single package, never fatal.
os_upgrade_one() {
  local pkg="$1"
  case "$IPILE_PM" in
    apt) os_sudo apt-get install -y --only-upgrade -qq "$pkg" || true ;;
    dnf) os_sudo dnf -y -q upgrade "$pkg" || true ;;
    pacman) os_sudo pacman -S --needed --noconfirm "$pkg" || true ;;
    apk) os_sudo apk upgrade -q "$pkg" || true ;;
    zypper) os_sudo zypper --non-interactive update "$pkg" || true ;;
    brew) run brew upgrade "$pkg" || true ;;
    none) : ;;
  esac
}

# Homebrew is a prerequisite for everything on macOS, so it installs itself.
os_ensure_brew() {
  [ "$IPILE_OS" = "mac" ] || return 0
  command -v brew >/dev/null 2>&1 && return 0
  ui_info "Homebrew not found. Installing it first."
  run /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}
