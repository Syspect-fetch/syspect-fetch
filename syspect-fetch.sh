mkdir -p "$HOME/.local/bin" "$HOME/.config/syspect-fetch"

cat > "$HOME/.local/bin/syspect-fetch" <<'SYSP'
#!/usr/bin/env bash

# ============================================================
# SYSPECT FETCH
# Version 3.2.0 "NOVA UNICODE"
# ============================================================

VERSION="3.2.0"
APP="Syspect Fetch"

# ---------- ANSI ----------
ESC=$'\033'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
CURSOR_HOME="${ESC}[H"
CLEAR_LINE="${ESC}[2K"
SHOW_CURSOR="${ESC}[?25h"

# ---------- Defaults ----------
THEME="${SYSP_THEME:-nova}"
INTERVAL="${SYSP_INTERVAL:-1}"
LIVE=0
LOGO_ONLY=0
ASCII=0
ANIMATION=1
TIP=1

# ---------- Auto-detect UTF-8 / Locale ----------
case "${LANG:-}${LC_ALL:-}${LC_CTYPE:-}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
    *) ASCII=1 ;; # Fallback naar ASCII als terminal geen UTF-8 locale doorgeeft
esac

# ---------- Theme ----------
set_theme() {
    case "$1" in
        nova|cyan)     C1="${ESC}[96m"; C2="${ESC}[36m"; C3="${ESC}[94m" ;;
        matrix|green) C1="${ESC}[92m"; C2="${ESC}[32m"; C3="${ESC}[90m" ;;
        cyber|purple) C1="${ESC}[95m"; C2="${ESC}[35m"; C3="${ESC}[94m" ;;
        fire|red)     C1="${ESC}[91m"; C2="${ESC}[31m"; C3="${ESC}[93m" ;;
        ocean|blue)   C1="${ESC}[94m"; C2="${ESC}[34m"; C3="${ESC}[96m" ;;
        gold|yellow)  C1="${ESC}[93m"; C2="${ESC}[33m"; C3="${ESC}[97m" ;;
        mono|white)   C1="${ESC}[97m"; C2="${ESC}[37m"; C3="${ESC}[90m" ;;
        *)             THEME="nova"; C1="${ESC}[96m"; C2="${ESC}[36m"; C3="${ESC}[94m" ;;
    esac
}

set_theme "$THEME"

# ---------- Utilities ----------
have() { command -v "$1" >/dev/null 2>&1; }
safe_cat() { [ -r "$1" ] && cat "$1" 2>/dev/null || true; }

bytes() {
    awk -v n="${1:-0}" '
    BEGIN {
        if (n < 0) n=0
        if (n >= 1099511627776) printf "%.2f TiB", n/1099511627776
        else if (n >= 1073741824) printf "%.2f GiB", n/1073741824
        else if (n >= 1048576) printf "%.1f MiB", n/1048576
        else if (n >= 1024) printf "%.1f KiB", n/1024
        else printf "%.0f B", n
    }'
}

num() { printf '%s' "${1:-}" | grep -Eq '^[0-9]+([.][0-9]+)?$'; }
clamp() { awk -v n="${1:-0}" 'BEGIN { if (n < 0) n=0; if (n > 100) n=100; printf "%.0f", n }'; }

# ---------- UTF-8 Safe Bars ----------
bar() {
    local p="${1:-0}" width="${2:-20}"
    p="$(clamp "$p")"

    awk -v p="$p" -v w="$width" -v c1="$C1" -v c2="$C2" -v reset="$RESET" '
    BEGIN {
        filled = int(p * w / 100 + 0.5)
        if (filled < 0) filled = 0
        if (filled > w) filled = w
        empty = w - filled

        printf "%s", c1
        for (i = 0; i < filled; i++) printf "█"
        printf "%s", c2
        for (i = 0; i < empty; i++) printf "·"
        printf "%s", reset
    }'
}

