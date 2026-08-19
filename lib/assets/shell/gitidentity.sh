# Shared helpers for gclone, gremote and gitprofile.
#
# Installed by ipile. These are the one place that knows the shape of
# ~/.gitidentities, so a change to that format is a change to this file
# and nothing else.
#
# Deliberately array free. These are sourced into zsh as well as bash,
# and the two disagree about whether an index starts at 0 or 1.

# _ipile_identities_file. The identity map, or a non-zero exit if there
# is none worth reading.
_ipile_identities_file() {
  local f="$HOME/.gitidentities"
  [ -s "$f" ] || return 1
  printf '%s' "$f"
}

# _ipile_identity_line <alias>. The full record for one alias.
_ipile_identity_line() {
  local f
  f=$(_ipile_identities_file) || return 1
  grep "^${1}|" "$f" 2>/dev/null | head -1
}

# _ipile_field <line> <n>. Field n of a pipe separated record. Field 4 is
# the host and is absent in files written before hosts were supported,
# where github.com was the only possibility.
_ipile_field() {
  local v
  v=$(printf '%s' "$1" | cut -d'|' -f"$2")
  [ "$2" = "4" ] && [ -z "$v" ] && v="github.com"
  printf '%s' "$v"
}

# _ipile_pick_identity [prompt]. Prints the numbered list, reads a
# choice, and leaves the chosen record in IPILE_IDENTITY.
_ipile_pick_identity() {
  local prompt="${1:-Which identity?}"
  local f count n line alias name email choice
  IPILE_IDENTITY=""

  f=$(_ipile_identities_file) || {
    echo "  No identities yet. Run: ipile git-accounts"
    return 1
  }

  count=$(grep -c . "$f")
  printf '\n  %s\n\n' "$prompt"
  n=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=$((n + 1))
    alias=$(_ipile_field "$line" 1)
    name=$(_ipile_field "$line" 2)
    email=$(_ipile_field "$line" 3)
    printf '  [%d]  %s <%s>  \033[2m(%s)\033[0m\n' "$n" "$name" "$email" "$alias"
  done <"$f"
  printf '\n'

  # The prompt is printed rather than passed to read, because read's own
  # prompt flag is spelled differently in bash and zsh and this file is
  # sourced into both. Trying one then the other risks the first attempt
  # swallowing the answer.
  while true; do
    printf '  Choose [1-%d]: ' "$count"
    read -r choice || return 1
    case "$choice" in
      '' | *[!0-9]*) ;;
      *) [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ] && break ;;
    esac
    printf '  Enter a number between 1 and %d.\n' "$count"
  done

  IPILE_IDENTITY=$(grep -n . "$f" | sed -n "${choice}p" | cut -d: -f2-)
  [ -n "$IPILE_IDENTITY" ]
}

# _ipile_alias_url <alias> <host> <url>. Rewrites a clone URL to the SSH
# host alias so that remote authenticates with that profile's key. A URL
# on a different host is returned untouched, because rewriting it would
# point at a key the other host has never seen.
_ipile_alias_url() {
  local alias="$1" host="$2" url="$3" host_re path
  host_re=$(printf '%s' "$host" | sed 's|\.|\\.|g')
  if printf '%s' "$url" | grep -qE "^(git@${host_re}:|https://${host_re}/)"; then
    path=$(printf '%s' "$url" | sed "s|git@${host}:||;s|https://${host}/||")
    case "$path" in *.git) ;; *) path="${path}.git" ;; esac
    printf '%s:%s' "$alias" "$path"
  else
    printf '%s' "$url"
  fi
}
