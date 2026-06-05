# Documentation

> 🇬🇧 [English](#english) · 🇮🇩 [Bahasa Indonesia](#bahasa-indonesia)

---

## English

### Table of contents

1. [What it is](#what-it-is)
2. [Install](#install)
3. [Commands](#commands)
4. [What you'll see](#what-youll-see)
5. [Configuration](#configuration)
6. [How it's wired](#how-its-wired)
7. [Build it yourself](#build-it-yourself)
8. [Design choices](#design-choices)
9. [Troubleshooting](#troubleshooting)

### What it is

When Grafana Cloud says *"no data"* for a host, the symptom is on the dashboard but the cause is almost always on the node: DNS, TLS, auth, an outbound firewall, a typo in the remote_write URL, or a Loki rate limit. `gc-hc` runs from the node and tells you, in seconds, which of those it is.

It probes — from the host that's actually shipping the data:

- **DNS** resolution for every Grafana Cloud endpoint you've configured
- **TLS** handshake, with certificate verification
- **Prometheus `remote_write`** reachability and credentials (POSTs to your `/api/prom/push`)
- **Prometheus query** API health (`/api/prom/api/v1/status/buildinfo`)
- **Loki push** with a real, well-formed payload (catches 400 vs 401 vs 403 cleanly)
- **Fleet Management** endpoint (optional, for hosts using Grafana Agent's fleet management)

Result is a single JSON document, persisted, and re-emitted on every systemd-timer run so you can ship it back to Grafana Cloud as another data source.

### Install

One-liner, the way you'd expect:

```bash
curl -fsSL https://github.com/naufalmng/gc-hc/releases/latest/download/gc-hc.sh | sudo bash
```

The script builds a real `.deb` on the fly and hands it to `apt-get install`, so removal is the standard `sudo apt-get remove gc-hc`. No untracked files in `/usr/local`, no surprise systemd units, nothing apt doesn't know about.

**Non-interactive:**

```bash
curl -fsSL https://github.com/naufalmng/gc-hc/releases/latest/download/gc-hc.sh | sudo bash -s -- install --yes
```

**Standalone** (no apt, no systemd, just a binary in `$PWD`):

```bash
curl -fsSL https://github.com/naufalmng/gc-hc/releases/latest/download/gc-hc.sh | bash -s -- standalone
./gc-hc config
./gc-hc check
```

### Commands

After install, both `gc-hc` and `gchc` work — `gchc` is a one-line wrapper that exec's into `gc-hc`. They are interchangeable.

| Command | What it does |
| --- | --- |
| `gc-hc onboard` | Configure, enable the systemd timer, run the first check |
| `gc-hc config` | Create or update `/etc/gc-hc/env` |
| `gc-hc config show` / `--show` | Print the config with the API key masked |
| `gc-hc check` | Run a healthcheck once |
| `gc-hc check --json` | Same, but emit only the result JSON (machine-readable) |
| `gc-hc status` | Show timer state, last result, next scheduled run |
| `gc-hc logs` | Tail journalctl (system mode) or the local log file |
| `gc-hc enable` / `disable` | Toggle the systemd timer |
| `gc-hc remove` | Remove the package or standalone data |
| `gc-hc help` | Print usage |

**Useful flags**: `-i 5m` (timer interval), `-t 10` (curl timeout seconds), `-q` (quiet), `-y` (assume yes), `--json`, `--no-dns`, `--no-tls`, `--no-loki-write`, `--no-prom-query`, `--no-fleet`.

### What you'll see

```
────────────────────────────────────────────────────────
  gc-hc status
────────────────────────────────────────────────────────
  status       : ✓ enabled
  timer        : ✓ active
  service      : ✓ inactive
  last check   : ✓ pass
  next run     : 00h 04m 12s left
────────────────────────────────────────────────────────
  tool         : gc-hc 2.0.0
  mode         : system
  binary       : /usr/bin/gc-hc
  config       : /etc/gc-hc/env
  state        : /var/lib/gc-hc/last.json
  log          : /var/log/gc-hc/gc-hc.log
────────────────────────────────────────────────────────
```

A failed run writes a discriminated reason — not just "fail":

| Check        | State | Message                |
| ------------ | ----- | ---------------------- |
| `prom.dns`   | pass  | resolved               |
| `prom.tls`   | pass  | handshake_ok           |
| `prom.push`  | pass  | reachable_http_400     |
| `prom.query` | pass  | http_200               |
| `loki.write` | fail  | auth_http_401          |
| `fleet`      | skip  | disabled               |

`loki.write: auth_http_401` is the point — you immediately know it's the API key, not DNS, not the firewall.

Exit codes follow the verdict precedence: `0` if all PASS, `1` if any WARN, `2` if any FAIL. Hook it into your alerting.

### Configuration

Configured via `/etc/gc-hc/env` (system mode) or `./.gc-hc/env` (standalone). The `onboard` flow walks you through every field.

| Variable                         | Required | What it is                                              |
| -------------------------------- | :------: | ------------------------------------------------------- |
| `GCLOUD_HOSTED_METRICS_URL`      | yes      | Prometheus `remote_write` URL (`/api/prom/push`)        |
| `GCLOUD_HOSTED_METRICS_ID`       | yes      | Numeric Prometheus instance ID                          |
| `GCLOUD_HOSTED_LOGS_URL`         | yes      | Loki push URL                                           |
| `GCLOUD_HOSTED_LOGS_ID`          | yes      | Numeric Loki instance ID                                |
| `GCLOUD_RW_API_KEY`              | yes      | Grafana Cloud API key (must start with `glc_`)          |
| `GCLOUD_FM_URL`                  | optional | Fleet Management endpoint                               |
| `GC_HC_INTERVAL`                 | optional | Timer interval (1m, 5m, 15m, 1h; default `5m`)          |
| `GC_HC_TIMEOUT`                  | optional | curl timeout, seconds (1–300, default 10)               |
| `GC_HC_RETRIES`                  | optional | curl retries (default 2)                                |
| `GC_HC_RETRY_DELAY`              | optional | curl retry delay, seconds (default 2)                   |
| `GC_HC_DNS` / `GC_HC_TLS`        | optional | `false` to disable that probe                           |
| `GC_HC_LOKI_WRITE`               | optional | `false` to skip the Loki write probe                    |
| `GC_HC_PROM_QUERY`               | optional | `false` to skip the Prometheus query probe              |
| `GC_HC_FLEET`                    | optional | `false` to skip the Fleet probe                         |
| `GC_HC_LOG_RETENTION`            | optional | Check log age retention (`24h` default, `0` disables)   |
| `GC_HC_LOG_KEEP`                 | optional | Fallback last N check entries kept (default 100)        |
| `GC_HC_TRACE`                    | optional | `auto` (default), `always`, or `never` — auto-traceroute on probe failure |
| `GC_HC_TRACE_TOOL`               | optional | `auto` (default), `traceroute`, or `tracepath`          |
| `GC_HC_TRACE_TIMEOUT`            | optional | Per-hop timeout, seconds (default 2)                    |
| `GC_HC_TRACE_MAX_HOPS`           | optional | Abort after N hops (default 15)                         |
| `GC_HC_TRACE_LOG_RETENTION`      | optional | Trace log age retention (`24h` default, `0` disables)   |
| `GC_HC_TRACE_LOG_KEEP`           | optional | Fallback last N entries kept per probe log (default 50) |

If you're already running [Grafana Alloy](https://grafana.com/docs/alloy/latest/) and the same vars are set in `/etc/default/alloy` or `/etc/sysconfig/alloy`, `gc-hc` will pick them up automatically.

The config file is mode `0600` and the API key is masked everywhere it's printed (`status`, `config show`).

SMTP mail notifications are configured separately in `/etc/gc-hc/mail.env`
(system mode) or `./.gc-hc/mail.env` (standalone) to keep mail credentials out
of the core healthcheck config:

```bash
sudo gc-hc config smtp
gc-hc config smtp --test        # default test verdict: fail
gc-hc config smtp --test warn   # custom test verdict: warn/pass/fail
```

Non-interactive setup example:

```bash
sudo GC_HC_MAIL_ENABLED=true \
  GC_HC_MAIL_ON=change \
  GC_HC_MAIL_PROVIDER=gmail \
  GC_HC_MAIL_TO=ops@example.com \
  GC_HC_MAIL_FROM=gc@example.com \
  GC_HC_MAIL_USER=gc@example.com \
  GC_HC_MAIL_PASS=abcdefghijklmnop \
  gc-hc config smtp --yes
```

`GC_HC_MAIL_PASS` is stored in `mail.env`, so that file is mode `0600` and must
be treated as secret. `config show` only prints `GC_HC_MAIL_PASS=(set)`.
Use comma-separated `GC_HC_MAIL_TO` for multiple recipients. Delivery uses
`msmtp`; install it with:

```bash
sudo apt-get install -y msmtp ca-certificates
```

Run `gc-hc config smtp --test` after SMTP config exists to send a test message.

### How it's wired

```
                ┌─────────────────────────────────────┐
                │  curl ... | sudo bash               │
                │  (single self-contained script)     │
                └──────────────┬──────────────────────┘
                               │
                               ▼
                ┌─────────────────────────────────────┐
                │  installer (gc-hc.sh)               │
                │   • builds .deb in /var/tmp         │
                │   • apt-get install ./*.deb         │
                └──────────────┬──────────────────────┘
                               │
              ┌────────────────┴────────────────────┐
              ▼                                     ▼
   /usr/bin/gc-hc                    /lib/systemd/system/
   /usr/bin/gchc                       gc-hc.service
                                       gc-hc.timer
              │                                     │
              └────────────────┬────────────────────┘
                               ▼
                ┌─────────────────────────────────────┐
                │  gc-hc check  (every 5m default)    │
                │    DNS → TLS → prom → loki → fleet  │
                └──────────────┬──────────────────────┘
                               ▼
                /var/lib/gc-hc/last.json
                /var/log/gc-hc/gc-hc.log
```

The installer is one file. The runtime tool is a separate script embedded inside it. Service and timer units, plus `postinst`/`prerm`/`postrm` maintainer scripts, are also embedded — at install time we materialize them onto disk and let `dpkg` track them.

That's how `apt-get remove` knows about everything we put down: every file is owned by the `gc-hc` package, by design.

### Build it yourself

```bash
git clone https://github.com/naufalmng/gc-hc
cd gc-hc
make build           # → dist/gc-hc.sh, dist/gc-hc
make test            # smoke + bats
make install         # local install via apt-get
```

**Source layout:**

```
gc-hc/
├── src/
│   ├── tool/         # 15 modules — runtime healthcheck
│   └── installer/    # 9 modules — .deb builder + apt installer
├── assets/
│   ├── systemd/      # service + timer units
│   ├── debian/       # postinst, prerm, postrm, control template
│   └── banner/       # ASCII banner
├── scripts/build.sh  # assembles dist artifacts
├── tests/
│   ├── bats/         # unit tests (pure functions)
│   ├── smoke.sh      # quick assertions, no external deps
│   └── parity.sh     # verifies built artifact retains every contract
└── .github/workflows/  ci.yml + release.yml
```

The build pipeline concatenates source modules in lexical order, embeds asset files via heredoc placeholders, and substitutes `__PACKAGE_VERSION__`, `__PACKAGE_MAINTAINER__`, `__PACKAGE_HOMEPAGE__` from `VERSION` plus environment overrides.

### Design choices

- **No jq dependency.** Result JSON is hand-assembled with a pure-bash `json_escape`. The healthcheck must keep working even on minimal Debian images.
- **`/dev/tty` for prompts.** That's what makes `curl ... | sudo bash` interactive — stdin is the pipe, but the user's terminal is still attached.
- **API key masking by default.** `config show` and `status` print `glc_xx...yyyy`; the unredacted value never leaves `/etc/gc-hc/env` (mode `0600`).
- **400 is a pass for `remote_write` empty bodies.** Mimir/Cortex respond 400 to an empty protobuf POST when auth is good, which is genuinely the cheapest reachable+authed probe — annotated explicitly in the result.
- **Verdict precedence is FAIL > WARN > PASS.** Exit codes mirror that: `0/1/2`. Hook it into your alerting.
- **One artifact, two lifecycles.** The same script can either build a `.deb` (system mode) or drop a self-contained binary (standalone mode). Same source, different install entry.

### Troubleshooting

**`config missing, run: gc-hc config`** — no `/etc/gc-hc/env` and no usable Alloy fallback. Run `sudo gc-hc onboard`.

**`GCLOUD_RW_API_KEY must start with glc_`** — Grafana Cloud API keys always start with `glc_`. If yours doesn't, you might be holding a different credential type (SA token, etc.). Generate a proper Access Policy token with `metrics:write` and `logs:write` scopes.

**`prom.push: auth_http_401`** — credentials are wrong, or the metrics ID doesn't match the URL's region/stack.

**`loki.write: bad_payload_http_400`** — the Loki endpoint accepted auth but rejected the test payload. Most often a region/URL mismatch where another Loki accepts the credential but disagrees with the body schema. Confirm the `GCLOUD_HOSTED_LOGS_URL` matches your stack.

**`*.dns: lookup_failed`** — DNS is broken on the host. Check `/etc/resolv.conf`, `systemd-resolved` status, or split-horizon DNS. Has nothing to do with credentials.

**`*.tls: handshake_failed`** — outbound HTTPS to Grafana Cloud is being intercepted, MITM'd, or blocked at the firewall. `openssl s_client -connect <host>:443` will give you the same answer in more detail.

**`prom.query: reachable_http_404`** — buildinfo endpoint isn't where we expect. Self-hosted or older Mimir/Cortex deployments sometimes route this differently. The `pass` HTTP statuses in `check_prom_query` accept 404 as "reachable but no buildinfo" — not a fail.

---

## Bahasa Indonesia

### Daftar isi

1. [Apa itu](#apa-itu)
2. [Instalasi](#instalasi)
3. [Perintah](#perintah)
4. [Tampilan output](#tampilan-output)
5. [Konfigurasi](#konfigurasi)
6. [Cara kerja](#cara-kerja)
7. [Build sendiri](#build-sendiri)
8. [Pilihan desain](#pilihan-desain)
9. [Troubleshooting](#troubleshooting-1)

### Apa itu

Kalau Grafana Cloud bilang *"no data"* untuk sebuah host, gejalanya muncul di dashboard tapi penyebabnya hampir selalu di node: DNS, TLS, auth, firewall outbound, salah ketik URL `remote_write`, atau Loki kena rate limit. `gc-hc` jalan dari node dan kasih tahu masalahnya yang mana, dalam hitungan detik.

`gc-hc` melakukan probe — dari host yang sebenarnya ngirim data:

- **DNS** resolution untuk semua endpoint Grafana Cloud yang lu konfigurasi
- **TLS** handshake, dengan certificate verification
- **Prometheus `remote_write`** reachability dan credentials (POST ke `/api/prom/push`)
- **Prometheus query** API health (`/api/prom/api/v1/status/buildinfo`)
- **Loki push** dengan payload yang valid (membedakan 400 vs 401 vs 403 dengan jelas)
- **Fleet Management** endpoint (opsional, untuk host yang pakai fleet management Grafana Agent)

Hasilnya satu dokumen JSON, disimpan di disk, dan dipancarkan ulang setiap timer jalan — bisa lu kirim balik ke Grafana Cloud sebagai data source tambahan.

### Instalasi

One-liner, persis kayak yang lu harapin:

```bash
curl -fsSL https://github.com/naufalmng/gc-hc/releases/latest/download/gc-hc.sh | sudo bash
```

Script-nya bikin `.deb` asli on the fly, lalu di-install via `apt-get install` — jadi pas mau hapus, tinggal `sudo apt-get remove gc-hc`. Ga ada file siluman di `/usr/local`, ga ada systemd unit yang nyangkut, semua di-track sama apt.

**Non-interaktif:**

```bash
curl -fsSL https://github.com/naufalmng/gc-hc/releases/latest/download/gc-hc.sh | sudo bash -s -- install --yes
```

**Standalone** (tanpa apt, tanpa systemd, cuma binary di `$PWD`):

```bash
curl -fsSL https://github.com/naufalmng/gc-hc/releases/latest/download/gc-hc.sh | bash -s -- standalone
./gc-hc config
./gc-hc check
```

### Perintah

Setelah install, `gc-hc` dan `gchc` dua-duanya jalan — `gchc` itu wrapper satu baris yang exec ke `gc-hc`. Sama persis, bisa dipakai bergantian.

| Perintah | Fungsi |
| --- | --- |
| `gc-hc onboard` | Konfigurasi, aktifkan systemd timer, jalankan check pertama |
| `gc-hc config` | Bikin atau update `/etc/gc-hc/env` |
| `gc-hc config show` / `--show` | Print config dengan API key di-mask |
| `gc-hc check` | Jalankan healthcheck sekali |
| `gc-hc check --json` | Sama, tapi cuma output JSON (buat script) |
| `gc-hc status` | Tampilkan state timer, hasil terakhir, jadwal berikutnya |
| `gc-hc logs` | Tail journalctl (system mode) atau log file lokal |
| `gc-hc enable` / `disable` | Hidupkan/matikan systemd timer |
| `gc-hc remove` | Hapus package atau data standalone |
| `gc-hc help` | Tampilkan bantuan |

**Flag yang berguna**: `-i 5m` (interval timer), `-t 10` (timeout curl detik), `-q` (quiet), `-y` (auto-yes), `--json`, `--no-dns`, `--no-tls`, `--no-loki-write`, `--no-prom-query`, `--no-fleet`.

### Tampilan output

```
────────────────────────────────────────────────────────
  gc-hc status
────────────────────────────────────────────────────────
  status       : ✓ enabled
  timer        : ✓ active
  service      : ✓ inactive
  last check   : ✓ pass
  next run     : 00h 04m 12s left
────────────────────────────────────────────────────────
  tool         : gc-hc 2.0.0
  mode         : system
  binary       : /usr/bin/gc-hc
  config       : /etc/gc-hc/env
  state        : /var/lib/gc-hc/last.json
  log          : /var/log/gc-hc/gc-hc.log
────────────────────────────────────────────────────────
```

Run yang fail nulis alasan spesifik — bukan cuma "fail":

| Check        | State | Message                |
| ------------ | ----- | ---------------------- |
| `prom.dns`   | pass  | resolved               |
| `prom.tls`   | pass  | handshake_ok           |
| `prom.push`  | pass  | reachable_http_400     |
| `prom.query` | pass  | http_200               |
| `loki.write` | fail  | auth_http_401          |
| `fleet`      | skip  | disabled               |

`loki.write: auth_http_401` itu intinya — lu langsung tahu masalahnya di API key, bukan di DNS, bukan di firewall.

Exit code mengikuti verdict: `0` kalau semua PASS, `1` kalau ada WARN, `2` kalau ada FAIL. Bisa langsung dipasang ke alerting.

### Konfigurasi

Disimpan di `/etc/gc-hc/env` (system mode) atau `./.gc-hc/env` (standalone). Flow `onboard` akan nuntun lu lewat semua field.

| Variabel                         | Wajib    | Penjelasan                                              |
| -------------------------------- | :------: | ------------------------------------------------------- |
| `GCLOUD_HOSTED_METRICS_URL`      | ya       | URL Prometheus `remote_write` (`/api/prom/push`)        |
| `GCLOUD_HOSTED_METRICS_ID`       | ya       | Numeric Prometheus instance ID                          |
| `GCLOUD_HOSTED_LOGS_URL`         | ya       | URL Loki push                                           |
| `GCLOUD_HOSTED_LOGS_ID`          | ya       | Numeric Loki instance ID                                |
| `GCLOUD_RW_API_KEY`              | ya       | Grafana Cloud API key (harus mulai dengan `glc_`)       |
| `GCLOUD_FM_URL`                  | opsional | Fleet Management endpoint                               |
| `GC_HC_INTERVAL`                 | opsional | Interval timer (1m, 5m, 15m, 1h; default `5m`)          |
| `GC_HC_TIMEOUT`                  | opsional | Timeout curl, detik (1–300, default 10)                 |
| `GC_HC_RETRIES`                  | opsional | Curl retries (default 2)                                |
| `GC_HC_RETRY_DELAY`              | opsional | Curl retry delay, detik (default 2)                     |
| `GC_HC_DNS` / `GC_HC_TLS`        | opsional | `false` untuk disable probe                             |
| `GC_HC_LOKI_WRITE`               | opsional | `false` untuk skip Loki write probe                     |
| `GC_HC_PROM_QUERY`               | opsional | `false` untuk skip Prometheus query probe               |
| `GC_HC_FLEET`                    | opsional | `false` untuk skip Fleet probe                          |
| `GC_HC_LOG_RETENTION`            | opsional | Retention umur check log (`24h` default, `0` disable)   |
| `GC_HC_LOG_KEEP`                 | opsional | Fallback last N entry check yang disimpan (default 100) |
| `GC_HC_TRACE`                    | opsional | `auto` (default), `always`, atau `never` — auto-traceroute saat probe fail |
| `GC_HC_TRACE_TOOL`               | opsional | `auto` (default), `traceroute`, atau `tracepath`        |
| `GC_HC_TRACE_TIMEOUT`            | opsional | Timeout per hop, detik (default 2)                      |
| `GC_HC_TRACE_MAX_HOPS`           | opsional | Abort setelah N hop (default 15)                        |
| `GC_HC_TRACE_LOG_RETENTION`      | opsional | Retention umur trace log (`24h` default, `0` disable)   |
| `GC_HC_TRACE_LOG_KEEP`           | opsional | Fallback last N entry per probe log (default 50)        |

Kalau lu udah jalanin [Grafana Alloy](https://grafana.com/docs/alloy/latest/) dan variabel yang sama sudah di-set di `/etc/default/alloy` atau `/etc/sysconfig/alloy`, `gc-hc` akan otomatis pakai itu.

File config mode `0600` dan API key di-mask di mana pun di-print (`status`, `config show`).

Notifikasi email SMTP disimpan terpisah di `/etc/gc-hc/mail.env` (system mode) atau `./.gc-hc/mail.env` (standalone), supaya credential email tidak campur dengan config healthcheck utama:

```bash
sudo gc-hc config smtp
gc-hc config smtp --test        # default test verdict: fail
gc-hc config smtp --test warn   # custom test verdict: warn/pass/fail
```

Contoh setup non-interactive:

```bash
sudo GC_HC_MAIL_ENABLED=true \
  GC_HC_MAIL_ON=change \
  GC_HC_MAIL_PROVIDER=gmail \
  GC_HC_MAIL_TO=ops@example.com \
  GC_HC_MAIL_FROM=gc@example.com \
  GC_HC_MAIL_USER=gc@example.com \
  GC_HC_MAIL_PASS=abcdefghijklmnop \
  gc-hc config smtp --yes
```

`GC_HC_MAIL_PASS` disimpan di `mail.env`, jadi file itu mode `0600` dan harus dianggap secret. `config show` cuma print `GC_HC_MAIL_PASS=(set)`. Pakai comma-separated `GC_HC_MAIL_TO` untuk banyak recipient. Delivery memakai `msmtp`; install dengan:

```bash
sudo apt-get install -y msmtp ca-certificates
```

Jalankan `gc-hc config smtp --test` setelah SMTP config ada untuk mengirim test message.

### Cara kerja

```
                ┌─────────────────────────────────────┐
                │  curl ... | sudo bash               │
                │  (script self-contained satu file)  │
                └──────────────┬──────────────────────┘
                               │
                               ▼
                ┌─────────────────────────────────────┐
                │  installer (gc-hc.sh)               │
                │   • bikin .deb di /var/tmp          │
                │   • apt-get install ./*.deb         │
                └──────────────┬──────────────────────┘
                               │
              ┌────────────────┴────────────────────┐
              ▼                                     ▼
   /usr/bin/gc-hc                    /lib/systemd/system/
   /usr/bin/gchc                       gc-hc.service
                                       gc-hc.timer
              │                                     │
              └────────────────┬────────────────────┘
                               ▼
                ┌─────────────────────────────────────┐
                │  gc-hc check  (default tiap 5m)     │
                │    DNS → TLS → prom → loki → fleet  │
                └──────────────┬──────────────────────┘
                               ▼
                /var/lib/gc-hc/last.json
                /var/log/gc-hc/gc-hc.log
```

Installer-nya satu file. Tool runtime-nya script terpisah yang ke-embed di dalamnya. Service dan timer unit, plus maintainer script `postinst`/`prerm`/`postrm`, juga ke-embed — pas install kita materialize ke disk dan biarkan `dpkg` yang tracking.

Itu kenapa `apt-get remove` tahu semua file yang di-install: setiap file di-own oleh package `gc-hc`, by design.

### Build sendiri

```bash
git clone https://github.com/naufalmng/gc-hc
cd gc-hc
make build           # → dist/gc-hc.sh, dist/gc-hc
make test            # smoke + bats
make install         # install lokal via apt-get
```

**Layout source:**

```
gc-hc/
├── src/
│   ├── tool/         # 15 modul — runtime healthcheck
│   └── installer/    # 9 modul — .deb builder + apt installer
├── assets/
│   ├── systemd/      # service + timer unit
│   ├── debian/       # postinst, prerm, postrm, control template
│   └── banner/       # ASCII banner
├── scripts/build.sh  # assemble dist artifact
├── tests/
│   ├── bats/         # unit test (pure function)
│   ├── smoke.sh      # quick assertion, tanpa dependency eksternal
│   └── parity.sh     # verify built artifact retain semua kontrak
└── .github/workflows/  ci.yml + release.yml
```

Build pipeline-nya nge-concat module sumber dalam urutan leksikal, embed asset file via heredoc placeholder, dan substitute `__PACKAGE_VERSION__`, `__PACKAGE_MAINTAINER__`, `__PACKAGE_HOMEPAGE__` dari `VERSION` + environment override.

### Pilihan desain

- **No jq dependency.** JSON hasil di-assemble dengan `json_escape` pure-bash. Healthcheck harus tetap jalan di Debian image yang minimal banget.
- **Pakai `/dev/tty` buat prompt.** Itu yang bikin `curl ... | sudo bash` tetap interaktif — stdin sudah ke-occupy pipe, tapi terminal user masih nyangkut di `/dev/tty`.
- **API key di-mask by default.** `config show` dan `status` cuma nampilin `glc_xx...yyyy`; nilai aslinya ga pernah keluar dari `/etc/gc-hc/env` (mode `0600`).
- **400 = pass untuk `remote_write` body kosong.** Mimir/Cortex jawab 400 ke POST protobuf kosong kalau auth-nya bener, dan itu probe paling murah buat verify reachable+authed — di-annotate eksplisit di hasil.
- **Verdict precedence: FAIL > WARN > PASS.** Exit code mirror itu: `0/1/2`. Tinggal pasang ke alerting.
- **Satu artifact, dua lifecycle.** Script yang sama bisa build `.deb` (system mode) atau drop binary self-contained (standalone mode). Source sama, entry install beda.

### Troubleshooting

**`config missing, run: gc-hc config`** — `/etc/gc-hc/env` ga ada, dan ga ada Alloy fallback yang bisa dipakai. Jalankan `sudo gc-hc onboard`.

**`GCLOUD_RW_API_KEY must start with glc_`** — Grafana Cloud API key selalu mulai dengan `glc_`. Kalau punya lu beda, kemungkinan itu credential tipe lain (SA token, dll). Generate Access Policy token yang proper dengan scope `metrics:write` dan `logs:write`.

**`prom.push: auth_http_401`** — credential salah, atau metrics ID ga match dengan region/stack URL.

**`loki.write: bad_payload_http_400`** — Loki endpoint terima auth tapi reject test payload. Paling sering ini region/URL mismatch — Loki lain terima credential-nya tapi schema body-nya beda. Pastiin `GCLOUD_HOSTED_LOGS_URL` match dengan stack lu.

**`*.dns: lookup_failed`** — DNS broken di host. Cek `/etc/resolv.conf`, status `systemd-resolved`, atau split-horizon DNS. Ga ada hubungannya sama credential.

**`*.tls: handshake_failed`** — HTTPS outbound ke Grafana Cloud ke-intercept, ke-MITM, atau diblok firewall. `openssl s_client -connect <host>:443` bakal kasih jawaban yang sama dengan detail lebih banyak.

**`prom.query: reachable_http_404`** — buildinfo endpoint ga ada di lokasi yang kita expect. Mimir/Cortex self-hosted atau versi lama kadang routing-nya beda. Status 404 di-treat sebagai "reachable tapi ga ada buildinfo" — bukan fail.
