#!/usr/bin/env bash
# ============================================================
#  recon-chain.sh
#  Automated recon pipeline:
#  subfinder → httpx → nuclei → katana → ffuf → dalfox → sqlmap
#
#  Author : lexapypsik10
#  License: MIT
# ============================================================

set -uo pipefail

# ---------- Config ----------
CONFIG_FILE="${RECON_CHAIN_CONFIG:-$HOME/.config/recon-chain.conf}"
# shellcheck disable=SC1090
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

REPORT_ROOT="${REPORT_ROOT:-$HOME/recon-chain/reports}"
QUEUE_FILE="${QUEUE_FILE:-$HOME/.local/share/recon-chain/queue.txt}"
LOG_FILE="${LOG_FILE:-$HOME/.local/share/recon-chain/recon-chain.log}"

RATE_LIMIT="${RATE_LIMIT:-150}"
DEPTH="${DEPTH:-3}"
WITH_NUCLEI="${WITH_NUCLEI:-1}"
WITH_FFUF="${WITH_FFUF:-0}"
WITH_SQLMAP="${WITH_SQLMAP:-0}"
NUCLEI_SEVERITY="${NUCLEI_SEVERITY:-critical,high,medium}"
NUCLEI_TIMEOUT="${NUCLEI_TIMEOUT:-5}"
SQLMAP_LEVEL="${SQLMAP_LEVEL:-1}"
SQLMAP_RISK="${SQLMAP_RISK:-1}"
FFUF_WORDLIST="${FFUF_WORDLIST:-/usr/share/wordlists/dirb/common.txt}"

mkdir -p "$REPORT_ROOT" "$(dirname "$QUEUE_FILE")" "$(dirname "$LOG_FILE")"
touch "$QUEUE_FILE" "$LOG_FILE"

# ---------- Tool resolution ----------
GOPATH_BIN="$(go env GOPATH 2>/dev/null)/bin"
[[ -d "$GOPATH_BIN" ]] || GOPATH_BIN=""

resolve_tool() {
    local name="$1" alias1="${2:-}" alias2="${3:-}"
    local candidates=()

    [[ -n "$alias1" ]] && candidates+=("$alias1")
    [[ -n "$alias2" ]] && candidates+=("$alias2")
    [[ -n "$GOPATH_BIN" ]] && candidates+=("$GOPATH_BIN/$name")
    candidates+=(
        "/root/go/bin/$name"
        "/usr/local/bin/$name"
        "/usr/bin/$name"
        "$HOME/go/bin/$name"
    )

    local c
    for c in "${candidates[@]}"; do
        if [[ -x "$c" ]] && "$c" --help >/dev/null 2>&1; then
            printf '%s' "$c"; return 0
        fi
        if [[ -x "$c" ]] && "$c" -h >/dev/null 2>&1; then
            printf '%s' "$c"; return 0
        fi
    done

    if command -v "$name" >/dev/null 2>&1; then
        printf '%s' "$(command -v "$name")"
        return 0
    fi
    return 1
}

SUBFINDER_BIN="$(resolve_tool subfinder || true)"
HTTPX_BIN="$(resolve_tool httpx httpx-toolkit || true)"
KATANA_BIN="$(resolve_tool katana || true)"
DALFOX_BIN="$(resolve_tool dalfox || true)"
NUCLEI_BIN="$(resolve_tool nuclei || true)"
FFUF_BIN="$(resolve_tool ffuf || true)"
SQLMAP_BIN="$(resolve_tool sqlmap || true)"

# ---------- Colors ----------
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
    CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
    RED=""; GREEN=""; YELLOW=""; CYAN=""; BOLD=""; NC=""
fi

