# gitprofile: manually switch git identity for the current shell session
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

  # The alias may be given either way round, github-work or just work.
  local alias_label config
  alias_label=$(echo "$alias" | sed 's/^[a-z0-9-]*-//')
  config="$HOME/.gitconfig-${alias_label}"
  [ -f "$config" ] || config="$HOME/.gitconfig-${alias}"

  if [ ! -f "$config" ]; then
    echo "Unknown profile: $alias"
    echo "Run 'gitprofile' to list available profiles."
    return 1
  fi

  # Assign before exporting. Exporting a failed substitution succeeds and
  # would silently activate a profile with an empty name, which then
  # authors commits as nobody.
  local p_name p_email
  p_name=$(git config -f "$config" user.name) || p_name=""
  p_email=$(git config -f "$config" user.email) || p_email=""

  if [ -z "$p_name" ] || [ -z "$p_email" ]; then
    echo "Profile $alias has no name or email set in $config"
    return 1
  fi

  export GIT_AUTHOR_NAME="$p_name"
  export GIT_AUTHOR_EMAIL="$p_email"
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
  export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
  printf '\n  \033[38;2;1;102;48m✓\033[0m  Git profile active: %s <%s>\n\n' "$GIT_AUTHOR_NAME" "$GIT_AUTHOR_EMAIL"
}
