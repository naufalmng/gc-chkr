# Configuration: load, validate, prompt, persist, and display.
# Falls back to Grafana Alloy's env files when no gc-hc config exists yet,
# so existing Alloy-instrumented hosts get a smooth onboarding.

source_env() {
  local file="${1:?missing file}"

  if [[ ! -s "$file" ]]; then
    return 1
  fi

  set -a
  # shellcheck disable=SC1090
  . "$file"
  set +a
}

load_config() {
  local file=""

  if [[ -s "$CONFIG_FILE" ]]; then
    source_env "$CONFIG_FILE"
    return 0
  fi

  for file in "${ALLOY_ENV_FILES[@]}"; do
    if [[ -s "$file" ]] && source_env "$file"; then
      return 0
    fi
  done

  return 1
}

validate_config() {
  valid_url "GCLOUD_HOSTED_METRICS_URL" "$GCLOUD_HOSTED_METRICS_URL"
  valid_id "GCLOUD_HOSTED_METRICS_ID" "$GCLOUD_HOSTED_METRICS_ID"
  valid_url "GCLOUD_HOSTED_LOGS_URL" "$GCLOUD_HOSTED_LOGS_URL"
  valid_id "GCLOUD_HOSTED_LOGS_ID" "$GCLOUD_HOSTED_LOGS_ID"
  valid_key "$GCLOUD_RW_API_KEY"

  if [[ -n "${GCLOUD_FM_URL:-}" ]]; then
    valid_url "GCLOUD_FM_URL" "$GCLOUD_FM_URL"
  fi
}

prompt_value() {
  local var="${1:?missing var}"
  local label="${2:?missing label}"
  local current="${!var:-}"
  local input=""

  while true; do
    if [[ -n "$current" ]]; then
      if [[ "$var" == "GCLOUD_RW_API_KEY" ]]; then
        input="$(tty_read "${label} [$(mask "$current")]: ")" || return 1
      else
        input="$(tty_read "${label} [${current}]: ")" || return 1
      fi
    else
      input="$(tty_read "${label}: ")" || return 1
    fi

    input="$(trim "$input")"

    if [[ -z "$input" && -n "$current" ]]; then
      input="$current"
    fi

    if [[ -n "$input" ]]; then
      printf -v "$var" '%s' "$input"
      # shellcheck disable=SC2163  # we genuinely want indirect export here
      export "$var"
      return 0
    fi

    warn "value cannot be empty"
  done
}

configure() {
  LAST_STEP="configure"

  if [[ "$MODE" == "system" ]]; then
    need_root
  fi

  printf '\nConfig target: %s\n' "$CONFIG_FILE"
  load_config || true

  prompt_value "GCLOUD_HOSTED_METRICS_URL" "Prometheus remote_write URL"
  prompt_value "GCLOUD_HOSTED_METRICS_ID" "Prometheus username / metrics ID"
  prompt_value "GCLOUD_HOSTED_LOGS_URL" "Loki push URL"
  prompt_value "GCLOUD_HOSTED_LOGS_ID" "Loki username / logs ID"
  prompt_value "GCLOUD_RW_API_KEY" "Grafana Cloud API key"

  if [[ -n "${GCLOUD_FM_URL:-}" ]]; then
    confirm "Keep Fleet URL check?" "y" || GCLOUD_FM_URL=""
  elif confirm "Add Fleet URL check?" "n"; then
    prompt_value "GCLOUD_FM_URL" "Fleet Management URL"
  fi

  # Auto-traceroute knobs are advanced and rarely tuned; gate the prompts
  # behind a single confirm so the typical onboard stays a 5-question flow.
  # Unanswered → keep the in-memory defaults from 01-globals.
  if confirm "Configure auto-traceroute settings? (defaults are sane)" "n"; then
    prompt_value "GC_HC_TRACE"          "Mode (auto / always / never)"
    prompt_value "GC_HC_TRACE_TOOL"     "Tool (auto / traceroute / tracepath)"
    prompt_value "GC_HC_TRACE_TIMEOUT"  "Per-hop timeout (seconds)"
    prompt_value "GC_HC_TRACE_MAX_HOPS" "Abort after N hops"
    prompt_value "GC_HC_TRACE_LOG_KEEP" "Last N entries kept per probe log"
  fi

  validate_config

  install -d -m 0750 "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR"

  if [[ "$MODE" == "system" ]]; then
    chown root:root "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR"
  fi

  # Backup existing config unless --force was passed; cheap insurance against
  # a fat-finger.
  if [[ -e "$CONFIG_FILE" && "$FORCE" != "true" ]]; then
    cp -a "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  fi

  {
    printf "GCLOUD_HOSTED_METRICS_URL='%s'\n" "$(quote_env "$GCLOUD_HOSTED_METRICS_URL")"
    printf "GCLOUD_HOSTED_METRICS_ID='%s'\n"  "$(quote_env "$GCLOUD_HOSTED_METRICS_ID")"
    printf "GCLOUD_HOSTED_LOGS_URL='%s'\n"    "$(quote_env "$GCLOUD_HOSTED_LOGS_URL")"
    printf "GCLOUD_HOSTED_LOGS_ID='%s'\n"     "$(quote_env "$GCLOUD_HOSTED_LOGS_ID")"
    printf "GCLOUD_RW_API_KEY='%s'\n"         "$(quote_env "$GCLOUD_RW_API_KEY")"
    printf "GCLOUD_FM_URL='%s'\n"             "$(quote_env "${GCLOUD_FM_URL:-}")"
    printf "GC_HC_INTERVAL='%s'\n"          "$GC_HC_INTERVAL"
    printf "GC_HC_TIMEOUT='%s'\n"           "$TIMEOUT"
    printf "GC_HC_RETRIES='%s'\n"           "$GC_HC_RETRIES"
    printf "GC_HC_RETRY_DELAY='%s'\n"       "$GC_HC_RETRY_DELAY"
    printf "GC_HC_DNS='%s'\n"               "$GC_HC_DNS"
    printf "GC_HC_TLS='%s'\n"               "$GC_HC_TLS"
    printf "GC_HC_LOKI_WRITE='%s'\n"        "$GC_HC_LOKI_WRITE"
    printf "GC_HC_PROM_QUERY='%s'\n"        "$GC_HC_PROM_QUERY"
    printf "GC_HC_FLEET='%s'\n"             "$GC_HC_FLEET"
    printf "GC_HC_TRACE='%s'\n"          "$GC_HC_TRACE"
    printf "GC_HC_TRACE_TOOL='%s'\n"     "$GC_HC_TRACE_TOOL"
    printf "GC_HC_TRACE_TIMEOUT='%s'\n"  "$GC_HC_TRACE_TIMEOUT"
    printf "GC_HC_TRACE_MAX_HOPS='%s'\n" "$GC_HC_TRACE_MAX_HOPS"
    printf "GC_HC_TRACE_LOG_KEEP='%s'\n" "$GC_HC_TRACE_LOG_KEEP"
    printf "GC_HC_TRACE_LOG_RETENTION='%s'\n" "$GC_HC_TRACE_LOG_RETENTION"
    printf "GC_HC_LOG_KEEP='%s'\n"       "$GC_HC_LOG_KEEP"
    printf "GC_HC_LOG_RETENTION='%s'\n"  "$GC_HC_LOG_RETENTION"
  } > "$CONFIG_FILE"

  chmod 0600 "$CONFIG_FILE"

  if [[ "$MODE" == "system" ]]; then
    chown root:root "$CONFIG_FILE"
  fi

  ok "config saved: $CONFIG_FILE"
}

