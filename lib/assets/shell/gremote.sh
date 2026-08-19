# gremote: add a git remote that authenticates as a chosen identity.
#
# Usage:
#   gremote add <name> <url>   add a remote, choosing which identity pushes it
#   gremote list               every remote, and the identity behind it
#   gremote                    same as list
#
# Why this exists: a repository can have several remotes on several
# accounts, and the account is selected by the SSH host alias baked into
# each remote's URL. This does that rewriting for you and records which
# profile a remote belongs to, so pre-push can tell you when the commits
# you are about to send were authored by somebody else.
#
# What it does not do: change who authors a commit. Git stamps the author
# when you commit, not when you push, and a repository has one identity at
# a time. Use 'gitprofile use <alias>' to change that.
gremote() {
  local cmd="${1:-list}"

  case "$cmd" in
    add)
      local name="${2:-}" url="${3:-}"
      if [ -z "$name" ] || [ -z "$url" ]; then
        echo "Usage: gremote add <name> <url>"
        return 1
      fi
      if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "Not a git repository."
        return 1
      fi
      if git remote get-url "$name" >/dev/null 2>&1; then
        echo "Remote '${name}' already exists: $(git remote get-url "$name")"
        return 1
      fi

      _ipile_pick_identity "Which identity should push to '${name}'?" || return 1

      local alias host rewritten
      alias=$(_ipile_field "$IPILE_IDENTITY" 1)
      host=$(_ipile_field "$IPILE_IDENTITY" 4)
      rewritten=$(_ipile_alias_url "$alias" "$host" "$url")

      if [ "$rewritten" = "$url" ]; then
        printf '\n  \033[1;33m!\033[0m  %s is not on %s, so the URL is unchanged.\n' "$url" "$host"
        printf '     That remote will use your default SSH key, not %s.\n' "$alias"
      fi

      git remote add "$name" "$rewritten" || return 1
      git config --local "remote.${name}.ipileidentity" "$alias"

      printf '\n  \033[38;2;1;102;48m✓\033[0m  %s  \033[2m->\033[0m  %s\n' "$name" "$rewritten"
      printf '     Pushes as: %s <%s>\n\n' \
        "$(_ipile_field "$IPILE_IDENTITY" 2)" "$(_ipile_field "$IPILE_IDENTITY" 3)"

      # Said once, and only when it can actually bite: a second identity
      # in a repo whose commits are authored by the first.
      local committing
      committing=$(git config --local user.email 2>/dev/null || true)
      if [ -n "$committing" ] && [ "$committing" != "$(_ipile_field "$IPILE_IDENTITY" 3)" ]; then
        printf '  \033[2mCommits here are still authored as %s.\033[0m\n' "$committing"
        printf '  \033[2mGit sets the author at commit time, not at push time.\033[0m\n'
        printf '  \033[2mChange it with: gitprofile use %s\033[0m\n\n' "$alias"
      fi
      ;;

    list | ls)
      if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "Not a git repository."
        return 1
      fi
      local r u a line
      printf '\n  \033[1mRemotes\033[0m\n\n'
      for r in $(git remote); do
        u=$(git remote get-url "$r")
        a=$(git config --local --get "remote.${r}.ipileidentity" 2>/dev/null || true)
        # Not added by gremote? The alias is still recoverable from the
        # URL, which is where it actually takes effect.
        [ -z "$a" ] && a=$(printf '%s' "$u" | sed -n 's/^\(git@\)\{0,1\}\([a-z0-9]*-[^:]*\):.*/\2/p')
        if [ -n "$a" ]; then
          line=$(_ipile_identity_line "$a")
          if [ -n "$line" ]; then
            printf '  %-12s %s\n' "$r" "$u"
            printf '  %-12s \033[2m%s <%s>\033[0m\n\n' "" \
              "$(_ipile_field "$line" 2)" "$(_ipile_field "$line" 3)"
            continue
          fi
        fi
        printf '  %-12s %s\n' "$r" "$u"
        printf '  %-12s \033[2mno ipile identity, uses your default SSH key\033[0m\n\n' ""
      done
      printf '  \033[2mCommitting as: %s <%s>\033[0m\n\n' \
        "$(git config user.name 2>/dev/null)" "$(git config user.email 2>/dev/null)"
      ;;

    *)
      echo "Usage: gremote add <name> <url> | gremote list"
      return 1
      ;;
  esac
}
