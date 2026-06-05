# Interactive helpers that bind to /dev/tty rather than stdin.
# This is what makes `curl ... | sudo bash` work — the script's stdin is the
# pipe, but the user's terminal is still attached at /dev/tty.

tty_read() {
  local prompt="${1:?missing prompt}"
  local answer=""

  if [[ ! -r /dev/tty ]]; then
    return 2
  fi

  printf '%s' "$prompt" > /dev/tty

  if ! IFS= read -r answer < /dev/tty; then
    return 1
  fi

  answer="$(trim "$answer")"
  printf '%s' "$answer"
}

tty_read_secret() {
  local prompt="${1:?missing prompt}"
  local answer=""

  if [[ ! -r /dev/tty ]]; then
    return 2
  fi

  printf '%s' "$prompt" > /dev/tty
  stty -echo < /dev/tty
  if ! IFS= read -r answer < /dev/tty; then
    stty echo < /dev/tty
    return 1
  fi
  stty echo < /dev/tty
  printf '\n' > /dev/tty

  answer="$(trim "$answer")"
  printf '%s' "$answer"
}

confirm() {
  local prompt="${1:?missing prompt}"
  local default="${2:-n}"
  local suffix=""
  local answer=""

  if [[ "$YES" == "true" ]]; then
    ok "auto-confirmed: $prompt"
    return 0
  fi

  case "$default" in
    y|Y) suffix=" [Y/n] " ;;
    *) suffix=" [y/N] " ;;
  esac

  while true; do
    if ! answer="$(tty_read "${prompt}${suffix}")"; then
      die "interactive confirmation requires a TTY; rerun with --yes"
      return 1
    fi

    if [[ -z "$answer" ]]; then
      answer="$default"
    fi

    case "$answer" in
      y|Y|yes|YES|Yes) return 0 ;;
      n|N|no|NO|No) return 1 ;;
      *) warn "answer yes or no" ;;
    esac
  done
}
