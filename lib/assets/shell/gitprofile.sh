# gitprofile: switch git identity.
#
# Usage:
#   gitprofile                 list every profile
#   gitprofile <alias>         switch for this shell session only
#   gitprofile use <alias>     set this repository's identity, permanently
#
# The difference matters. The bare form exports GIT_AUTHOR_* into the
# current shell, so it lasts until you close the terminal and reaches any
# repository you touch from it. 'use' writes to this repository's own
# config, so it survives new shells and applies to nothing else. When the
# identity a repo was given is simply wrong, 'use' is the one you want.
gitprofile() {
  local alias="${1:-}"
  local IDENTITIES_FILE="$HOME/.gitidentities"

  if [ "$alias" = "use" ]; then
    local want="${2:-}"
    if [ -z "$want" ]; then
      echo "Usage: gitprofile use <alias>"
      return 1
    fi
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
      echo "Not a git repository. Use 'gitprofile ${want}' for a shell-wide switch."
      return 1
    fi

    local line u_name u_email u_key
    line=$(_ipile_identity_line "$want")
    # Accept the short form too, so 'use work' finds 'github-work'.
    [ -z "$line" ] && line=$(grep -- "-${want}|" "$IDENTITIES_FILE" 2>/dev/null | head -1)
    if [ -z "$line" ]; then
      echo "Unknown profile: ${want}"
      echo "Run 'gitprofile' to list them."
      return 1
    fi

    want=$(_ipile_field "$line" 1)
    u_name=$(_ipile_field "$line" 2)
    u_email=$(_ipile_field "$line" 3)
    git config --local user.name "$u_name"
    git config --local user.email "$u_email"

    u_key="$HOME/.ssh/id_ed25519_$(printf '%s' "$want" | sed 's/^[a-z0-9]*-//').pub"
    if [ -f "$u_key" ]; then
      git config --local gpg.format ssh
      git config --local user.signingkey "$u_key"
      git config --local commit.gpgsign true
      git config --local tag.gpgsign true
    fi

    printf '\n  \033[38;2;1;102;48m✓\033[0m  This repo now commits as: \033[1m%s\033[0m <%s>\n' "$u_name" "$u_email"
    printf '     \033[2mAlready-made commits keep the author they were written with.\033[0m\n\n'
    return 0
  fi

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
