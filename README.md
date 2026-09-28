<div align="center">

# 🩸 RECON-CHAIN

### **Automated recon pipeline — from a single domain to exploitable endpoints.**

<img src="https://img.shields.io/badge/bash-%3E%3D%204.0-8B0000?style=for-the-badge&logo=gnu-bash&logoColor=white" />
<img src="https://img.shields.io/badge/linux-kali%20%7C%20debian-8B0000?style=for-the-badge&logo=linux&logoColor=white" />
<img src="https://img.shields.io/badge/subfinder-recon-8B0000?style=for-the-badge" />
<img src="https://img.shields.io/badge/httpx-probing-8B0000?style=for-the-badge" />
<img src="https://img.shields.io/badge/nuclei-vuln%20scan-8B0000?style=for-the-badge" />
<img src="https://img.shields.io/badge/katana-crawling-8B0000?style=for-the-badge" />
<img src="https://img.shields.io/badge/dalfox-xss-8B0000?style=for-the-badge" />
<img src="https://img.shields.io/badge/sqlmap-sqli-8B0000?style=for-the-badge" />
<img src="https://img.shields.io/badge/license-MIT-8B0000?style=for-the-badge" />

<br />
<br />

**One script. Seven tools. Full recon.**

`subfinder` → `httpx` → `nuclei` → `katana` → `ffuf` → `dalfox` → `sqlmap`

<br />

