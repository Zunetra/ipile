#!/usr/bin/env bash
# Terminal output and prompts. The single source of truth for both.
# Sourced, never executed. Kept bash 3.2 safe: no associative arrays,
# no ${VAR,,}, no mapfile, no namerefs.

# === Colours

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
# Theme green, matches the portfolio accent (#016630) via 24-bit ANSI
THEME_GREEN='\033[38;2;1;102;48m'

# Logo palette, for the banner only. Each plate of the mark gets a lit
# top edge and a darker bottom edge, which is what makes the stack read as
# three solid objects rather than six lines.
PLATE1_LIT='\033[38;2;255;255;255m'
PLATE1_DARK='\033[38;2;150;168;186m'
PLATE2_LIT='\033[38;2;86;102;120m'
PLATE2_DARK='\033[38;2;42;52;64m'
PLATE3_LIT='\033[38;2;52;227;155m'
PLATE3_DARK='\033[38;2;14;150;104m'
GLOW='\033[38;2;11;122;85m'

# The wordmark falls from white to a soft mint over its rows, so it picks
# up the emerald of the plate it sits beside without losing legibility.
WORD1='\033[38;2;255;255;255m'
WORD2='\033[38;2;226;242;236m'
WORD3='\033[38;2;198;232;218m'
WORD4='\033[38;2;170;222;201m'
WORD5='\033[38;2;142;212;184m'
LOGO_EMERALD='\033[38;2;16;185;129m'

# Colour is a terminal affordance, not content. Piping into a file or a
# pager, or setting NO_COLOR, must not produce escape sequences.
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
  CYAN=''; GREEN=''; YELLOW=''; RED=''; MAGENTA=''
  BOLD=''; DIM=''; NC=''; THEME_GREEN=''
  PLATE1_LIT=''; PLATE1_DARK=''; PLATE2_LIT=''; PLATE2_DARK=''
  PLATE3_LIT=''; PLATE3_DARK=''; GLOW=''
  WORD1=''; WORD2=''; WORD3=''; WORD4=''; WORD5=''; LOGO_EMERALD=''
fi

RULE="  ──────────────────────────────────────────────────────────"

# === Output

# === The banner
#
# The mark is the logo's three stacked plates, each drawn as a lit top
# edge over a darker bottom edge so it reads as a solid object rather
# than two lines. Every plate shares one column, top edges at 3 and
# bottom edges at 4, so the stack is square rather than stepped.
#
# In the wordmark, the e carries a dot above and a dot below, both
# matching the i tittles in size, shading and colour, so the three marks
# read as one family. It nods at the Yoruba spelling of the name without
# the banner having to render combining accents, which no block font does
# cleanly. Drawn art either way: every machine-read surface stays plain
# ASCII 'ipile', per the naming rule in the README.
#
# The columns are load bearing. The wordmark starts at column 16 on every
# row, and each line pays for its own mark width in the spaces that
# follow it, so changing a plate's indent means changing that line's
# trailing padding by the same amount.
ui_banner() {
  local title="$1"
  local subtitle="$2"
  echo ""
  echo -e "   ${PLATE1_LIT}▗▄▄▄▄▄▄▄▄▄▖${NC}      ${LOGO_EMERALD}██${NC}                  ${LOGO_EMERALD}██${NC}     ${WORD1}▄▄▄▄${NC}         ${LOGO_EMERALD}██${NC}"
  echo -e "   ${PLATE1_LIT}▐   ${LOGO_EMERALD}>_${PLATE1_LIT}    ▌${NC}      ${GLOW}▀▀${NC}                  ${GLOW}▀▀${NC}     ${WORD1}▀▀██${NC}         ${GLOW}▀▀${NC}"
  echo -e "    ${PLATE1_DARK}▝▀▀▀▀▀▀▀▘${NC}   ${WORD2}  ████     ██▄███▄    ████       ██       ▄████▄${NC}"
  echo -e "   ${PLATE2_LIT}▗▄▄▄▄▄▄▄▄▄▖${NC}  ${WORD3}    ██     ██▀  ▀██     ██       ██      ██▄▄▄▄██${NC}"
  echo -e "    ${PLATE2_DARK}▝▀▀▀▀▀▀▀▘${NC}   ${WORD3}    ██     ██    ██     ██       ██      ██▀▀▀▀▀▀${NC}"
  echo -e "   ${PLATE3_LIT}▗▄▄▄▄▄▄▄▄▄▖${NC}  ${WORD4} ▄▄▄██▄▄▄  ███▄▄██▀  ▄▄▄██▄▄▄    ██▄▄▄   ▀██▄▄▄▄█${NC}"
  echo -e "    ${PLATE3_DARK}▝▀▀▀▀▀▀▀▘${NC}   ${WORD5} ▀▀▀▀▀▀▀▀  ██ ▀▀▀    ▀▀▀▀▀▀▀▀     ▀▀▀▀     ▀▀▀▀▀${NC}"
  echo -e "    ${GLOW}░░░░░░░░░${NC}   ${WORD5}           ██${NC}                               ${LOGO_EMERALD}██${NC}"
  echo ""
  echo -e "   ${PLATE3_LIT}‹${NC} ${LOGO_EMERALD}foundation for your workspace${NC} ${PLATE3_LIT}›${NC}"
  echo -e "   ${CYAN}${title}${NC}  ${DIM}·${NC}  ${DIM}${subtitle}${NC}"
  echo ""
}

ui_rule() {
  echo -e "${THEME_GREEN}${RULE}${NC}"
}

ui_heading() {
  local emoji="$1"
  local title="$2"
  local desc="$3"
  echo ""
  ui_rule
  echo -e "  ${emoji}  ${BOLD}${title}${NC}"
  [ -n "$desc" ] && echo -e "  ${DIM}${desc}${NC}"
  ui_rule
  echo ""
}

