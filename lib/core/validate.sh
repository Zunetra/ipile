#!/usr/bin/env bash
# Input validation. Pure predicates and normalisers, no output, no prompts.
# Sourced, never executed. Kept bash 3.2 safe: no associative arrays,
# no ${VAR,,}, no mapfile, no namerefs.
#
# Nothing here writes to the terminal or reads from it. Every function is
# a predicate returning 0/1, or a normaliser printing one line on stdout.
# The interactive wrappers that prompt and re-prompt live in ui.sh, so
# these stay callable from doctor.sh and from tests with no tty attached.

# === Field predicates

# valid_email <string>. Shape only, any domain. A domain allowlist would
# reject the work address that is the whole reason this tool exists.
valid_email() {
  case "$1" in
    *[[:space:]]* | *'|'*) return 1 ;;
  esac
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$'
}

# valid_host <string>. Shape only: no scheme, no path, no port, no
# leading or trailing dot.
#
# A single-label host passes deliberately. Requiring a dot would reject
# 'gitbub' here, which sounds right but is worse in practice: the user
# gets "enter a hostname" when what they actually need is "did you mean
# github.com?". Shape and plausibility are separate questions, so this
# answers only the first and leaves the typo to forge_suggest. A real
# single-label host on an internal network stays reachable too.
valid_host() {
  case "$1" in
    *[[:space:]]* | */* | *:* | *'|'* | .* | *.) return 1 ;;
  esac
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$'
}

# valid_gh_username <string>. GitHub's own rule: alphanumeric plus single
# internal hyphens, 39 characters at most.
valid_gh_username() {
  [ ${#1} -le 39 ] || return 1
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9](-?[A-Za-z0-9])*$'
}

# valid_alias <string>. Stricter than it looks because the alias becomes a
# filename (~/.gitconfig-<alias>), an SSH Host token, and a grep pattern
# (identity.sh greps '^<alias>|'). A regex metacharacter here breaks
# lookup silently rather than loudly.
valid_alias() {
  printf '%s' "$1" | grep -Eq '^[a-z0-9][a-z0-9._-]*$'
}

# valid_freetext <string>. For names, which cannot be pattern-matched in
# any useful way. Guards the one character that matters: '|' is the field
# delimiter in ~/.ipile/identities, so a name containing it corrupts the
# map and every ident_field lookup that follows.
valid_freetext() {
  [ -n "$1" ] || return 1
  case "$1" in
    *'|'*) return 1 ;;
  esac
  printf '%s' "$1" | grep -q '[^[:space:]]' || return 1
  printf '%s' "$1" | grep -q '[[:cntrl:]]' && return 1
  return 0
}

# valid_dir <string>. Exists and is a directory, once a leading ~ is
# expanded. The projects-root prompt expects the output of `pwd`, pasted
# straight from a terminal already sitting in the folder, but a leading
# ~ is accepted too since that is the other thing people type by hand.
valid_dir() {
  local p="$1"
  case "$p" in
    '~') p="$HOME" ;;
    '~/'*) p="${HOME}/${p#\~/}" ;;
  esac
  [ -d "$p" ]
}

# === Normalisers

# gh_normalize_username <string>. The prompt asks for a username, but a
# profile URL is what sits on the clipboard, so accept both and reduce to
# the username rather than rejecting. Rejecting URLs would be the wrong
# trade: a bare username is what most people type, and a hard "must start
# with https://github.com/" rule would turn the common case into an error.
#
#   musathedev                          -> musathedev
#   github.com/musathedev               -> musathedev
#   www.github.com/musathedev           -> musathedev
#   https://github.com/musathedev       -> musathedev
#   https://www.github.com/musathedev/  -> musathedev
#   git@github.com:musathedev           -> musathedev
gh_normalize_username() {
  local v="$1"

  v="${v#git+ssh://}"
  v="${v#ssh://}"
  v="${v#https://}"
  v="${v#http://}"
  v="${v#git@}"
  v="${v#www.}"

  # scp-style remote, git@host:user
  case "$v" in
    *:*) v="${v#*:}" ;;
  esac

  # host-prefixed path, host/user, after the scheme is already gone
  case "$v" in
    *.*/*) v="${v#*/}" ;;
  esac

  v="${v%/}"
  # a repo path rather than a profile, user/repo
  v="${v%%/*}"
  v="${v%.git}"

  printf '%s' "$v"
}