[Features](#-features) · [Pipeline](#-pipeline) · [Install](#-installation) · [Usage](#-usage) · [Queue](#-queue-system) · [Reports](#-report-structure) · [FAQ](#-faq)

</div>

---

## 🩸 What is this

**recon-chain** is a single Bash script that wraps seven industry-standard recon and vulnerability scanning tools into one coherent pipeline, with a queue system, timestamped reports, colored output and sane defaults.

Feed it a domain. Get back a folder full of subdomains, live hosts, endpoints, parameters and potential vulnerabilities — organized and ready to triage.

No Python environment. No `pip install`. No cloud. Just `git clone` and go.

---

## ⚔️ Features

- 🩸 **7-stage pipeline** — subdomain enumeration, live host probing, vulnerability scan, JS-aware crawling, directory fuzzing, XSS and SQL injection.
- 🎯 **Queue system** — scan dozens of targets one after another, unattended.
- 🧠 **Smart input handling** — accepts `example.com`, `https://example.com/`, `127.0.0.1:3000`, `http://host:port/`. Normalizes everything automatically.
- 🕷️ **Headless crawling** — katana runs with `-hl -nos`, so it renders JavaScript and works against SPAs (OWASP Juice Shop, Angular, React, Vue).
- 🛡️ **Single-host safe** — the root domain is always included in the subdomain list, even if `subfinder` returns nothing. No more empty pipelines.
- 🎛️ **Optional stages** — turn off what you don't need: `--no-nuclei`, `--with-ffuf`, `--with-sqlmap`.
- 🔧 **Kali-aware** — auto-detects `httpx` vs `httpx-toolkit`, `$GOPATH/bin`, `/root/go/bin`, `/usr/local/bin`. No PATH wrestling.
- 📁 **Timestamped reports** — every run gets its own folder with a `summary.txt`.
- 📝 **Logging** — every command and exit code logged to `~/.local/share/recon-chain/`.
- 🎨 **Colored output** — clean, readable, auto-disabled when piped to a file.

---

## 🗡️ Pipeline

```
                         ┌──────────────┐
                         │    DOMAIN    │
                         └──────┬───────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │  [1]  subfinder       │
                    │  ─ subdomains.txt     │
                    └───────────┬───────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │  [2]  httpx           │
                    │  ─ live_hosts.txt     │
                    │  ─ urls.txt           │
                    └───────────┬───────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌──────────────┐      ┌──────────────┐      ┌──────────────────┐
│ [3]  nuclei  │      │ [4]  katana  │      │ [5]  ffuf        │
│ vuln scan    │      │ crawl        │      │ dir fuzz         │
│              │      │              │      │ (--with-ffuf)    │
│ ─ findings   │      │ ─ endpoints  │      │ ─ findings       │
└──────────────┘      └──────┬───────┘      └──────────────────┘
                             │
                             ▼
                    ┌───────────────────┐
                    │  [6]  dalfox      │
                    │  XSS on params    │
                    │  ─ xss_findings   │
                    └─────────┬─────────┘
                              │
                              ▼
                    ┌───────────────────┐
                    │  [7]  sqlmap      │
                    │  SQLi on params   │
                    │  (--with-sqlmap)  │
                    │  ─ sqlmap_findings│
                    └─────────┬─────────┘
                              │
                              ▼
                       ┌─────────────┐
                       │ summary.txt │
                       └─────────────┘
```

Every stage is optional in the sense that if it produces nothing, the pipeline continues gracefully — no crashes, no missing files, no broken summary.

---

## 📦 Installation

### 1. Clone the repo

```bash
git clone https://github.com/lexapypsik10/recon-chain.git
cd recon-chain
chmod +x recon-chain.sh
```

### 2. Install dependencies

**Debian / Kali / Ubuntu:**

```bash
sudo apt update
sudo apt install -y ffuf sqlmap chromium golang-go
```

**ProjectDiscovery + dalfox (Go tools):**

```bash
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/projectdiscovery/katana/cmd/katana@latest
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install -v github.com/hahwul/dalfox/v2@latest

# Make sure $GOPATH/bin is in PATH
export PATH="$PATH:$(go env GOPATH)/bin"
echo 'export PATH="$PATH:$(go env GOPATH)/bin"' >> ~/.bashrc
```

### 3. Update nuclei templates (one-time)

```bash
nuclei -update-templates
```

### 4. Verify

```bash
./recon-chain.sh tools
```

You should see resolved paths for every tool. If something shows `<not found>` — that tool will be skipped gracefully.

---

## 🩸 Usage

### Basic — full pipeline

```bash
./recon-chain.sh run example.com
./recon-chain.sh run https://example.com/
./recon-chain.sh run 127.0.0.1.nip.io:3000
./recon-chain.sh run http://127.0.0.1:8080/
```

All four input formats work identically — the script normalizes them.

### With optional stages

```bash
# Enable heavy stages
./recon-chain.sh run example.com --with-ffuf --with-sqlmap

# Skip nuclei for a fast run
./recon-chain.sh run example.com --no-nuclei

# Slow down for fragile targets
./recon-chain.sh run example.com --rate-limit 30

# Crawl deeper
./recon-chain.sh run example.com --depth 5
```

### Individual stages

```bash
./recon-chain.sh subs example.com      # subdomain enumeration only
./recon-chain.sh live example.com      # + live host probing
./recon-chain.sh urls example.com      # + URL crawling
./recon-chain.sh xss  example.com      # + XSS scanning
```

### Utilities

```bash
./recon-chain.sh tools      # show resolved binary paths
./recon-chain.sh reports    # list all report folders
./recon-chain.sh --help     # full help
```

---

## 📋 Queue System

Scan multiple targets sequentially:

```bash
./recon-chain.sh queue add example.com
./recon-chain.sh queue add test.com
./recon-chain.sh queue add 127.0.0.1.nip.io:3000

./recon-chain.sh queue list
# == QUEUE ==
#  1. example.com
#  2. test.com
#  3. 127.0.0.1.nip.io:3000

./recon-chain.sh queue run       # run all, one after another
./recon-chain.sh queue clear     # wipe the queue
```

The queue is stored as plain text in `~/.local/share/recon-chain/queue.txt` — you can edit it by hand.

---

## 📁 Report Structure

Every run creates a timestamped folder under `$REPORT_ROOT` (default `~/recon-chain/reports/`):

```
<target>_<YYYYMMDD_HHMMSS>/
├── subdomains.txt         ← raw subfinder output + root domain
├── live_hosts.txt         ← httpx output (status, title, tech)
├── urls.txt               ← clean URLs extracted from live_hosts
├── nuclei_findings.txt    ← vulnerabilities detected by nuclei
├── crawl_urls.txt         ← raw katana output
├── endpoints.txt          ← sorted unique endpoints
├── params.txt             ← URLs with query parameters
├── ffuf_findings.txt      ← directory fuzzing results (optional)
├── xss_findings.txt       ← XSS findings from dalfox
├── sqlmap_findings.txt    ← SQLi findings from sqlmap (optional)
├── sqlmap_out/            ← full sqlmap session dumps
└── summary.txt            ← counts for every stage
```

Example `summary.txt`:

```
Recon summary for 127.0.0.1.nip.io:3000
Generated:     2026-09-28 17:44:40
Subdomains:    1
Live hosts:    1
Nuclei finds:  0
Endpoints:     41
FFUF finds:    0
XSS finds:     0
SQLi params:   0
```

---

## ⚙️ Configuration

Optional config file at `~/.config/recon-chain.conf`:

```bash
# Where reports are stored
REPORT_ROOT="$HOME/recon-chain/reports"

# Requests per second
RATE_LIMIT=150

# Crawl depth for katana
DEPTH=3

# Toggle stages (0 = off, 1 = on)
WITH_NUCLEI=1
WITH_FFUF=0
WITH_SQLMAP=0

# Nuclei severity filter
NUCLEI_SEVERITY="critical,high,medium"

# sqlmap settings
SQLMAP_LEVEL=1
SQLMAP_RISK=1

# ffuf wordlist
FFUF_WORDLIST="/usr/share/wordlists/dirb/common.txt"
```

Tighten permissions:

```bash
chmod 600 ~/.config/recon-chain.conf
```

---

## 🧪 Verified On

**OWASP Juice Shop** via `127.0.0.1.nip.io:3000`:

- katana discovered **41 endpoints**, including `/rest/products/search?q=` and `/api/Challenges/`
- scan triggered Juice Shop's built-in **"Error Handling"** and **"Repetitive Registration"** challenges
- headless mode (`-hl -nos`) successfully rendered the Angular SPA

**The Range** (`the-range.appsec.study`):

- 14 intentionally vulnerable challenges
- pipeline picks up all reachable endpoints and parameterized URLs

---

## ❓ FAQ

<details>
<summary><b>Do I need root?</b></summary>

Only for `ffuf` on privileged ports and `sqlmap` when using `--os-shell`. For normal recon — no.

</details>

<details>
<summary><b>Why is httpx on Kali broken?</b></summary>

Kali ships two `httpx` binaries: the Python library and the ProjectDiscovery Go tool. The Python one shadows the Go one in `$PATH`. `recon-chain` resolves this automatically — it looks for `httpx-toolkit` first, then `$GOPATH/bin/httpx`, then `PATH`.

</details>

<details>
<summary><b>Why does Juice Shop crash after a few minutes?</b></summary>

Juice Shop is a deliberately fragile teaching app. Under aggressive automated scanning it drops and restarts with a fresh database — that's by design. Run with `--rate-limit 30` to make it survive longer, or use The Range / DVWA / WebGoat for stable targets.

</details>

<details>
<summary><b>Can I add more stages?</b></summary>

Yes — edit the script and add a `stage_<name>()` function, then call it inside `run_full()`. The pattern is consistent.

</details>

<details>
<summary><b>Does it work on macOS?</b></summary>

The script itself is portable bash. The tools (`subfinder`, `httpx`, etc.) work on macOS too, installed via `brew`. Chromium for headless katana is auto-downloaded.

</details>

---

## 🛡️ Legal

**Only scan targets you have explicit permission to test.**

- Your own infrastructure
- Bug bounty programs within their scope
- Deliberately vulnerable labs: OWASP Juice Shop, The Range, DVWA, WebGoat, HackTheBox, TryHackMe

Scanning third-party systems without authorization is illegal in most jurisdictions.

---

## 🤝 Contributing

Pull requests welcome.

1. Fork the repo
2. Create a branch: `git checkout -b feature/my-change`
3. Run `shellcheck recon-chain.sh` before committing
4. Keep the style: 4-space indent, `set -uo pipefail`, colors via `$'\033…'`, helpers named `box_line` / `box_rule` / `die` / `warn` / `ok`
5. Open a PR with a clear description

---

## 📄 License

MIT — see [LICENSE](LICENSE).

<div align="center">

<br />

**🩸 Stay in the red. Hack responsibly. 🩸**

<br />

<img src="https://img.shields.io/badge/made%20with-bash-8B0000?style=for-the-badge&logo=gnu-bash&logoColor=white" />

</div>