log()  { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"; }
die()  { printf '%s[-] %s%s\n' "$RED" "$*" "$NC" >&2; exit 1; }
warn() { printf '%s[!] %s%s\n' "$YELLOW" "$*" "$NC"; }
ok()   { printf '%s[+] %s%s\n' "$GREEN" "$*" "$NC"; }

strip_ansi() { sed -E 's/\x1b\[[0-9;]*m//g'; }

box_line() {
    local text="$1" width="$2"
    local visible len pad
    visible=$(printf '%s' "$text" | strip_ansi)
    len=${#visible}
    pad=$(( width - len - 2 ))
    (( pad < 0 )) && pad=0
    printf '%s|%s %b%*s %s|%s\n' "$CYAN" "$NC" "$text" "$pad" "" "$CYAN" "$NC"
}

box_rule() {
    local width="$1"
    printf '%s+%s+%s\n' "$CYAN" "$(printf '%*s' "$width" '' | tr ' ' '=')" "$NC"
}

# ---------- Help ----------
show_help() {
    local W=96
    echo
    box_rule "$W"
    box_line "${BOLD}${YELLOW}RECON-CHAIN.SH — FULL RECON PIPELINE${NC}" "$W"
    box_rule "$W"
    box_line "" "$W"
    box_line "${GREEN}PIPELINE:${NC} subfinder → httpx → nuclei → katana → ffuf → dalfox → sqlmap" "$W"
    box_line "" "$W"
    box_line "${GREEN}USAGE:${NC}   ./recon-chain.sh <command> [target] [options]" "$W"
    box_line "" "$W"
    box_line "${GREEN}COMMANDS:${NC}" "$W"
    box_line "   run <target>              full recon on a target" "$W"
    box_line "   subs <domain>             subdomain enumeration only" "$W"
    box_line "   live <target>             live host probing only" "$W"
    box_line "   urls <target>             collect URLs (katana)" "$W"
    box_line "   xss <target>              XSS scanning only" "$W"
    box_line "   tools                     show resolved tool paths" "$W"
    box_line "   queue add <target>        add target to queue" "$W"
    box_line "   queue list                show queue" "$W"
    box_line "   queue run                 run all queued targets" "$W"
    box_line "   queue clear               clear queue" "$W"
    box_line "   reports                   list all report folders" "$W"
    box_line "" "$W"
    box_line "${GREEN}INPUT FORMATS:${NC}" "$W"
    box_line "   example.com               domain (subfinder + root always included)" "$W"
    box_line "   https://example.com/      URL (normalized, subfinder skipped)" "$W"
    box_line "   127.0.0.1:3000            host:port (subfinder skipped)" "$W"
    box_line "   http://127.0.0.1:8080/    full URL (subfinder skipped)" "$W"
    box_line "" "$W"
    box_line "${GREEN}OPTIONS for run:${NC}" "$W"
    box_line "   --with-ffuf               enable ffuf directory fuzzing" "$W"
    box_line "   --with-sqlmap             enable sqlmap SQLi scanning" "$W"
    box_line "   --no-nuclei               skip nuclei" "$W"
    box_line "   --rate-limit N            requests per second (default: 150)" "$W"
    box_line "   --depth N                 crawl depth (default: 3)" "$W"
    box_line "" "$W"
    box_line "${GREEN}CONFIG:${NC} ~/.config/recon-chain.conf" "$W"
    box_rule "$W"
    echo
}

# ---------- Preflight ----------
require_tools() {
    local missing=()
    [[ -z "$SUBFINDER_BIN" ]] && missing+=("subfinder")
    [[ -z "$HTTPX_BIN"    ]] && missing+=("httpx (go version)")
    [[ -z "$KATANA_BIN"   ]] && missing+=("katana")
    [[ -z "$DALFOX_BIN"   ]] && missing+=("dalfox")
    (( WITH_NUCLEI == 1 )) && [[ -z "$NUCLEI_BIN" ]] && missing+=("nuclei")
    (( WITH_FFUF == 1 ))   && [[ -z "$FFUF_BIN"   ]] && missing+=("ffuf")
    (( WITH_SQLMAP == 1 )) && [[ -z "$SQLMAP_BIN" ]] && missing+=("sqlmap")

    if (( ${#missing[@]} > 0 )); then
        die "missing tools: ${missing[*]}. Install them or disable with flags."
    fi
}

show_tools() {
    echo "${CYAN}Resolved tool paths:${NC}"
    printf '  subfinder : %s\n' "${SUBFINDER_BIN:-<not found>}"
    printf '  httpx     : %s\n' "${HTTPX_BIN:-<not found>}"
    printf '  katana    : %s\n' "${KATANA_BIN:-<not found>}"
    printf '  dalfox    : %s\n' "${DALFOX_BIN:-<not found>}"
    printf '  nuclei    : %s\n' "${NUCLEI_BIN:-<not found>}"
    printf '  ffuf      : %s\n' "${FFUF_BIN:-<not found>}"
    printf '  sqlmap    : %s\n' "${SQLMAP_BIN:-<not found>}"
}

# ---------- Stage 1: subdomains ----------
stage_subs() {
    local domain="$1" outdir="$2"
    echo "${CYAN}[1/7] Subdomain enumeration...${NC}"
    log "SUBS: $domain"

    local norm="$domain"
    norm="${norm#http://}"
    norm="${norm#https://}"
    norm="${norm%/}"

    if [[ "$domain" =~ ^https?:// ]]; then
        warn "    input is URL, skipping subfinder"
        printf 'http://%s\n' "$norm" >"$outdir/subdomains.txt"
        return 0
    fi

    if [[ "$norm" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]] || [[ "$norm" =~ :[0-9]+$ ]]; then
        warn "    input is host:port, skipping subfinder"
        printf 'http://%s\n' "$norm" >"$outdir/subdomains.txt"
        return 0
    fi

    "$SUBFINDER_BIN" -d "$norm" -silent -o "$outdir/subdomains.txt" 2>/dev/null || true
    [[ -f "$outdir/subdomains.txt" ]] || : >"$outdir/subdomains.txt"

    if ! grep -qxF "$norm" "$outdir/subdomains.txt"; then
        printf '%s\n' "$norm" >>"$outdir/subdomains.txt"
    fi

    local count; count=$(wc -l <"$outdir/subdomains.txt")
    ok "    found: $count hosts (subdomains + root)"
}

# ---------- Stage 2: httpx ----------
stage_live() {
    local outdir="$1"
    echo "${CYAN}[2/7] Live host probing...${NC}"
    log "LIVE: probing"

    if [[ ! -s "$outdir/subdomains.txt" ]]; then
        warn "    no hosts, skipping"
        : >"$outdir/live_hosts.txt"; : >"$outdir/urls.txt"
        return 1
    fi

    "$HTTPX_BIN" -l "$outdir/subdomains.txt" -silent \
        -title -status-code -tech-detect \
        -ports 80,443,3000,5000,8000,8080,8443,9000 \
        -o "$outdir/live_hosts.txt" 2>/dev/null || true

    [[ -f "$outdir/live_hosts.txt" ]] || : >"$outdir/live_hosts.txt"

    grep -oE 'https?://[^ ]+' "$outdir/live_hosts.txt" | sort -u >"$outdir/urls.txt" || true

    if [[ ! -s "$outdir/urls.txt" ]] && [[ -s "$outdir/live_hosts.txt" ]]; then
        awk '{print $1}' "$outdir/live_hosts.txt" \
            | grep -E '^[a-zA-Z0-9.-]+(:[0-9]+)?$' \
            | sed -E 's|^|http://|' \
            | sort -u >"$outdir/urls.txt" || true
    fi

    [[ -f "$outdir/urls.txt" ]] || : >"$outdir/urls.txt"

    local count; count=$(wc -l <"$outdir/live_hosts.txt")
    ok "    live: $count hosts"
    if [[ -s "$outdir/urls.txt" ]]; then
        ok "    urls: $(wc -l <"$outdir/urls.txt")"
    fi
}

# ---------- Stage 3: nuclei ----------
stage_nuclei() {
    local outdir="$1"
    echo "${CYAN}[3/7] Nuclei vulnerability scan...${NC}"
    log "NUCLEI: starting"

    if (( WITH_NUCLEI == 0 )); then warn "    disabled"; : >"$outdir/nuclei_findings.txt"; return 0; fi
    if [[ ! -s "$outdir/urls.txt" ]]; then
        warn "    no URLs, skipping"; : >"$outdir/nuclei_findings.txt"; return 1
    fi

    "$NUCLEI_BIN" -list "$outdir/urls.txt" \
        -severity "$NUCLEI_SEVERITY" \
        -rate-limit "$RATE_LIMIT" \
        -timeout "$NUCLEI_TIMEOUT" -retries 1 \
        -silent -no-color \
        -o "$outdir/nuclei_findings.txt" 2>/dev/null || true

    [[ -f "$outdir/nuclei_findings.txt" ]] || : >"$outdir/nuclei_findings.txt"
    local count; count=$(wc -l <"$outdir/nuclei_findings.txt")
    ok "    findings: $count"
}

# ---------- Stage 4: katana ----------
stage_crawl() {
    local outdir="$1"
    echo "${CYAN}[4/7] Live crawl (katana)...${NC}"
    log "CRAWL: starting"

    if [[ ! -s "$outdir/urls.txt" ]]; then
        warn "    no live URLs, skipping"
        : >"$outdir/crawl_urls.txt"; : >"$outdir/endpoints.txt"
        return 1
    fi

    "$KATANA_BIN" -list "$outdir/urls.txt" -silent \
        -jc -hl -nos -d "$DEPTH" -rl "$RATE_LIMIT" \
        -o "$outdir/crawl_urls.txt" 2>/dev/null || true

    [[ -f "$outdir/crawl_urls.txt" ]] || : >"$outdir/crawl_urls.txt"

    sort -u "$outdir/crawl_urls.txt" -o "$outdir/endpoints.txt" 2>/dev/null || \
        cp "$outdir/crawl_urls.txt" "$outdir/endpoints.txt"
    [[ -f "$outdir/endpoints.txt" ]] || : >"$outdir/endpoints.txt"

    local count; count=$(wc -l <"$outdir/endpoints.txt")
    ok "    endpoints: $count"
}

# ---------- Stage 5: ffuf ----------
stage_ffuf() {
    local outdir="$1"
    echo "${CYAN}[5/7] Directory fuzzing (ffuf)...${NC}"
    log "FFUF: starting"

    if (( WITH_FFUF == 0 )); then warn "    disabled (use --with-ffuf)"; : >"$outdir/ffuf_findings.txt"; return 0; fi
    if [[ ! -s "$outdir/urls.txt" ]]; then
        warn "    no live URLs, skipping"; : >"$outdir/ffuf_findings.txt"; return 1
    fi
    if [[ ! -f "$FFUF_WORDLIST" ]]; then
        warn "    wordlist not found: $FFUF_WORDLIST"; : >"$outdir/ffuf_findings.txt"; return 1
    fi

    : >"$outdir/ffuf_findings.txt"
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        "$FFUF_BIN" -u "${url}/FUZZ" -w "$FFUF_WORDLIST" \
            -mc 200,204,301,302,307,401,403 \
            -rate "$RATE_LIMIT" -s \
            >>"$outdir/ffuf_findings.txt" 2>/dev/null || true
    done <"$outdir/urls.txt"

    local count; count=$(wc -l <"$outdir/ffuf_findings.txt")
    ok "    ffuf findings: $count"
}

# ---------- Stage 6: dalfox ----------
stage_xss() {
    local outdir="$1"
    echo "${CYAN}[6/7] XSS scanning (dalfox)...${NC}"
    log "XSS: starting"

    if [[ ! -s "$outdir/endpoints.txt" ]]; then
        warn "    no endpoints, skipping"; : >"$outdir/xss_findings.txt"; return 1
    fi

    grep '?' "$outdir/endpoints.txt" | sort -u >"$outdir/params.txt" || true
    if [[ ! -s "$outdir/params.txt" ]]; then
        warn "    no parameterized URLs found"; : >"$outdir/xss_findings.txt"; return 0
    fi

    "$DALFOX_BIN" file "$outdir/params.txt" --silence --no-color \
        --output "$outdir/xss_findings.txt" 2>/dev/null || true
    [[ -f "$outdir/xss_findings.txt" ]] || : >"$outdir/xss_findings.txt"

    local count; count=$(grep -c '\[V\]' "$outdir/xss_findings.txt" 2>/dev/null || echo 0)
    ok "    XSS findings: $count"
}

# ---------- Stage 7: sqlmap ----------
stage_sqlmap() {
    local outdir="$1"
    echo "${CYAN}[7/7] SQL injection scan (sqlmap)...${NC}"
    log "SQLMAP: starting"

    if (( WITH_SQLMAP == 0 )); then warn "    disabled (use --with-sqlmap)"; : >"$outdir/sqlmap_findings.txt"; return 0; fi
    if [[ ! -s "$outdir/params.txt" ]]; then
        warn "    no parameterized URLs, skipping"; : >"$outdir/sqlmap_findings.txt"; return 1
    fi

    : >"$outdir/sqlmap_findings.txt"
    local i=0
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        (( i++ ))
        (( i > 20 )) && { warn "    hit 20-URL limit, stopping"; break; }

        echo "  [>] $url" >>"$outdir/sqlmap_findings.txt"
        "$SQLMAP_BIN" -u "$url" \
            --batch --level="$SQLMAP_LEVEL" --risk="$SQLMAP_RISK" \
            --threads 2 --timeout 10 --retries 1 \
            --output-dir="$outdir/sqlmap_out" \
            >>"$outdir/sqlmap_findings.txt" 2>&1 || true
    done <"$outdir/params.txt"

    local count; count=$(grep -c 'Parameter:' "$outdir/sqlmap_findings.txt" 2>/dev/null || echo 0)
    ok "    potential SQLi params: $count"
}

# ---------- Helpers ----------
count_lines() { [[ -f "$1" ]] && wc -l <"$1" || echo 0; }
count_xss()   { [[ -f "$1" ]] && grep -c '\[V\]' "$1" 2>/dev/null || echo 0; }
count_nuc()   { [[ -f "$1" ]] && wc -l <"$1" || echo 0; }
count_sql()   { [[ -f "$1" ]] && grep -c 'Parameter:' "$1" 2>/dev/null || echo 0; }

# ---------- Full run ----------
run_full() {
    local target="$1"
    local ts outdir
    ts=$(date +%Y%m%d_%H%M%S)
    local safe="${target#http://}"; safe="${safe#https://}"
    safe="${safe//[:\/]/_}"
    outdir="$REPORT_ROOT/${safe}_${ts}"
    mkdir -p "$outdir"

    echo "${CYAN}>>> Target:${NC} $target"
    echo "${CYAN}    Output:${NC} $outdir"
    echo "${CYAN}    Config:${NC} nuclei=$WITH_NUCLEI ffuf=$WITH_FFUF sqlmap=$WITH_SQLMAP rate=$RATE_LIMIT depth=$DEPTH"
    echo ""

    stage_subs   "$target" "$outdir"
    stage_live   "$outdir"
    stage_nuclei "$outdir"
    stage_crawl  "$outdir"
    stage_ffuf   "$outdir"
    stage_xss    "$outdir"
    stage_sqlmap "$outdir"

    {
        echo "Recon summary for $target"
        echo "Generated:     $(date)"
        echo "Subdomains:    $(count_lines "$outdir/subdomains.txt")"
        echo "Live hosts:    $(count_lines "$outdir/live_hosts.txt")"
        echo "Nuclei finds:  $(count_nuc   "$outdir/nuclei_findings.txt")"
        echo "Endpoints:     $(count_lines "$outdir/endpoints.txt")"
        echo "FFUF finds:    $(count_lines "$outdir/ffuf_findings.txt")"
        echo "XSS finds:     $(count_xss   "$outdir/xss_findings.txt")"
        echo "SQLi params:   $(count_sql   "$outdir/sqlmap_findings.txt")"
    } >"$outdir/summary.txt"

    echo ""
    ok "Recon complete"
    ok "Report: $outdir/summary.txt"
    log "DONE: $target → $outdir"
}

# ---------- Queue ----------
queue_add()   { [[ -z "${1:-}" ]] && die "no target"; printf '%s\n' "$1" >>"$QUEUE_FILE"; ok "Added: $1"; }
queue_list()  { if [[ -s "$QUEUE_FILE" ]]; then echo "${YELLOW}== QUEUE ==${NC}"; nl -w2 -s'. ' "$QUEUE_FILE"; else warn "queue empty"; fi; }
queue_clear() { : >"$QUEUE_FILE"; ok "queue cleared"; }
queue_run()   {
    [[ -s "$QUEUE_FILE" ]] || die "queue is empty"
    ok "running queue..."
    while IFS= read -r target || [[ -n "$target" ]]; do
        [[ -z "$target" ]] && continue
        run_full "$target"
        echo "${CYAN}----------------------------------------${NC}"
    done <"$QUEUE_FILE"
    ok "queue finished"
}

# ---------- Run wrapper ----------
cmd_run() {
    local target=""

    while (( $# > 0 )); do
        case "$1" in
            --with-ffuf)   WITH_FFUF=1; shift ;;
            --with-sqlmap) WITH_SQLMAP=1; shift ;;
            --no-nuclei)   WITH_NUCLEI=0; shift ;;
            --rate-limit)  RATE_LIMIT="$2"; shift 2 ;;
            --depth)       DEPTH="$2"; shift 2 ;;
            --*) die "unknown option: $1" ;;
            *) if [[ -z "$target" ]]; then target="$1"; shift; else die "unexpected arg: $1"; fi ;;
        esac
    done

    [[ -n "$target" ]] || die "usage: $0 run <target> [options]"
    require_tools
    run_full "$target"
}

# ---------- Main ----------
main() {
    if (( $# == 0 )); then show_help; exit 0; fi

    local cmd="$1"; shift

    case "$cmd" in
        --help|-h|man) show_help; exit 0 ;;

        tools)
            show_tools
            exit 0
            ;;

        run)
            cmd_run "$@"
            ;;

        subs)
            require_tools; [[ -n "${1:-}" ]] || die "usage: $0 subs <domain>"
            local ts safe outdir
            ts=$(date +%Y%m%d_%H%M%S); safe="${1//[:\/]/_}"
            outdir="$REPORT_ROOT/${safe}_${ts}"; mkdir -p "$outdir"
            stage_subs "$1" "$outdir"; ok "Output: $outdir/subdomains.txt"
            ;;

        live)
            require_tools; [[ -n "${1:-}" ]] || die "usage: $0 live <target>"
            local ts safe outdir
            ts=$(date +%Y%m%d_%H%M%S); safe="${1//[:\/]/_}"
            outdir="$REPORT_ROOT/${safe}_${ts}"; mkdir -p "$outdir"
            stage_subs "$1" "$outdir"; stage_live "$outdir"
            ok "Output: $outdir/live_hosts.txt"
            ;;

        urls)
            require_tools; [[ -n "${1:-}" ]] || die "usage: $0 urls <target>"
            local ts safe outdir
            ts=$(date +%Y%m%d_%H%M%S); safe="${1//[:\/]/_}"
            outdir="$REPORT_ROOT/${safe}_${ts}"; mkdir -p "$outdir"
            stage_subs "$1" "$outdir"; stage_live "$outdir"; stage_crawl "$outdir"
            ok "Output: $outdir/endpoints.txt"
            ;;

        xss)
            require_tools; [[ -n "${1:-}" ]] || die "usage: $0 xss <target>"
            local ts safe outdir
            ts=$(date +%Y%m%d_%H%M%S); safe="${1//[:\/]/_}"
            outdir="$REPORT_ROOT/${safe}_${ts}"; mkdir -p "$outdir"
            stage_subs "$1" "$outdir"; stage_live "$outdir"
            stage_crawl "$outdir"; stage_xss "$outdir"
            ok "Output: $outdir/xss_findings.txt"
            ;;

        queue)
            require_tools
            case "${1:-}" in
                add)   shift; queue_add "$@" ;;
                list)  queue_list ;;
                run)   queue_run ;;
                clear) queue_clear ;;
                *)     show_help; exit 1 ;;
            esac
            ;;

        reports)
            if [[ -d "$REPORT_ROOT" ]]; then
                find "$REPORT_ROOT" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort -r
            else
                warn "no reports yet"
            fi
            ;;

        *) show_help; exit 1 ;;
    esac
}

main "$@"