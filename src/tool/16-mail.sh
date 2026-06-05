# Mail notification config, rendering, and SMTP delivery via msmtp.

load_mail_config() {
  if [[ ! -s "$MAIL_CONFIG_FILE" ]]; then
    return 1
  fi

  source_env "$MAIL_CONFIG_FILE"
}

mail_provider_defaults() {
  case "$GC_HC_MAIL_PROVIDER" in
    gmail)
      GC_HC_MAIL_HOST="smtp.gmail.com"
      GC_HC_MAIL_PORT="587"
      GC_HC_MAIL_TLS="starttls"
      GC_HC_MAIL_AUTH="on"
      ;;
    outlook)
      GC_HC_MAIL_HOST="smtp.office365.com"
      GC_HC_MAIL_PORT="587"
      GC_HC_MAIL_TLS="starttls"
      GC_HC_MAIL_AUTH="on"
      ;;
    yahoo)
      GC_HC_MAIL_HOST="smtp.mail.yahoo.com"
      GC_HC_MAIL_PORT="587"
      GC_HC_MAIL_TLS="starttls"
      GC_HC_MAIL_AUTH="on"
      ;;
    custom) ;;
    *) die "GC_HC_MAIL_PROVIDER must be gmail, outlook, yahoo, or custom"; return 1 ;;
  esac
}

validate_mail_config() {
  [[ "$GC_HC_MAIL_ENABLED" == "true" || "$GC_HC_MAIL_ENABLED" == "false" ]] || {
    die "GC_HC_MAIL_ENABLED must be true or false"; return 1;
  }
  [[ "$GC_HC_MAIL_ON" =~ ^(change|fail|warn|always)$ ]] || {
    die "GC_HC_MAIL_ON must be change, fail, warn, or always"; return 1;
  }
  [[ "$GC_HC_MAIL_PROVIDER" =~ ^(gmail|outlook|yahoo|custom)$ ]] || {
    die "GC_HC_MAIL_PROVIDER must be gmail, outlook, yahoo, or custom"; return 1;
  }
  [[ "$GC_HC_MAIL_PORT" =~ ^[0-9]+$ ]] || {
    die "GC_HC_MAIL_PORT must be numeric"; return 1;
  }
  [[ "$GC_HC_MAIL_TLS" =~ ^(starttls|ssl|none)$ ]] || {
    die "GC_HC_MAIL_TLS must be starttls, ssl, or none"; return 1;
  }
  [[ -n "$GC_HC_MAIL_TO" ]] || { die "GC_HC_MAIL_TO is required"; return 1; }
  [[ -n "$GC_HC_MAIL_FROM" ]] || { die "GC_HC_MAIL_FROM is required"; return 1; }
  [[ -n "$GC_HC_MAIL_HOST" ]] || { die "GC_HC_MAIL_HOST is required"; return 1; }
  if [[ "$GC_HC_MAIL_AUTH" != "off" ]]; then
    [[ -n "$GC_HC_MAIL_USER" ]] || { die "GC_HC_MAIL_USER is required"; return 1; }
    [[ -n "$GC_HC_MAIL_PASS" ]] || { die "GC_HC_MAIL_PASS is required"; return 1; }
  fi
}

mail_recipients() {
  local raw="${1:?missing recipients}"
  local recipient=""
  local recipients=()
  local old_ifs="$IFS"

  IFS=','
  read -r -a recipients <<< "$raw"
  IFS="$old_ifs"

  for recipient in "${recipients[@]}"; do
    recipient="$(trim "$recipient")"
    [[ -n "$recipient" ]] || continue
    printf '%s\n' "$recipient"
  done
}

mail_test_result() {
  local overall="${1:-fail}"
  local now=""
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  case "$overall" in
    pass)
      printf '{"tool":"%s","version":"%s","mode":"%s","host":"smtp-test","started":"%s","finished":"%s","overall":"pass","summary":{"pass":1,"warn":0,"fail":0,"skip":0},"checks":[{"name":"smtp.test","state":"pass","message":"test_pass"}]}\n' "$APP" "$VERSION" "$MODE" "$now" "$now"
      ;;
    warn)
      printf '{"tool":"%s","version":"%s","mode":"%s","host":"smtp-test","started":"%s","finished":"%s","overall":"warn","summary":{"pass":0,"warn":1,"fail":0,"skip":0},"checks":[{"name":"smtp.test","state":"warn","message":"test_warn"}]}\n' "$APP" "$VERSION" "$MODE" "$now" "$now"
      ;;
    *)
      printf '{"tool":"%s","version":"%s","mode":"%s","host":"smtp-test","started":"%s","finished":"%s","overall":"fail","summary":{"pass":0,"warn":0,"fail":1,"skip":0},"checks":[{"name":"smtp.test","state":"fail","message":"test_fail"}]}\n' "$APP" "$VERSION" "$MODE" "$now" "$now"
      ;;
  esac
}

