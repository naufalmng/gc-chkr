# Auto-traceroute on probe failure. When a check fails we fire a single
# traceroute against the affected host, summarize the path into a record()
# line, and append the raw output to a per-probe rolling log file.
#
# Backoff: only on first failure (last state != "fail"). When the probe
# recovers, state resets to "pass" so the next failure fires a fresh trace.
# This keeps timer-mode noise low — a 1-hour outage = 1 traceroute, not 12.
#
# Tool detection: traceroute > tracepath. traceroute is the primary because
# its output is richer (hop-per-line with rtt) and widely available via
# `apt install traceroute`. tracepath is a fallback because it's part of
# iputils-tracepath which is already present on many Debian/Ubuntu hosts
# (and runs unprivileged via UDP). Both are skipped cleanly if absent —
# we never apt install at runtime (preserves the zero-deps contract).

# Cache the resolved tool name across one run.
_TRACE_TOOL_CACHE=""

# Detect which traceroute-family tool is available. Honours
# GC_HC_TRACE_TOOL if it pins a specific binary; "auto" probes in order.
trace_detect_tool() {
  if [[ -n "$_TRACE_TOOL_CACHE" ]]; then
    printf '%s' "$_TRACE_TOOL_CACHE"
    return 0
  fi

  local pin="${GC_HC_TRACE_TOOL:-auto}"
  local candidate=""

  case "$pin" in
    traceroute|tracepath)
      if command -v "$pin" > /dev/null 2>&1; then
        _TRACE_TOOL_CACHE="$pin"
        printf '%s' "$pin"
        return 0
      fi
      return 1
      ;;
    auto|"")
      for candidate in traceroute tracepath; do
        if command -v "$candidate" > /dev/null 2>&1; then
          _TRACE_TOOL_CACHE="$candidate"
          printf '%s' "$candidate"
          return 0
        fi
      done
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# Run the resolved tool against $host, bounded by max-hops + per-hop timeout.
# Echoes raw multi-line output. Caller is responsible for both parsing the
# summary and persisting the raw output to the rolling log.
trace_run() {
  local host="${1:?missing host}"
  local tool=""
  local max="${GC_HC_TRACE_MAX_HOPS:-15}"
  local hop_to="${GC_HC_TRACE_TIMEOUT:-2}"

  if ! tool="$(trace_detect_tool)"; then
    return 1
  fi

  case "$tool" in
    traceroute)
      # traceroute: -n no DNS, -q 1 single probe per hop, -w per-hop wait,
      # -m max ttl. Default UDP (no root needed).
      traceroute -n -q 1 -w "$hop_to" -m "$max" "$host" 2>&1
      ;;
    tracepath)
      # tracepath: -m max_hops, no per-hop timeout flag (compiled-in default
      # is reasonable). Output format:
      #   1?: [LOCALHOST]                                         pmtu 1500
      #   1:  gw.local                                          0.503ms
      #   2:  isp.example.net                                   5.123ms
      tracepath -n -m "$max" "$host" 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

# Pure-function summarizer. Reduces multi-line traceroute output to a
# single-line "hops=N last=X rtt=Yms" string suitable for the JSON record.
# Tolerates traceroute / tracepath formats and all-timeout output.
trace_summarize() {
  local raw="${1-}"
  local hops=0
  local last_host=""
  local last_rtt=""
  local line=""
  local first_field=""

  if [[ -z "$raw" ]]; then
    printf 'hops=0\n'
    return 0
  fi

  # We walk lines and extract the highest-numbered hop's host + rtt.
  # Both supported tools print a leading hop number, so we can normalize
  # by stripping the leading "  N  " or "N:" prefix.
  while IFS= read -r line; do
    # Skip blank, header, and tracepath pmtu/resume rows (they have ?: not :).
    [[ -z "$line" ]] && continue
    [[ "$line" =~ pmtu ]] && continue
    [[ "$line" =~ ^traceroute ]] && continue   # traceroute banner

    first_field="${line#"${line%%[![:space:]]*}"}"   # strip leading whitespace
    first_field="${first_field%%[!0-9]*}"
    [[ -z "$first_field" ]] && continue
    hops="$first_field"

    # Grab host + first rtt-looking token. Both tracepath and traceroute
    # print "<host> <rtt>ms" or "<host> <ms>ms".
    if [[ "$line" =~ [[:space:]]([^[:space:]*]+)[[:space:]]+([0-9]+\.?[0-9]*)\ ?ms ]]; then
      last_host="${BASH_REMATCH[1]}"
      last_rtt="${BASH_REMATCH[2]}ms"
    elif [[ "$line" =~ \* ]]; then
      last_host="*"
      last_rtt="timeout"
    fi
  done <<< "$raw"

  if [[ -z "$last_host" ]]; then
    printf 'hops=%s\n' "$hops"
    return 0
  fi

  printf 'hops=%s last=%s rtt=%s\n' "$hops" "$last_host" "$last_rtt"
}