# === Forge recognition

# The forges worth recognising by name. Space separated because bash 3.2
# has no associative arrays and this list is short enough that a linear
# scan is free.
IPILE_KNOWN_FORGES="github.com gitlab.com bitbucket.org codeberg.org"

# forge_is_known <host>
forge_is_known() {
  local host="$1" known
  for known in $IPILE_KNOWN_FORGES; do
    [ "$host" = "$known" ] && return 0
  done
  return 1
}

# str_distance <a> <b>. Levenshtein, iterative with two rows. Bash 3.2
# safe: indexed arrays only. Called once against four short candidates,
# so the cost of doing this in pure shell never shows up.
str_distance() {
  local a="$1" b="$2"
  local la=${#a} lb=${#b}
  local i j cost del ins sub
  local prev cur

  [ "$la" -eq 0 ] && {
    printf '%s' "$lb"
    return 0
  }
  [ "$lb" -eq 0 ] && {
    printf '%s' "$la"
    return 0
  }

  local -a prev_row cur_row
  for j in $(seq 0 "$lb"); do prev_row[j]=$j; done

  for i in $(seq 1 "$la"); do
    cur_row[0]=$i
    for j in $(seq 1 "$lb"); do
      cost=1
      [ "${a:i-1:1}" = "${b:j-1:1}" ] && cost=0
      del=$((prev_row[j] + 1))
      ins=$((cur_row[j - 1] + 1))
      sub=$((prev_row[j - 1] + cost))
      cur=$del
      [ "$ins" -lt "$cur" ] && cur=$ins
      [ "$sub" -lt "$cur" ] && cur=$sub
      cur_row[j]=$cur
    done
    for j in $(seq 0 "$lb"); do prev_row[j]=${cur_row[j]}; done
  done

  printf '%s' "${prev_row[lb]}"
}

# forge_suggest <host>. Prints the nearest known forge, or nothing.
#
# The comparison is on the label before the first dot, not the whole
# host. 'gitbub' against 'github.com' is distance 5, which no sane
# threshold catches, while 'gitbub' against 'github' is distance 1. The
# TLD is noise for this purpose.
forge_suggest() {
  local host="$1"
  local label="${host%%.*}"
  local known known_label d
  local best="" best_d=3

  for known in $IPILE_KNOWN_FORGES; do
    known_label="${known%%.*}"
    d="$(str_distance "$label" "$known_label")"
    if [ "$d" -lt "$best_d" ]; then
      best_d="$d"
      best="$known"
    fi
  done

  [ -n "$best" ] && printf '%s' "$best"
}

# === Versions

# version_newer <candidate> <current>. 0 when candidate is a strictly newer
# vMAJOR.MINOR.PATCH than current, compared numerically so v1.0.10 beats
# v1.0.9. A candidate that is not plain numeric is never newer, so a
# garbled version.txt cannot trigger an update. A current that is not
# numeric ('dev', 'unknown') is always older, so a broken install can
# still be offered the release.
version_newer() {
  local cand="${1#v}" curr="${2#v}" i c k
  case "$cand" in '' | *[!0-9.]*) return 1 ;; esac
  case "$curr" in '' | *[!0-9.]*) return 0 ;; esac

  for i in 1 2 3; do
    c="$(printf '%s' "$cand" | cut -d. -f"$i")"
    k="$(printf '%s' "$curr" | cut -d. -f"$i")"
    c="${c:-0}"
    k="${k:-0}"
    [ "$c" -gt "$k" ] && return 0
    [ "$c" -lt "$k" ] && return 1
  done
  return 1
}