prompt_choice() {
  local var="${1:?missing var}"
  local label="${2:?missing label}"
  local allowed="${3:?missing allowed}"
  local current="${!var:-}"
  local input=""

  while true; do
    input="$(tty_read "${label} [${current}]: ")" || return 1
    input="$(trim "$input")"
    [[ -n "$input" ]] || input="$current"

    if [[ " $allowed " == *" $input "* ]]; then
      printf -v "$var" '%s' "$input"
      export "$var"
      return 0
    fi

    warn "allowed values: $allowed"
  done
}

prompt_mail_password() {
  local input=""

  if [[ -n "${GC_HC_MAIL_PASS:-}" ]]; then
    if confirm "Keep existing SMTP password?" "y"; then
      return 0
    fi
  fi

  input="$(tty_read_secret "SMTP app password: ")" || return 1
  input="$(trim "$input")"
  [[ -n "$input" ]] || { die "SMTP app password cannot be empty"; return 1; }
  GC_HC_MAIL_PASS="$input"
  export GC_HC_MAIL_PASS
}

configure_mail() {
  LAST_STEP="configure mail"

  if [[ "$MODE" == "system" ]]; then
    need_root
  fi

  if [[ -s "$MAIL_CONFIG_FILE" ]]; then
    source_env "$MAIL_CONFIG_FILE"
  fi
  GC_HC_MAIL_ENABLED="true"

  printf '\nMail config target: %s\n' "$MAIL_CONFIG_FILE"
  prompt_choice "GC_HC_MAIL_ON" "Notify on (change / fail / warn / always)" "change fail warn always"
  prompt_choice "GC_HC_MAIL_PROVIDER" "Provider (gmail / outlook / yahoo / custom)" "gmail outlook yahoo custom"
  mail_provider_defaults
  prompt_value "GC_HC_MAIL_TO" "Mail to"
  prompt_value "GC_HC_MAIL_FROM" "Mail from"
  prompt_value "GC_HC_MAIL_USER" "SMTP username"

  if [[ "$GC_HC_MAIL_PROVIDER" == "custom" ]]; then
    prompt_value "GC_HC_MAIL_HOST" "SMTP host"
    prompt_value "GC_HC_MAIL_PORT" "SMTP port"
    prompt_choice "GC_HC_MAIL_TLS" "SMTP TLS (starttls / ssl / none)" "starttls ssl none"
    prompt_value "GC_HC_MAIL_AUTH" "SMTP auth"
  fi

  prompt_mail_password
  validate_mail_config

  while confirm "Send test email?" "y"; do
    if send_test_mail_current "${GC_HC_MAIL_TEST:-fail}"; then
      break
    fi
    warn "SMTP test failed; review the previous values and try again"
    prompt_choice "GC_HC_MAIL_PROVIDER" "Provider (gmail / outlook / yahoo / custom)" "gmail outlook yahoo custom"
    mail_provider_defaults
    prompt_value "GC_HC_MAIL_TO" "Mail to"
    prompt_value "GC_HC_MAIL_FROM" "Mail from"
    prompt_value "GC_HC_MAIL_USER" "SMTP username"
    if [[ "$GC_HC_MAIL_PROVIDER" == "custom" ]]; then
      prompt_value "GC_HC_MAIL_HOST" "SMTP host"
      prompt_value "GC_HC_MAIL_PORT" "SMTP port"
      prompt_choice "GC_HC_MAIL_TLS" "SMTP TLS (starttls / ssl / none)" "starttls ssl none"
      prompt_value "GC_HC_MAIL_AUTH" "SMTP auth"
    fi
    prompt_mail_password
    validate_mail_config
  done

  write_mail_config
  ok "mail config saved: $MAIL_CONFIG_FILE"
}