# Per-probe state file (used to suppress repeats within sustained outages).
trace_state_path() {
  local probe="${1:?missing probe}"
  printf '%s/trace/%s.last' "$STATE_DIR" "$probe"
}

trace_log_path() {
  local probe="${1:?missing probe}"
  printf '%s/trace/%s.log' "$LOG_DIR" "$probe"
}

trace_state_get() {
  local probe="${1:?missing probe}"
  local path
  path="$(trace_state_path "$probe")"

  if [[ -s "$path" ]]; then
    trim "$(cat "$path" 2>/dev/null || true)"
  else
    printf ''
  fi
}

trace_state_set() {
  local probe="${1:?missing probe}"
  local status="${2:?missing status}"
  local path dir
  path="$(trace_state_path "$probe")"
  dir="$(dirname "$path")"

  # mkdir is the reliable creator across Linux + MSYS git-bash. The mode is
  # best-effort: install -d -m fails on Windows because chmod returns EPERM,
  # which would short-circuit the write. Splitting the steps keeps the file
  # write reliable while still enforcing 0750 on real targets.
  mkdir -p "$dir" 2>/dev/null || return 0
  chmod 0750 "$dir" 2>/dev/null || true
  printf '%s\n' "$status" > "$path" 2>/dev/null || true
}

# Write a timestamped block to the rolling per-probe log, then truncate
# to the last N entries. Entries are separated by a "===" delimiter line
# so tail-rotation can split safely.
trace_log_write() {
  local probe="${1:?missing probe}"
  local raw="${2-}"
  local keep="${GC_HC_TRACE_LOG_KEEP:-50}"
  local path stamp tmp dir
  path="$(trace_log_path "$probe")"
  dir="$(dirname "$path")"
  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  mkdir -p "$dir" 2>/dev/null || return 0
  chmod 0750 "$dir" 2>/dev/null || true
  {
    printf '=== %s ===\n' "$stamp"
    printf '%s\n' "$raw"
  } >> "$path" 2>/dev/null || return 0

  log_time_rotate "$path" "${GC_HC_TRACE_LOG_RETENTION:-24h}" trace
  log_tail_rotate "$path" "$keep" '^=== '

  chmod 0640 "$path" 2>/dev/null || true
}

# Hook called from runcheck after a probe fails. Honours GC_HC_TRACE
# mode and the per-probe state-backed backoff.
trace_on_failure() {
  local probe="${1:?missing probe}"
  local host="${2:?missing host}"
  local mode="${GC_HC_TRACE:-auto}"
  local prev tool raw summary

  [[ "$mode" == "never" ]] && return 0

  if [[ "$mode" != "always" ]]; then
    prev="$(trace_state_get "$probe")"
    if [[ "$prev" == "fail" ]]; then
      return 0
    fi
  fi

  if ! tool="$(trace_detect_tool)"; then
    record "${probe}.trace" "skip" "no_trace_tool" "$host" ""
    return 0
  fi

  if ! raw="$(trace_run "$host")"; then
    record "${probe}.trace" "skip" "trace_failed" "$host" ""
    trace_state_set "$probe" "fail"
    return 0
  fi

  summary="$(trace_summarize "$raw")"
  trace_log_write "$probe" "$raw"
  trace_state_set "$probe" "fail"

  record "${probe}.trace" "info" "captured_via_${tool}" "$host" "$summary log=$(trace_log_path "$probe")"
}

# Hook called from runcheck after a probe passes. Re-arms state so the
# next failure fires a fresh trace.
trace_on_success() {
  local probe="${1:?missing probe}"
  local prev

  prev="$(trace_state_get "$probe")"
  if [[ "$prev" == "fail" ]]; then
    trace_state_set "$probe" "pass"
  fi
}

# Discover any probes currently in fail-state. Used by show_status.
# Echoes "<probe> <log_path>" pairs, one per line.
trace_pending_failures() {
  local dir="${STATE_DIR}/trace"
  local f probe

  [[ -d "$dir" ]] || return 0

  for f in "$dir"/*.last; do
    [[ -f "$f" ]] || continue
    if [[ "$(trim "$(cat "$f" 2>/dev/null || true)")" == "fail" ]]; then
      probe="$(basename "$f" .last)"
      printf '%s %s\n' "$probe" "$(trace_log_path "$probe")"
    fi
  done
}