config_row() {
  local key="${1:?missing key}"
  local value="${2:-<unset>}"
  [[ -n "$value" ]] || value="<unset>"
  printf '  %-30s : %s\n' "$key" "$value"
}

config_section() {
  local title="${1:?missing title}"
  printf '\n%s\n' "────────────────────────────────────────────────────────"
  printf '  %s\n' "$title"
  printf '%s\n' "────────────────────────────────────────────────────────"
}

show_config() {
  if ! load_config; then
    die "config missing"
    return 1
  fi

  config_section "Grafana Cloud"
  config_row "GCLOUD_HOSTED_METRICS_URL" "${GCLOUD_HOSTED_METRICS_URL:-}"
  config_row "GCLOUD_HOSTED_METRICS_ID" "${GCLOUD_HOSTED_METRICS_ID:-}"
  config_row "GCLOUD_HOSTED_LOGS_URL" "${GCLOUD_HOSTED_LOGS_URL:-}"
  config_row "GCLOUD_HOSTED_LOGS_ID" "${GCLOUD_HOSTED_LOGS_ID:-}"
  config_row "GCLOUD_FM_URL" "${GCLOUD_FM_URL:-}"
  config_row "GCLOUD_RW_API_KEY" "$(mask "${GCLOUD_RW_API_KEY:-}")"

  config_section "Checks"
  config_row "GC_HC_INTERVAL" "${GC_HC_INTERVAL:-}"
  config_row "GC_HC_TIMEOUT" "${GC_HC_TIMEOUT:-}"
  config_row "GC_HC_RETRIES" "${GC_HC_RETRIES:-}"
  config_row "GC_HC_RETRY_DELAY" "${GC_HC_RETRY_DELAY:-}"
  config_row "GC_HC_DNS" "${GC_HC_DNS:-}"
  config_row "GC_HC_TLS" "${GC_HC_TLS:-}"
  config_row "GC_HC_LOKI_WRITE" "${GC_HC_LOKI_WRITE:-}"
  config_row "GC_HC_PROM_QUERY" "${GC_HC_PROM_QUERY:-}"
  config_row "GC_HC_FLEET" "${GC_HC_FLEET:-}"
  config_row "GC_HC_LOG_KEEP" "${GC_HC_LOG_KEEP:-}"
  config_row "GC_HC_LOG_RETENTION" "${GC_HC_LOG_RETENTION:-}"

  config_section "Trace"
  config_row "GC_HC_TRACE" "${GC_HC_TRACE:-}"
  config_row "GC_HC_TRACE_TOOL" "${GC_HC_TRACE_TOOL:-}"
  config_row "GC_HC_TRACE_TIMEOUT" "${GC_HC_TRACE_TIMEOUT:-}"
  config_row "GC_HC_TRACE_MAX_HOPS" "${GC_HC_TRACE_MAX_HOPS:-}"
  config_row "GC_HC_TRACE_LOG_KEEP" "${GC_HC_TRACE_LOG_KEEP:-}"
  config_row "GC_HC_TRACE_LOG_RETENTION" "${GC_HC_TRACE_LOG_RETENTION:-}"
}

show_all_config() {
  printf '\n%s\n' "────────────────────────────────────────────────────────"
  printf '  gc-hc config\n'
  printf '%s\n' "────────────────────────────────────────────────────────"
  config_row "GC_HC_CONFIG_FILE" "$CONFIG_FILE"
  config_row "GC_HC_MAIL_CONFIG_FILE" "$MAIL_CONFIG_FILE"
  show_config
  show_mail_config || {
    config_section "Mail"
    config_row "GC_HC_MAIL_ENABLED" "false"
    config_row "GC_HC_MAIL_CONFIG" "$MAIL_CONFIG_FILE"
  }
  printf '%s\n' "────────────────────────────────────────────────────────"
}
