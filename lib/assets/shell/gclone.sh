# gclone: clone a GitHub repo as a specific identity
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
  local SEL_ALIAS SEL_NAME SEL_HOST REPO_PATH REWRITTEN
  SEL_ALIAS=$(echo "$SELECTED" | cut -d'|' -f1)
  SEL_NAME=$(echo "$SELECTED" | cut -d'|' -f2)
  # Field 4 is the host. Absent on identity files written before hosts
  # were supported, where github.com was the only possibility.
  SEL_HOST=$(echo "$SELECTED" | cut -d'|' -f4)
  [ -z "$SEL_HOST" ] && SEL_HOST="github.com"

  # Rewrite to the SSH alias when the URL points at the chosen profile's
  # own host. Matching on that host rather than on github.com is what
  # lets a GitLab or self hosted profile rewrite too.
  local HOST_RE
  HOST_RE=$(echo "$SEL_HOST" | sed 's|\.|\\.|g')
  if echo "$url" | grep -qE "git@${HOST_RE}:|https://${HOST_RE}/"; then
    REPO_PATH=$(echo "$url" | sed "s|git@${SEL_HOST}:||;s|https://${SEL_HOST}/||")
    [[ "$REPO_PATH" != *.git ]] && REPO_PATH="${REPO_PATH}.git"
    REWRITTEN="${SEL_ALIAS}:${REPO_PATH}"
  else
    echo "  URL is not on ${SEL_HOST}, cloning as-is. Identity will be set on first commit."
    REWRITTEN="$url"
  fi

  echo ""
  printf '  \033[38;2;1;102;48m✓\033[0m  Cloning as: \033[1m%s\033[0m \033[2m(%s)\033[0m\n' "$SEL_NAME" "$SEL_ALIAS"
  echo "  URL: $REWRITTEN"
  echo ""

  git clone "$REWRITTEN" "${@:2}"
}
