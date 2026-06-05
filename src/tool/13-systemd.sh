# systemd timer / service lifecycle. Standalone mode is a no-op everywhere
# because we don't (and shouldn't) install user-level units when the tool
# isn't packaged.

write_timer_override() {
  local calendar=""

  if [[ "$MODE" != "system" ]]; then
    return 0
  fi

  need_root
  valid_interval "$GC_HC_INTERVAL"

  calendar="$(calendar_from_interval "$GC_HC_INTERVAL")"

  install -d -m 0755 "$TIMER_OVERRIDE_DIR"

  cat > "$TIMER_OVERRIDE_FILE" <<EOF
[Timer]
OnCalendar=
OnCalendar=${calendar}
EOF

  chmod 0644 "$TIMER_OVERRIDE_FILE"
  chown root:root "$TIMER_OVERRIDE_FILE"
}

enable_timer() {
  LAST_STEP="enable timer"

  if [[ "$MODE" != "system" ]]; then
    info "standalone mode: scheduler is not installed"
    return 0
  fi

  need_root
  need_cmd systemctl
  valid_interval "$GC_HC_INTERVAL"

  if ! confirm "Enable and start gc-hc.timer now?" "y"; then
    info "timer enable skipped"
    return 0
  fi

  write_timer_override
  systemctl daemon-reload

  if ! systemctl enable --now "$TIMER_NAME"; then
    die "failed to enable ${TIMER_NAME}"
    return 1
  fi

  ok "timer enabled"
}

disable_timer() {
  LAST_STEP="disable timer"

  if [[ "$MODE" != "system" ]]; then
    return 0
  fi

  need_root
  systemctl disable --now "$TIMER_NAME"          >/dev/null 2>&1 || true
  systemctl stop "$SERVICE_NAME"                  >/dev/null 2>&1 || true
  systemctl reset-failed "$SERVICE_NAME" "$TIMER_NAME" >/dev/null 2>&1 || true
}

# One-touch onboarding: configure -> enable -> first check -> show status.
# Each step is allowed to fail soft; we still print status so the user gets
# diagnostic feedback even on a bad config.
onboard() {
  cat <<EOF

Onboard plan:
  1. Create/update config:
     ${CONFIG_FILE}

  2. Enable systemd timer:
     ${TIMER_NAME}

  3. Run first healthcheck immediately.

EOF

  if ! confirm "Continue onboard?" "y"; then
    info "cancelled"
    return 0
  fi

  configure
  if confirm "Configure mail notifications?" "n"; then
    configure_mail
  fi
  enable_timer
  run_check || true
  show_status
}
