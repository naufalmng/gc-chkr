# Tool entrypoint. Wires up traps, parses args, dispatches to the action
# handler. Keep this thin — actual logic lives in the per-domain modules.

main() {
  trap on_error  ERR
  trap on_exit   EXIT
  trap on_signal INT TERM

  parse_args "$@"

  case "$ACTION" in
    onboard)     onboard ;;
    config)
      if [[ "$GC_HC_CONFIG_SHOW" == "true" ]]; then show_all_config
      elif [[ "$GC_HC_CONFIG_SMTP" == "true" && -n "$GC_HC_MAIL_TEST" ]]; then send_test_mail_saved "$GC_HC_MAIL_TEST"
      elif [[ "$GC_HC_CONFIG_SMTP" == "true" && "$YES" == "true" ]]; then configure_mail_noninteractive
      elif [[ "$GC_HC_CONFIG_SMTP" == "true" ]]; then configure_mail
      else configure
      fi
      ;;
    check)       run_check ;;
    status)      show_status ;;
    logs)        show_logs ;;
    remove)      remove_self ;;
    enable)      enable_timer ;;
    disable)     disable_timer ;;
    help)        usage ;;
    version)     printf '%s %s\n' "$APP" "$VERSION" ;;
    *)
      die "unknown command: $ACTION"
      usage
      return 1
      ;;
  esac
}

main "$@"