write_mail_config() {
  mkdir -p "$CONFIG_DIR"
  chmod 0750 "$CONFIG_DIR" 2>/dev/null || true

  if [[ "$MODE" == "system" ]]; then
    chown root:root "$CONFIG_DIR"
  fi

  if [[ -e "$MAIL_CONFIG_FILE" && "$FORCE" != "true" ]]; then
    cp -a "$MAIL_CONFIG_FILE" "${MAIL_CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  fi

  {
    printf "GC_HC_MAIL_ENABLED='%s'\n"       "$GC_HC_MAIL_ENABLED"
    printf "GC_HC_MAIL_ON='%s'\n"            "$GC_HC_MAIL_ON"
    printf "GC_HC_MAIL_PROVIDER='%s'\n"      "$GC_HC_MAIL_PROVIDER"
    printf "GC_HC_MAIL_TO='%s'\n"            "$(quote_env "$GC_HC_MAIL_TO")"
    printf "GC_HC_MAIL_FROM='%s'\n"          "$(quote_env "$GC_HC_MAIL_FROM")"
    printf "GC_HC_MAIL_HOST='%s'\n"          "$(quote_env "$GC_HC_MAIL_HOST")"
    printf "GC_HC_MAIL_PORT='%s'\n"          "$GC_HC_MAIL_PORT"
    printf "GC_HC_MAIL_USER='%s'\n"          "$(quote_env "$GC_HC_MAIL_USER")"
    printf "GC_HC_MAIL_PASS='%s'\n"          "$(quote_env "$GC_HC_MAIL_PASS")"
    printf "GC_HC_MAIL_TLS='%s'\n"           "$GC_HC_MAIL_TLS"
    printf "GC_HC_MAIL_AUTH='%s'\n"          "$GC_HC_MAIL_AUTH"
    printf "GC_HC_MAIL_COOLDOWN='%s'\n"      "$GC_HC_MAIL_COOLDOWN"
    printf "GC_HC_MAIL_SUBJECT_PREFIX='%s'\n" "$(quote_env "$GC_HC_MAIL_SUBJECT_PREFIX")"
  } > "$MAIL_CONFIG_FILE"

  chmod 0600 "$MAIL_CONFIG_FILE"
  if [[ "$MODE" == "system" ]]; then
    chown root:root "$MAIL_CONFIG_FILE"
  fi
}

configure_mail_noninteractive() {
  LAST_STEP="configure mail"

  if [[ "$MODE" == "system" ]]; then
    need_root
  fi

  if [[ -s "$MAIL_CONFIG_FILE" ]]; then
    source_env "$MAIL_CONFIG_FILE"
  fi
  mail_provider_defaults
  validate_mail_config
  if [[ -n "$GC_HC_MAIL_TEST" ]]; then
    send_test_mail_current "$GC_HC_MAIL_TEST"
  fi
  write_mail_config
  ok "mail config saved: $MAIL_CONFIG_FILE"
}

show_mail_config() {
  if ! load_mail_config; then
    return 1
  fi

  config_section "Mail"
  config_row "GC_HC_MAIL_STATUS" "$(mail_status_line)"
  config_row "GC_HC_MAIL_ENABLED" "${GC_HC_MAIL_ENABLED:-}"
  config_row "GC_HC_MAIL_ON" "${GC_HC_MAIL_ON:-}"
  config_row "GC_HC_MAIL_PROVIDER" "${GC_HC_MAIL_PROVIDER:-}"
  config_row "GC_HC_MAIL_TO" "${GC_HC_MAIL_TO:-}"
  config_row "GC_HC_MAIL_FROM" "${GC_HC_MAIL_FROM:-}"
  config_row "GC_HC_MAIL_HOST" "${GC_HC_MAIL_HOST:-}"
  config_row "GC_HC_MAIL_PORT" "${GC_HC_MAIL_PORT:-}"
  config_row "GC_HC_MAIL_USER" "${GC_HC_MAIL_USER:-}"
  config_row "GC_HC_MAIL_PASS" "$(secret_state "${GC_HC_MAIL_PASS:-}")"
  config_row "GC_HC_MAIL_TLS" "${GC_HC_MAIL_TLS:-}"
  config_row "GC_HC_MAIL_AUTH" "${GC_HC_MAIL_AUTH:-}"
  config_row "GC_HC_MAIL_COOLDOWN" "${GC_HC_MAIL_COOLDOWN:-}"
  config_row "GC_HC_MAIL_SUBJECT_PREFIX" "${GC_HC_MAIL_SUBJECT_PREFIX:-}"
}

secret_state() {
  if [[ -n "${1:-}" ]]; then
    printf '(set)'
  else
    printf '(empty)'
  fi
}

