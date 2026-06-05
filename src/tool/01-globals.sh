# Mutable globals: CLI flags, runtime state, and Grafana Cloud credentials.
# Defaults are intentionally tolerant; validate_config enforces correctness
# before any network call.

ACTION="help"
TIMEOUT="10"
QUIET="false"
JSON="false"
YES="false"
FORCE="false"
LAST_STEP="init"
TRACE_FORCE=""

GCLOUD_HOSTED_METRICS_URL="${GCLOUD_HOSTED_METRICS_URL:-}"
GCLOUD_HOSTED_METRICS_ID="${GCLOUD_HOSTED_METRICS_ID:-}"
GCLOUD_HOSTED_LOGS_URL="${GCLOUD_HOSTED_LOGS_URL:-}"
GCLOUD_HOSTED_LOGS_ID="${GCLOUD_HOSTED_LOGS_ID:-}"
GCLOUD_FM_URL="${GCLOUD_FM_URL:-}"
GCLOUD_RW_API_KEY="${GCLOUD_RW_API_KEY:-}"

GC_HC_INTERVAL="${GC_HC_INTERVAL:-5m}"
GC_HC_TIMEOUT="${GC_HC_TIMEOUT:-10}"
GC_HC_RETRIES="${GC_HC_RETRIES:-2}"
GC_HC_RETRY_DELAY="${GC_HC_RETRY_DELAY:-2}"
GC_HC_DNS="${GC_HC_DNS:-true}"
GC_HC_TLS="${GC_HC_TLS:-true}"
GC_HC_LOKI_WRITE="${GC_HC_LOKI_WRITE:-true}"
GC_HC_PROM_QUERY="${GC_HC_PROM_QUERY:-true}"
GC_HC_FLEET="${GC_HC_FLEET:-true}"

# Log retention. The check log is JSONL (one record per line) and gets
# tail-rotated to keep the last N entries. 0 = disable rotation (keep all
# forever — manage via logrotate). Default 100 ≈ 8h of timer-mode history
# at 5min interval, ~60KB on disk.
GC_HC_LOG_KEEP="${GC_HC_LOG_KEEP:-100}"
GC_HC_LOG_RETENTION="${GC_HC_LOG_RETENTION:-24h}"

# Auto-traceroute on failure. auto = capture once per failure run, reset
# state when probe recovers. always = force every run. never = disabled.
# Tool defaults to auto-detect (traceroute > tracepath); skip cleanly if
# none installed (no apt install at runtime — preserves zero-deps contract).
GC_HC_TRACE="${GC_HC_TRACE:-auto}"
GC_HC_TRACE_TOOL="${GC_HC_TRACE_TOOL:-auto}"
GC_HC_TRACE_TIMEOUT="${GC_HC_TRACE_TIMEOUT:-2}"
GC_HC_TRACE_MAX_HOPS="${GC_HC_TRACE_MAX_HOPS:-15}"
GC_HC_TRACE_LOG_KEEP="${GC_HC_TRACE_LOG_KEEP:-50}"
GC_HC_TRACE_LOG_RETENTION="${GC_HC_TRACE_LOG_RETENTION:-24h}"

GC_HC_CONFIG_SMTP="false"
GC_HC_CONFIG_SHOW="false"
GC_HC_MAIL_TEST=""
GC_HC_MAIL_ENABLED="${GC_HC_MAIL_ENABLED:-false}"
GC_HC_MAIL_ON="${GC_HC_MAIL_ON:-change}"
GC_HC_MAIL_PROVIDER="${GC_HC_MAIL_PROVIDER:-custom}"
GC_HC_MAIL_TO="${GC_HC_MAIL_TO:-}"
GC_HC_MAIL_FROM="${GC_HC_MAIL_FROM:-}"
GC_HC_MAIL_HOST="${GC_HC_MAIL_HOST:-}"
GC_HC_MAIL_PORT="${GC_HC_MAIL_PORT:-587}"
GC_HC_MAIL_USER="${GC_HC_MAIL_USER:-}"
GC_HC_MAIL_PASS="${GC_HC_MAIL_PASS:-}"
GC_HC_MAIL_TLS="${GC_HC_MAIL_TLS:-starttls}"
GC_HC_MAIL_AUTH="${GC_HC_MAIL_AUTH:-plain}"
GC_HC_MAIL_COOLDOWN="${GC_HC_MAIL_COOLDOWN:-3600}"
GC_HC_MAIL_SUBJECT_PREFIX="${GC_HC_MAIL_SUBJECT_PREFIX:-[GC-HC]}"

CHECKS=()
PASS=0
WARN=0
FAIL=0
SKIP=0