ui_info() { echo -e "  ${DIM}→ $*${NC}"; }
ui_ok()   { echo -e "  ${THEME_GREEN}✓${NC}  $*"; }
ui_warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
ui_err()  { echo -e "  ${RED}✗${NC}  $*" >&2; }
ui_skip() { echo -e "  ${DIM}↷  $*${NC}"; }
ui_dry()  { echo -e "  ${MAGENTA}[dry-run]${NC} ${DIM}$*${NC}"; }

ui_done() {
  echo ""
  echo -e "  ${THEME_GREEN}${BOLD}✅  $*${NC}"
  echo ""
}

# === Prompts
#
# Every prompt honours IPILE_ASSUME_YES. In that mode a prompt with a
# safe default takes the default and says so, and a prompt with no
# default is a hard error rather than a silent guess.

ui_pause() {
  local label="${1:-continue}"
  [ "${IPILE_ASSUME_YES:-0}" = "1" ] && return 0
  read -r -p "$(echo -e "  ${DIM}Press Enter to ${label}...${NC} ")" _ || true
  echo ""
}

# ui_ask <prompt> <default> <varname>. Empty default means required.
ui_ask() {
  local prompt="$1"
  local default="$2"
  local varname="$3"
  # Prefixed because this gets eval-assigned into the caller's scope. A
  # caller whose own variable is named 'value' would otherwise have our
  # local assigned instead of theirs, and would read back nothing.
  local __ui_value=""

  if [ "${IPILE_ASSUME_YES:-0}" = "1" ]; then
    if [ -z "$default" ]; then
      ui_err "Non-interactive run needs a value for: ${prompt}"
      return 1
    fi
    eval "${varname}=\"\${default}\""
    ui_info "${prompt} ${default}"
    return 0
  fi

  while true; do
    if [ -n "$default" ]; then
      read -r -p "$(echo -e "  ${YELLOW}${prompt}${NC} ${DIM}[${default}]${NC} ")" __ui_value
      __ui_value="${__ui_value:-$default}"
    else
      read -r -p "$(echo -e "  ${YELLOW}${prompt}${NC} ")" __ui_value
    fi
    [ -n "$__ui_value" ] && break
    echo -e "  ${DIM}This field is required.${NC}"
  done
  eval "${varname}=\"\${__ui_value}\""
}

# ui_confirm <prompt> <default y|n>
ui_confirm() {
  local prompt="$1"
  local default="${2:-n}"
  local hint="y/N"
  [ "$default" = "y" ] && hint="Y/n"

  if [ "${IPILE_ASSUME_YES:-0}" = "1" ]; then
    [ "$default" = "y" ] && return 0 || return 1
  fi

  local answer=""
  while true; do
    read -r -p "$(echo -e "  ${YELLOW}${prompt}${NC} ${DIM}(${hint})${NC} ")" answer
    answer="$(printf '%s' "${answer:-$default}" | tr '[:upper:]' '[:lower:]')"
    case "$answer" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) echo -e "  ${DIM}Answer y or n.${NC}" ;;
    esac
  done
}

# ui_ask_int <prompt> <default> <varname>. Accepts 0 and up.
ui_ask_int() {
  local prompt="$1"
  local default="$2"
  local varname="$3"
  local __ui_value=""

  if [ "${IPILE_ASSUME_YES:-0}" = "1" ]; then
    eval "${varname}=\"\${default}\""
    return 0
  fi

  while true; do
    read -r -p "$(echo -e "  ${YELLOW}${prompt}${NC} ${DIM}[${default}]${NC} ")" __ui_value
    __ui_value="${__ui_value:-$default}"
    case "$__ui_value" in
      ''|*[!0-9]*) echo -e "  ${DIM}Enter 0 or a positive whole number.${NC}" ;;
      *) break ;;
    esac
  done
  eval "${varname}=\"\${__ui_value}\""
}

# ui_menu <varname> <label...>. Writes the 1-based index of the choice.
ui_menu() {
  local varname="$1"
  shift
  local count=$#
  local i=1
  local label
  local __ui_choice=""

  # A label starting with '!' is a way out rather than a way on. It is
  # drawn in red, number included, so the option that abandons the run
  # never looks like the option that continues it.
  for label in "$@"; do
    case "$label" in
      '!'*) echo -e "  ${RED}[${i}]  ${label#\!}${NC}" ;;
      *)    echo -e "  ${YELLOW}[${i}]${NC}  ${label}" ;;
    esac
    i=$((i + 1))
  done
  echo ""

  if [ "${IPILE_ASSUME_YES:-0}" = "1" ]; then
    eval "${varname}=1"
    return 0
  fi

  while true; do
    read -r -p "$(echo -e "  ${DIM}Choose [1-${count}]:${NC} ")" __ui_choice
    case "$__ui_choice" in
      ''|*[!0-9]*) ;;
      *) if [ "$__ui_choice" -ge 1 ] && [ "$__ui_choice" -le "$count" ]; then break; fi ;;
    esac
    echo -e "  ${DIM}Enter a number between 1 and ${count}.${NC}"
  done
  eval "${varname}=\"\${__ui_choice}\""
}

# ui_type_word <word> <prompt>. Blocks until the exact word is typed.
# Used for "I have registered the key on GitHub" gates.
ui_type_word() {
  local word="$1"
  local prompt="$2"
  [ "${IPILE_ASSUME_YES:-0}" = "1" ] && return 0
  local input=""
  while true; do
    read -r -p "$(echo -e "  ${YELLOW}${prompt}${NC} ")" input
    input="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"
    [ "$input" = "$word" ] && break
    echo -e "  ${DIM}Type the word ${word} and press Enter.${NC}"
  done
  echo ""
}