mail_status_line() {
  local provider=""

  if [[ ! -s "$MAIL_CONFIG_FILE" ]]; then
    printf '✗ disabled'
    return 0
  fi

  source_env "$MAIL_CONFIG_FILE" || {
    printf '! invalid'
    return 0
  }

  provider="${GC_HC_MAIL_PROVIDER:-custom}"
  provider="${provider^^}"

  if [[ "${GC_HC_MAIL_ENABLED:-false}" != "true" ]]; then
    printf '✗ disabled (%s)' "$provider"
    return 0
  fi

  if [[ -z "${GC_HC_MAIL_HOST:-}" || -z "${GC_HC_MAIL_TO:-}" || -z "${GC_HC_MAIL_FROM:-}" ]]; then
    printf '! invalid (%s)' "$provider"
    return 0
  fi

  if [[ "${GC_HC_MAIL_AUTH:-plain}" != "off" && ( -z "${GC_HC_MAIL_USER:-}" || -z "${GC_HC_MAIL_PASS:-}" ) ]]; then
    printf '! invalid (%s)' "$provider"
    return 0
  fi

  if ! command -v msmtp >/dev/null 2>&1; then
    printf '! enabled (%s, msmtp missing)' "$provider"
    return 0
  fi

  printf '✓ enabled (%s)' "$provider"
}

mail_state_file() {
  printf '%s/mail.last' "$STATE_DIR"
}

mail_signature() {
  local result="${1:-}"
  printf '%s' "$result" | sed -n 's/.*"overall":"\([^"]*\)".*"summary":{\([^}]*\)}.*/\1|\2/p'
}

mail_json_value() {
  local json="${1:?missing json}"
  local key="${2:?missing key}"
  printf '%s' "$json" | sed -n "s/.*\"${key}\":\"\([^\"]*\)\".*/\1/p" | head -n 1
}

mail_json_count() {
  local json="${1:?missing json}"
  local key="${2:?missing key}"
  printf '%s' "$json" | sed -n "s/.*\"${key}\":\([0-9]*\).*/\1/p" | head -n 1
}

should_send_mail() {
  local overall="${1:?missing overall}"
  local signature="${2:?missing signature}"
  local now="${3:?missing now}"
  local state_file=""
  local previous_signature=""
  local previous_sent="0"

  [[ "$GC_HC_MAIL_ENABLED" == "true" ]] || return 1

  case "$GC_HC_MAIL_ON" in
    always) ;;
    fail) [[ "$overall" == "fail" ]] || return 1 ;;
    warn) [[ "$overall" == "warn" || "$overall" == "fail" ]] || return 1 ;;
    change)
      state_file="$(mail_state_file)"
      if [[ -s "$state_file" ]]; then
        previous_signature="$(sed -n '1p' "$state_file")"
        previous_sent="$(sed -n '2p' "$state_file")"
      fi
      [[ "$signature" != "$previous_signature" ]] || return 1
      ;;
  esac

  state_file="$(mail_state_file)"
  if [[ -s "$state_file" ]]; then
    previous_sent="$(sed -n '2p' "$state_file")"
  fi
  previous_sent="${previous_sent:-0}"

  if [[ "$GC_HC_MAIL_ON" != "change" && "$GC_HC_MAIL_COOLDOWN" =~ ^[0-9]+$ ]]; then
    (( now - previous_sent >= GC_HC_MAIL_COOLDOWN )) || return 1
  fi

  return 0
}

record_mail_state() {
  local signature="${1:?missing signature}"
  local now="${2:?missing now}"

  mkdir -p "$STATE_DIR"
  chmod 0750 "$STATE_DIR" 2>/dev/null || true
  printf '%s\n%s\n' "$signature" "$now" > "$(mail_state_file)"
  chmod 0640 "$(mail_state_file)" 2>/dev/null || true
}

render_mail_subject() {
  local overall="${1:?missing overall}"
  local host="${2:?missing host}"

  case "$overall" in
    pass) printf '[PASS][%s] Health Check Passed | GC-HC' "$host" ;;
    warn) printf '[WARN][%s] Health Check Warned | GC-HC' "$host" ;;
    *)    printf '[FAIL][%s] Health Check Failed | GC-HC' "$host" ;;
  esac
}