ascii_bar() {
    local p="${1:-0}" width="${2:-20}"
    p="$(clamp "$p")"

    awk -v p="$p" -v w="$width" -v c2="$C2" -v reset="$RESET" '
    BEGIN {
        filled = int(p * w / 100 + 0.5)
        if (filled < 0) filled = 0
        if (filled > w) filled = w
        empty = w - filled

        printf "%s[", c2
        for (i = 0; i < filled; i++) printf "#"
        for (i = 0; i < empty; i++) printf "-"
        printf "]%s", reset
    }'
}

metric() {
    local label="$1" percent="$2" extra="$3"
    printf "  %b%-14s%b " "$C1" "$label" "$RESET"
    [ "$ASCII" -eq 1 ] && ascii_bar "$percent" || bar "$percent"
    printf " %b%3s%%%b" "$C1" "$percent" "$RESET"
    [ -n "$extra" ] && printf "  %b%s%b" "$DIM" "$extra" "$RESET"
    printf "\n"
}

info() { printf "  %b%-16s%b %s\n" "$C1" "$1" "$RESET" "${2:-N/A}"; }

section() {
    printf "\n%b  // %s%b\n" "$C1" "$1" "$RESET"
    if [ "$ASCII" -eq 1 ]; then
        printf "%b  ----------------------------------------------%b\n" "$C3" "$RESET"
    else
        printf "%b  ──────────────────────────────────────────────%b\n" "$C3" "$RESET"
    fi
}

# ---------- OS & Identity ----------
OS_ID="linux"
OS_NAME="Linux"
if [ -r /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-linux}"
    OS_NAME="${PRETTY_NAME:-${NAME:-Linux}}"
fi

KERNEL="$(uname -r 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"
HOSTNAME_VALUE="$(hostname 2>/dev/null || echo unknown)"
SHELL_NAME="$(basename "${SHELL:-unknown}")"

# ---------- CPU Sampler ----------
CPU_MODEL="$(awk -F': ' '/^model name/ {print $2; exit} /^Hardware/ {print $2; exit}' /proc/cpuinfo 2>/dev/null)"
[ -n "$CPU_MODEL" ] || CPU_MODEL="Unknown"
CPU_THREADS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo '?')"

OLD_IDLE=0; OLD_TOTAL=0; CPU_READY=0

cpu_usage() {
    local idle total di dt
    read -r idle total <<< "$(awk '$1=="cpu" {idle=$5+$6; total=$2+$3+$4+$5+$6+$7+$8+$9+$10; print idle, total; exit}' /proc/stat 2>/dev/null)"
    if ! num "$idle" || ! num "$total"; then echo 0; return; fi
    if [ "$CPU_READY" -eq 0 ]; then
        OLD_IDLE="$idle"; OLD_TOTAL="$total"; CPU_READY=1; echo 0; return
    fi
    di=$((idle-OLD_IDLE)); dt=$((total-OLD_TOTAL))
    OLD_IDLE="$idle"; OLD_TOTAL="$total"
    [ "$dt" -le 0 ] && { echo 0; return; }
    awk -v i="$di" -v t="$dt" 'BEGIN {x=((t-i)/t)*100; if(x<0)x=0; if(x>100)x=100; printf "%.0f",x}'
}

# ---------- Verbeterde Memory Calculation ----------
memory_info() {
    awk '
    /^MemTotal:/      {total=$2}
    /^MemFree:/       {free=$2}
    /^MemAvailable:/  {avail=$2}
    /^Buffers:/       {buffers=$2}
    /^Cached:/        {cached=$2}
    /^SReclaimable:/  {sreclaim=$2}
    /^SwapTotal:/     {swap_total=$2}
    /^SwapFree:/      {swap_free=$2}
    END {
        if (avail == 0 && total > 0) {
            avail = free + buffers + cached + sreclaim
        }
        used = total - avail
        buff_cache = buffers + cached + sreclaim
        swap_used = swap_total - swap_free

        ram_pct = (total > 0 ? (used / total) * 100 : 0)
        swap_pct = (swap_total > 0 ? (swap_used / swap_total) * 100 : 0)

        printf "%.0f %s %s %s %.0f %s %s\n", \
            ram_pct, \
            used * 1024, \
            total * 1024, \
            buff_cache * 1024, \
            swap_pct, \
            swap_used * 1024, \
            swap_total * 1024
    }' /proc/meminfo 2>/dev/null
}

