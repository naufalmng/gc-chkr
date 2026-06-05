
     ▄████   ▄████        ██   ██  ▄████
    ██       ██           ██   ██ ██
    ██  ▄▄   ██           ███████ ██
    ██  ██   ██           ██   ██ ██
     ▀████    ▀████  ▄    ██   ██  ▀████

**Grafana Cloud Health Checker** — reverse healthcheck CLI for validating Grafana Cloud reachability from the node-side.

[![CI](https://github.com/naufalmng/gc-hc/actions/workflows/ci.yml/badge.svg)](https://github.com/naufalmng/gc-hc/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/naufalmng/gc-hc?display_name=tag&sort=semver)](https://github.com/naufalmng/gc-hc/releases)
[![License](https://img.shields.io/github/license/naufalmng/gc-hc)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-1f425f.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-debian%20%7C%20ubuntu-d70a53)](#install)

</div>

---

## English

When Grafana Cloud says *"no data"*, everyone starts pointing fingers. `gc-hc` runs from the node and checks the usual suspects — DNS, TLS, auth, firewall rules, and endpoint URLs — so you can stop guessing and start fixing.

### Install / Update

```bash
curl -fsSL https://github.com/naufalmng/gc-hc/releases/latest/download/gc-hc.sh | sudo bash
```

### Quick start

```bash
sudo gc-hc onboard       # configure + enable timer + first check
gchc check               # run a check on demand
gchc status              # see current state and last result
gchc config show         # show core + mail config with secrets masked
sudo gc-hc config smtp   # optional SMTP mail notifications
gchc --help              # full command reference
sudo apt-get remove gc-hc
```

`gchc` is a short alias for `gc-hc` — same command, fewer keystrokes.

When a probe fails, `gc-hc` automatically runs a traceroute to the affected host, so the path is captured directly in the logs without requiring manual troubleshooting. Once the probe recovers, `gc-hc` resets the state and stops running traceroutes until the next failure.

For full usage, configuration reference, architecture, and design notes, see **[documentation.md](documentation.md)**.

---

## Bahasa Indonesia

Kalau Grafana Cloud bilang *"no data"*, biasanya semua mulai saling tuduh. `gc-hc` jalan dari sisi node dan ngecek tersangka utama — DNS, TLS, auth, firewall, dan URL endpoint — supaya lo bisa stop nebak-nebak dan mulai benerin masalahnya.

### Instalasi / Pembaharuan

```bash
curl -fsSL https://github.com/naufalmng/gc-hc/releases/latest/download/gc-hc.sh | sudo bash
```

### Quick start

```bash
sudo gc-hc onboard       # konfigurasi + aktifkan timer + jalankan check pertama
gchc check               # jalankan check kapan saja
gchc status              # lihat state dan hasil terakhir
gchc config show         # lihat core + mail config dengan secret di-mask
sudo gc-hc config smtp   # opsional: notifikasi email SMTP
gchc --help              # referensi command lengkap
sudo apt-get remove gc-hc
```

`gchc` adalah alias pendek untuk `gc-hc` — perintah sama, lebih ringkas.

Kalau ada probe yang gagal, gc-hc otomatis menjalankan traceroute ke host yang bermasalah, jadi jalurnya langsung masuk ke log tanpa perlu tracing manual. Setelah probe pulih, gc-hc akan mereset statusnya dan berhenti menjalankan traceroute sampai kegagalan berikutnya.

Untuk panduan lengkap, referensi konfigurasi, arsitektur, dan catatan desain, lihat **[documentation.md](documentation.md)**.

---

## License / Lisensi

Apache License 2.0. See [LICENSE](LICENSE).

## Author / Penulis

[Muhammad Naufal Hanif](https://github.com/naufalmng) — built this to stop guessing why Grafana Cloud was silent on certain hosts.