render_mail_body() {
  local result="${1:?missing result}"
  local subject="${2:?missing subject}"
  local overall host started finished pass warn fail skip
  local status_icon="❌"

  overall="$(mail_json_value "$result" overall)"
  host="$(mail_json_value "$result" host)"
  started="$(mail_json_value "$result" started)"
  finished="$(mail_json_value "$result" finished)"
  pass="$(mail_json_count "$result" pass)"
  warn="$(mail_json_count "$result" warn)"
  fail="$(mail_json_count "$result" fail)"
  skip="$(mail_json_count "$result" skip)"
  : "${overall:=n/a}" "${host:=n/a}" "${started:=n/a}" "${finished:=n/a}"
  : "${pass:=0}" "${warn:=0}" "${fail:=0}" "${skip:=0}"

  case "$overall" in
    pass) status_icon="✅" ;;
    warn) status_icon="⚠️" ;;
    fail) status_icon="❌" ;;
  esac

  cat <<EOF
Subject: $subject
From: $GC_HC_MAIL_FROM
To: $GC_HC_MAIL_TO

${status_icon} Alert Summary

Status      : ${overall^^}
Host        : $host
Started     : $started
Finished    : $finished
Tool        : $APP $VERSION
Mode        : $MODE

📊 Summary
PASS        : $pass
WARN        : $warn
FAIL        : $fail
SKIP        : $skip

🧾 Raw Result
$result
EOF
}

build_msmtp_config() {
  local path="${1:?missing path}"
  local tls="on"
  local tls_starttls="on"

  case "$GC_HC_MAIL_TLS" in
    ssl) tls="on"; tls_starttls="off" ;;
    starttls) tls="on"; tls_starttls="on" ;;
    none) tls="off"; tls_starttls="off" ;;
  esac

  {
    printf 'defaults\n'
    printf 'auth %s\n' "$GC_HC_MAIL_AUTH"
    printf 'tls %s\n' "$tls"
    printf 'tls_starttls %s\n' "$tls_starttls"
    printf 'account default\n'
    printf 'host %s\n' "$GC_HC_MAIL_HOST"
    printf 'port %s\n' "$GC_HC_MAIL_PORT"
    printf 'from %s\n' "$GC_HC_MAIL_FROM"
    if [[ "$GC_HC_MAIL_AUTH" != "off" ]]; then
      printf 'user %s\n' "$GC_HC_MAIL_USER"
      printf 'password %s\n' "$GC_HC_MAIL_PASS"
    fi
    printf 'account default : default\n'
  } > "$path"
  chmod 0600 "$path"
}

send_mail_payload() {
  local payload="${1:?missing payload}"
  local tmp_config=""
  local recipients=()

  need_cmd msmtp mktemp chmod rm
  tmp_config="$(mktemp)"
  build_msmtp_config "$tmp_config"
  mapfile -t recipients < <(mail_recipients "$GC_HC_MAIL_TO")
  if (( ${#recipients[@]} == 0 )); then
    rm -f "$tmp_config"
    die "GC_HC_MAIL_TO has no recipients"
    return 1
  fi
  if printf '%s' "$payload" | msmtp --file="$tmp_config" -- "${recipients[@]}"; then
    rm -f "$tmp_config"
    return 0
  fi
  rm -f "$tmp_config"
  return 1
}

send_test_mail_current() {
  local overall="${1:-fail}"
  local subject=""
  local payload=""
  local result=""

  validate_mail_config
  result="$(mail_test_result "$overall")"
  subject="$(render_mail_subject "$overall" "smtp-test")"
  payload="$(render_mail_body "$result" "$subject")"
  send_mail_payload "$payload"
}

send_test_mail_saved() {
  local overall="${1:-fail}"

  load_mail_config || { die "mail config missing"; return 1; }
  send_test_mail_current "$overall"
}

notify_mail_from_result() {
  local result="${1:?missing result}"
  local overall="${2:?missing overall}"
  local host="${3:?missing host}"
  local now=""
  local signature=""
  local subject=""
  local payload=""

  load_mail_config || return 0
  [[ "$GC_HC_MAIL_ENABLED" == "true" ]] || return 0
  validate_mail_config || return 0

  now="$(date +%s)"
  signature="$(mail_signature "$result")"
  [[ -n "$signature" ]] || signature="$overall"

  if ! should_send_mail "$overall" "$signature" "$now"; then
    return 0
  fi

  subject="$(render_mail_subject "$overall" "$host")"
  payload="$(render_mail_body "$result" "$subject")"

  if send_mail_payload "$payload"; then
    record_mail_state "$signature" "$now"
  else
    warn "mail notification failed"
  fi
}
