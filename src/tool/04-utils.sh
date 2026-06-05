# Generic shell utilities: privilege check, command presence, string helpers,
# pure-bash JSON string escaping (no jq dependency), and secret masking.

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "run as root"
    return 1
  fi
}

need_cmd() {
  local missing=()
  local cmd=""

  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    die "missing command(s): ${missing[*]}"
    return 1
  fi
}

trim() {
  local input="${1:-}"
  input="${input//$'\r'/}"
  input="${input#"${input%%[![:space:]]*}"}"
  input="${input%"${input##*[![:space:]]}"}"
  printf '%s' "$input"
}

json_escape() {
  local input="${1:-}"
  input="${input//\\/\\\\}"
  input="${input//\"/\\\"}"
  input="${input//$'\n'/\\n}"
  input="${input//$'\r'/\\r}"
  input="${input//$'\t'/\\t}"
  printf '%s' "$input"
}

# Escape a value for safe inclusion inside single-quoted shell env files.
quote_env() {
  local input="${1:-}"
  printf '%s' "$input" | sed "s/'/'\\\\''/g"
}

# Mask credentials for logs. Short values are fully obscured to avoid leaking
# entropy on prefix-only secrets.
mask() {
  local value="${1:-}"
  local len="${#value}"

  if [[ -z "$value" ]]; then
    printf '<empty>'
    return 0
  fi

  if (( len < 14 )); then
    printf '********'
    return 0
  fi

  printf '%s...%s' "${value:0:6}" "${value: -4}"
}

retention_seconds() {
  local value="${1:-0}"
  local number unit

  [[ "$value" != "0" ]] || { printf '0'; return 0; }
  [[ "$value" =~ ^([0-9]+)([smhd])$ ]] || return 1

  number="${BASH_REMATCH[1]}"
  unit="${BASH_REMATCH[2]}"

  case "$unit" in
    s) printf '%s' "$number" ;;
    m) printf '%s' "$((number * 60))" ;;
    h) printf '%s' "$((number * 3600))" ;;
    d) printf '%s' "$((number * 86400))" ;;
  esac
}

log_time_rotate() {
  local path="${1:?missing path}"
  local retention="${2:-0}"
  local mode="${3:-jsonl}"
  local seconds cutoff tmp

  [[ "$retention" != "0" ]] || return 0
  [[ -s "$path" ]] || return 0
  seconds="$(retention_seconds "$retention" 2>/dev/null || true)"
  [[ "$seconds" =~ ^[0-9]+$ && "$seconds" -gt 0 ]] || return 0
  cutoff="$(date -u -d "-${seconds} seconds" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  [[ -n "$cutoff" ]] || return 0

  tmp="${path}.rot"
  if [[ "$mode" == "trace" ]]; then
    awk -v cutoff="$cutoff" '
      /^=== / {
        stamp=$2
        keep=(stamp >= cutoff)
      }
      keep { print }
    ' "$path" > "$tmp" 2>/dev/null && mv "$tmp" "$path" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    return 0
  fi

  awk -v cutoff="$cutoff" '
    {
      stamp=$0
      sub(/^.*"started":"/, "", stamp)
      sub(/".*$/, "", stamp)
      if (stamp >= cutoff) print
    }
  ' "$path" > "$tmp" 2>/dev/null && mv "$tmp" "$path" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

log_tail_rotate() {
  local path="${1:?missing path}"
  local keep="${2:-0}"
  local marker="${3:-^}"
  local tmp

  (( keep > 0 )) || return 0
  [[ -s "$path" ]] || return 0

  tmp="${path}.rot"
  awk -v keep="$keep" -v marker="$marker" '
    $0 ~ marker { blocks++; idx[blocks] = NR }
    { lines[NR] = $0; total = NR }
    END {
      if (blocks <= keep) {
        for (i = 1; i <= total; i++) print lines[i]
        exit
      }
      start = idx[blocks - keep + 1]
      for (i = start; i <= total; i++) print lines[i]
    }
  ' "$path" > "$tmp" 2>/dev/null && mv "$tmp" "$path" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}