# ---------- System Helpers ----------
disk_info() { df -P -B1 / 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5,$3,$2}'; }
filesystem() { df -T / 2>/dev/null | awk 'NR==2 {print $2}'; }
load_average() { awk '{print $1 " / " $2 " / " $3}' /proc/loadavg 2>/dev/null; }

uptime_text() {
    awk '{
        s=int($1); d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60)
        if(d>0) printf "%dd %dh %dm",d,h,m
        else if(h>0) printf "%dh %dm",h,m
        else printf "%dm",m
    }' /proc/uptime 2>/dev/null
}

libc_name() {
    [ -e /lib/ld-musl-x86_64.so.1 ] || [ -e /lib/ld-musl-aarch64.so.1 ] && { echo musl; return; }
    [ -e /lib64/ld-linux-x86-64.so.2 ] || [ -e /lib/ld-linux-aarch64.so.1 ] && { echo glibc; return; }
    echo unknown
}

init_name() {
    if [ -d /run/runit ] || [ -d /etc/runit ]; then echo runit
    elif [ -d /run/systemd/system ]; then echo systemd
    elif [ -d /run/openrc ]; then echo OpenRC
    else echo unknown; fi
}

temperature() {
    local total=0 count=0 f t
    for f in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$f" ] || continue
        t="$(cat "$f" 2>/dev/null)"
        if [ -n "$t" ] && [ "$t" -gt 0 ] && [ "$t" -lt 115000 ]; then
            total=$((total+t))
            count=$((count+1))
        fi
    done
    [ "$count" -gt 0 ] && awk -v t="$total" -v c="$count" 'BEGIN{printf "%.0f°C", t/c/1000}' || echo "N/A"
}

network_interface() {
    have ip && ip route 2>/dev/null | awk '$1=="default" {print $5;exit}' || \
    awk -F: '$1!="lo" && $1!~/^ *$/ {gsub(/ /,"",$1);print $1;exit}' /proc/net/dev 2>/dev/null
}

network_ip() {
    local iface="$1"
    [ -n "$iface" ] && have ip && ip -4 addr show "$iface" 2>/dev/null | awk '$1=="inet" {print $2;exit}' || echo N/A
}

process_count() { set -- /proc/[0-9]*; echo "$#"; }
service_count() { [ -d /var/service ] && echo "$(ls -1 /var/service 2>/dev/null | wc -l)" || echo N/A; }

logo_void() {
cat <<'EOF'
             .--.
          .-(    )-.
         /  .----.  \
        |  /      \  |
        | |  VOID  | |
        |  \      /  |
         \  '----'  /
          '-.____.-'
             VOID
EOF
}

show_logo() {
    printf "%b" "$C1"
    logo_void
    printf "%b" "$RESET"
}

# ============================================================
# RENDERING
# ============================================================

