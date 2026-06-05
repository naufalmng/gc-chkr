#!/usr/bin/env bash
# tests/parity.sh — verify the built dist artifact retains every contract
# the public API depends on. Self-contained (no reference file needed).
#
# What we check:
#   - Both artifacts parse cleanly under bash -n
#   - Tool exposes all expected commands in dispatch
#   - All Grafana Cloud env names present
#   - All HTTP status branches handled
#   - systemd unit content correctly embedded
#   - dpkg maintainer scripts correctly embedded
#   - API key validator still enforces glc_ prefix
#   - Alloy fallback paths preserved
#   - Standalone mode still wired
#   - Pipe-install one-liner still documented

set -e

ROOT="$(cd -- "$(dirname -- "$0")/.." >/dev/null && pwd -P)"
cd "$ROOT"

NEW="dist/gc-hc.sh"
TOOL="dist/gc-hc"

if [[ ! -f "$NEW" || ! -f "$TOOL" ]]; then
  printf '  FAIL  build artifacts missing — run scripts/build.sh first\n' >&2
  exit 1
fi

PASS=0
FAIL=0

assert_in() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -qF -- "$needle" "$file"; then
    printf '  ok    %s\n' "$label"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s  (missing %q in %s)\n' "$label" "$needle" "$file"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Built artifacts parse cleanly ==="
bash -n "$NEW"  && { echo "  ok    installer parses"; PASS=$((PASS+1)); }
bash -n "$TOOL" && { echo "  ok    tool parses";      PASS=$((PASS+1)); }

echo
echo "=== Tool exposes all expected commands ==="
for cmd in onboard config check status logs remove enable disable help version; do
  if grep -Eq "^[[:space:]]*${cmd}\)" "$TOOL"; then
    printf '  ok    command: %s\n' "$cmd"
    PASS=$((PASS+1))
  else
    printf '  FAIL  command: %s missing in dispatch\n' "$cmd"
    FAIL=$((FAIL+1))
  fi
done

echo
echo "=== All Grafana env names present ==="
for v in GCLOUD_HOSTED_METRICS_URL GCLOUD_HOSTED_METRICS_ID \
         GCLOUD_HOSTED_LOGS_URL    GCLOUD_HOSTED_LOGS_ID \
         GCLOUD_FM_URL             GCLOUD_RW_API_KEY \
         GC_HC_TIMEOUT GC_HC_RETRIES GC_HC_RETRY_DELAY \
         GC_HC_DNS GC_HC_TLS GC_HC_LOKI_WRITE \
         GC_HC_PROM_QUERY GC_HC_FLEET \
         GC_HC_LOG_KEEP GC_HC_LOG_RETENTION \
         GC_HC_TRACE GC_HC_TRACE_TOOL \
         GC_HC_TRACE_TIMEOUT GC_HC_TRACE_MAX_HOPS \
         GC_HC_TRACE_LOG_KEEP GC_HC_TRACE_LOG_RETENTION; do
  assert_in "$TOOL" "$v" "env: $v"
done

echo
echo "=== Traceroute CLI flags + dispatch preserved ==="
assert_in "$TOOL" -- "--trace)"          "flag: --trace"
assert_in "$TOOL" -- "--no-trace)"       "flag: --no-trace"
assert_in "$TOOL" "trace_on_failure"     "hook: trace_on_failure"
assert_in "$TOOL" "trace_on_success"     "hook: trace_on_success"
assert_in "$TOOL" "trace_pending_failures" "status: trace_pending_failures"
assert_in "$TOOL" "log_tail_rotate"      "util: log_tail_rotate generic helper"
assert_in "$TOOL" "format_log_line"      "logs: pretty JSONL line formatter"
assert_in "$TOOL" "traceroute"           "tool: traceroute primary"
assert_in "$TOOL" "tracepath"            "tool: tracepath fallback"

echo
echo "=== HTTP status branches preserved ==="
for code in 200 202 204 301 302 307 308 400 401 403 404 405; do
  assert_in "$TOOL" "$code" "http status: $code"
done

echo
echo "=== systemd unit content embedded ==="
for line in 'Type=oneshot' 'ProtectSystem=full' 'NoNewPrivileges=true' \
            'ReadWritePaths=/var/lib/gc-hc /var/log/gc-hc' \
            'OnBootSec=1m' 'OnCalendar=*:0/5:00' \
            'Persistent=true' 'WantedBy=timers.target'; do
  assert_in "$NEW" "$line" "unit: $line"
done

echo
echo "=== dpkg maintainer effects embedded ==="
assert_in "$NEW" 'systemctl daemon-reload'                       "postinst: daemon-reload"
assert_in "$NEW" 'systemctl disable --now gc-hc.timer'           "prerm: disable timer"
assert_in "$NEW" 'rm -rf /etc/gc-hc /var/lib/gc-hc'              "postrm: data wipe"
assert_in "$NEW" 'systemctl reset-failed gc-hc.service gc-hc.timer' "postrm: reset-failed"

echo
echo "=== Pipe-install one-liner documented ==="
assert_in "$NEW" 'curl -fsSL'                    "pipe install example"
assert_in "$NEW" 'sudo bash -s -- install --yes' "non-interactive flag"

echo
echo "=== Brand identifiers ==="
assert_in "$NEW"  'gc-hc'  "kebab brand in installer"
assert_in "$TOOL" 'gchc'   "short alias documented"

echo
echo "=== API key validator still requires glc_ prefix ==="
assert_in "$TOOL" 'glc_*'                  "validator: glc_ guard"
assert_in "$TOOL" 'GCLOUD_RW_API_KEY must' "validator: error msg"

echo
echo "=== Alloy config fallback preserved ==="
assert_in "$TOOL" '/etc/default/alloy'    "alloy default"
assert_in "$TOOL" '/etc/sysconfig/alloy'  "alloy sysconfig"

echo
echo "=== Standalone mode preserved ==="
assert_in "$NEW"  'standalone' "standalone action"
assert_in "$TOOL" '.gc-hc'     "standalone home"

echo
echo "=== SMTP config test dispatch preserved ==="
assert_in "$TOOL" 'send_test_mail_saved "$GC_HC_MAIL_TEST"' "smtp test-only dispatch"
assert_in "$TOOL" 'GC_HC_MAIL_AUTH="on"' "smtp provider auth default"

echo
printf '\nTotal: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
