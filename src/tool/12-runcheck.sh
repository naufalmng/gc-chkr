# Healthcheck orchestrator. Runs every enabled probe, aggregates results into
# one JSON document, persists it, and exits with a code that reflects the
# overall verdict so systemd/cron alerting can trigger on it.

run_check() {
  local started=""
  local finished=""
  local host=""
  local overall="pass"
  local joined=""
  local item=""
  local result=""

  LAST_STEP="healthcheck"
  need_cmd curl awk sed grep date hostname getent

  if ! load_config; then
    die "config missing, run: gc-hc config"
    return 1
  fi

  validate_config
  valid_timeout "$GC_HC_TIMEOUT"

  CHECKS=()
  PASS=0
  WARN=0
  FAIL=0
  SKIP=0

  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  host="$(hostname -f 2>/dev/null || hostname)"

  if [[ "$GC_HC_DNS" == "true" ]]; then
    if check_dns "prom" "$GCLOUD_HOSTED_METRICS_URL"; then
      trace_on_success "prom.dns"
    else
      trace_on_failure "prom.dns" "$(host_from_url "$GCLOUD_HOSTED_METRICS_URL" 2>/dev/null || printf '%s' "$GCLOUD_HOSTED_METRICS_URL")"
    fi

    if check_dns "loki" "$GCLOUD_HOSTED_LOGS_URL"; then
      trace_on_success "loki.dns"
    else
      trace_on_failure "loki.dns" "$(host_from_url "$GCLOUD_HOSTED_LOGS_URL" 2>/dev/null || printf '%s' "$GCLOUD_HOSTED_LOGS_URL")"
    fi

    if [[ -n "${GCLOUD_FM_URL:-}" ]]; then
      if check_dns "fleet" "$GCLOUD_FM_URL"; then
        trace_on_success "fleet.dns"
      else
        trace_on_failure "fleet.dns" "$(host_from_url "$GCLOUD_FM_URL" 2>/dev/null || printf '%s' "$GCLOUD_FM_URL")"
      fi
    fi
  else
    record "dns" "skip" "disabled" "" ""
  fi

  if [[ "$GC_HC_TLS" == "true" ]]; then
    if check_tls "prom" "$GCLOUD_HOSTED_METRICS_URL"; then
      trace_on_success "prom.tls"
    else
      trace_on_failure "prom.tls" "$(host_from_url "$GCLOUD_HOSTED_METRICS_URL" 2>/dev/null || printf '%s' "$GCLOUD_HOSTED_METRICS_URL")"
    fi

    if check_tls "loki" "$GCLOUD_HOSTED_LOGS_URL"; then
      trace_on_success "loki.tls"
    else
      trace_on_failure "loki.tls" "$(host_from_url "$GCLOUD_HOSTED_LOGS_URL" 2>/dev/null || printf '%s' "$GCLOUD_HOSTED_LOGS_URL")"
    fi

    if [[ -n "${GCLOUD_FM_URL:-}" ]]; then
      if check_tls "fleet" "$GCLOUD_FM_URL"; then
        trace_on_success "fleet.tls"
      else
        trace_on_failure "fleet.tls" "$(host_from_url "$GCLOUD_FM_URL" 2>/dev/null || printf '%s' "$GCLOUD_FM_URL")"
      fi
    fi
  else
    record "tls" "skip" "disabled" "" ""
  fi

  if check_prom_push; then
    trace_on_success "prom.push"
  else
    trace_on_failure "prom.push" "$(host_from_url "$GCLOUD_HOSTED_METRICS_URL" 2>/dev/null || printf '%s' "$GCLOUD_HOSTED_METRICS_URL")"
  fi

  if check_prom_query; then
    trace_on_success "prom.query"
  else
    trace_on_failure "prom.query" "$(host_from_url "$GCLOUD_HOSTED_METRICS_URL" 2>/dev/null || printf '%s' "$GCLOUD_HOSTED_METRICS_URL")"
  fi

  if check_loki; then
    trace_on_success "loki.push"
  else
    trace_on_failure "loki.push" "$(host_from_url "$GCLOUD_HOSTED_LOGS_URL" 2>/dev/null || printf '%s' "$GCLOUD_HOSTED_LOGS_URL")"
  fi

  if check_fleet; then
    trace_on_success "fleet.api"
  else
    if [[ -n "${GCLOUD_FM_URL:-}" ]]; then
      trace_on_failure "fleet.api" "$(host_from_url "$GCLOUD_FM_URL" 2>/dev/null || printf '%s' "$GCLOUD_FM_URL")"
    fi
  fi

  # Verdict: any FAIL beats any WARN beats all-PASS.
  if (( FAIL > 0 )); then
    overall="fail"
  elif (( WARN > 0 )); then
    overall="warn"
  fi

  for item in "${CHECKS[@]}"; do
    if [[ -z "$joined" ]]; then
      joined="$item"
    else
      joined="${joined},${item}"
    fi
  done

  finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  result="$(printf '{"tool":"%s","version":"%s","mode":"%s","host":"%s","started":"%s","finished":"%s","overall":"%s","summary":{"pass":%s,"warn":%s,"fail":%s,"skip":%s},"checks":[%s]}\n' \
    "$APP" \
    "$VERSION" \
    "$MODE" \
    "$(json_escape "$host")" \
    "$started" \
    "$finished" \
    "$overall" \
    "$PASS" \
    "$WARN" \
    "$FAIL" \
    "$SKIP" \
    "$joined")"

  install -d -m 0750 "$STATE_DIR" "$LOG_DIR"
  printf '%s' "$result" > "$RESULT_FILE"
  # JSONL: one record per line so tail/grep/jq -c work cleanly. The trailing
  # newline matters — without it `grep` and `wc -l` undercount the last entry.
  printf '%s\n' "$result" >> "$LOG_FILE"
  log_time_rotate "$LOG_FILE" "${GC_HC_LOG_RETENTION:-24h}" jsonl
  log_tail_rotate "$LOG_FILE" "${GC_HC_LOG_KEEP:-100}" '^'
  chmod 0640 "$RESULT_FILE" "$LOG_FILE" 2>/dev/null || true

  notify_mail_from_result "$result" "$overall" "$host"

  # Output mode:
  #   --json or non-TTY (piped/redirected) → raw JSON (machine-readable)
  #   TTY interactive                       → human-readable table
  if [[ "$JSON" == "true" ]] || [[ ! -t 1 ]]; then
    printf '%s' "$result"
  else
    format_result "$RESULT_FILE"
  fi

  case "$overall" in
    pass) return 0 ;;
    warn) return 1 ;;
    fail) return 2 ;;
  esac
}