render_full() {
    local cpu ram disk rp ru rt rbc sp su st dp du dt iface ip
    cpu="$(cpu_usage)"
    ram="$(memory_info)"
    disk="$(disk_info)"

    read -r rp ru rt rbc sp su st <<< "$ram"
    read -r dp du dt <<< "$disk"
    iface="$(network_interface)"
    ip="$(network_ip "$iface")"

    printf "\n"
    show_logo
    printf "\n"
    if [ "$ASCII" -eq 1 ]; then
        printf "%b+--------------------------------------------------------------+%b\n" "$C1" "$RESET"
        printf "%b|  SYSPECT FETCH  v%-6s  NOVA SYSTEM INTELLIGENCE             |%b\n" "$C1" "$VERSION" "$RESET"
        printf "%b+--------------------------------------------------------------+%b\n" "$C1" "$RESET"
    else
        printf "%b╔══════════════════════════════════════════════════════════════╗%b\n" "$C1" "$RESET"
        printf "%b║  SYSPECT FETCH  v%-6s  NOVA SYSTEM INTELLIGENCE             ║%b\n" "$C1" "$VERSION" "$RESET"
        printf "%b╚══════════════════════════════════════════════════════════════╝%b\n" "$C1" "$RESET"
    fi

    section "SYSTEM"
    info "OS" "$OS_NAME"
    info "Kernel" "$KERNEL"
    info "Architecture" "$ARCH"
    info "Hostname" "$HOSTNAME_VALUE"
    info "Init" "$(init_name)"
    info "libc" "$(libc_name)"

    section "PROCESSOR"
    info "CPU" "$CPU_MODEL"
    info "Threads" "$CPU_THREADS"
    info "Load" "$(load_average)"
    metric "CPU" "$cpu" ""

    section "MEMORY"
    metric "RAM" "$rp" "$(bytes "$ru") / $(bytes "$rt") (Cache: $(bytes "$rbc"))"
    [ "$st" -gt 0 ] && metric "SWAP" "$sp" "$(bytes "$su") / $(bytes "$st")"

    section "STORAGE"
    metric "Root disk" "$dp" "$(bytes "$du") / $(bytes "$dt")"
    info "Filesystem" "$(filesystem)"

    section "NETWORK & THERMALS"
    info "Interface" "${iface:-offline}"
    info "IPv4" "$ip"
    info "Temperature" "$(temperature)"

    section "RUNTIME"
    info "Uptime" "$(uptime_text)"
    info "Processes" "$(process_count)"
    info "Services" "$(service_count)"

    printf "\n"
}

render_live() {
    local cpu ram disk rp ru rt rbc sp su st dp du dt iface ip
    cpu="$(cpu_usage)"
    ram="$(memory_info)"
    disk="$(disk_info)"

    read -r rp ru rt rbc sp su st <<< "$ram"
    read -r dp du dt <<< "$disk"
    iface="$(network_interface)"
    ip="$(network_ip "$iface")"

    printf "%s" "$CURSOR_HOME"
    printf "%s\n" "$CLEAR_LINE"
    printf "%bSYSPECT FETCH%b  %b● LIVE%b  %s\n" "$C1" "$BOLD" "$RESET" "$C1" "$RESET" "$(date '+%H:%M:%S')"
    printf "%b\n" "$CLEAR_LINE"
    printf "  %s  (Kernel: %s)\n" "$OS_NAME" "$KERNEL"
    printf "%b\n" "$CLEAR_LINE"

    metric "CPU" "$cpu" ""
    metric "RAM" "$rp" "$(bytes "$ru") / $(bytes "$rt")"
    metric "DISK" "$dp" "$(bytes "$du") / $(bytes "$dt")"

    printf "%b\n" "$CLEAR_LINE"
    info "Load" "$(load_average)"
    info "Temp" "$(temperature)"
    info "Processes" "$(process_count)"
    info "Net" "${iface:-offline} ($ip)"
    printf "%b\n" "$CLEAR_LINE"
    printf "  %bCtrl+C%b to exit\n" "$DIM" "$RESET"
    printf "%b" "$CLEAR_LINE"
}

# ============================================================
# CLI ARGUMENTS
# ============================================================

while [ "$#" -gt 0 ]; do
    case "$1" in
        --live|-l) LIVE=1 ;;
        --interval|-i) shift; INTERVAL="${1:-1}" ;;
        --theme|-t) shift; THEME="${1:-nova}"; set_theme "$THEME" ;;
        --logo) show_logo; exit 0 ;;
        --ascii) ASCII=1 ;;
        --version|-v) echo "$APP $VERSION"; exit 0 ;;
        *) shift ;;
    esac
    shift
done

cleanup() { printf "%b" "$SHOW_CURSOR"; printf "\n"; }
trap cleanup INT TERM EXIT

if [ "$LIVE" -eq 1 ]; then
    cpu_usage >/dev/null
    render_live
    while :; do
        sleep "$INTERVAL"
        render_live
    done
fi

render_full
SYSP

chmod +x "$HOME/.local/bin/syspect-fetch"
bash -n "$HOME/.local/bin/syspect-fetch" && echo "✓ Syspect Fetch 3.2.0 geïnstalleerd zonder Unicode-fouten."
