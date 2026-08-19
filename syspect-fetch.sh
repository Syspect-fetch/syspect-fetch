mkdir -p "$HOME/.local/bin" \
         "$HOME/.config/syspect-fetch" \
         "$HOME/.config/syspect-fetch/logs" &&

rm -f \
  "$HOME/.local/bin/syspect-fetch-av" \
  "$HOME/.local/bin/syspectav" \
  "$HOME/.local/bin/SyspectAV" \
  "$HOME/.local/bin/syspectAV" \
  "$HOME/.config/syspect-fetch/fastfetch.conf" \
  "$HOME/.config/syspect-fetch/fastfetch.jsonc" &&

cat > "$HOME/.local/bin/syspect-fetch" <<'SYSP'
#!/usr/bin/env bash

# ============================================================
#                         SYSPECT-FETCH
#                         Version 9.0.0
#
# Created by Kayan Erkama
# License: MIT
#
# Native Linux system information utility.
#
# IMPORTANT:
# This program does NOT use Fastfetch, Neofetch or Pfetch.
# This program does NOT contain antivirus functionality.
# ============================================================

VERSION="9.0.0"
APP="Syspect-fetch"
AUTHOR="Kayan Erkama"

CONFIG_DIR="${HOME}/.config/syspect-fetch"
LOG_DIR="${CONFIG_DIR}/logs"

mkdir -p "$CONFIG_DIR" "$LOG_DIR" 2>/dev/null || true

# ============================================================
# ANSI
# ============================================================

ESC=$'\033'

RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"

RED="${ESC}[91m"
GREEN="${ESC}[92m"
YELLOW="${ESC}[93m"
BLUE="${ESC}[94m"
MAGENTA="${ESC}[95m"
CYAN="${ESC}[96m"
WHITE="${ESC}[97m"

CLEAR="${ESC}[2J${ESC}[H"
HOME_CURSOR="${ESC}[H"
HIDE_CURSOR="${ESC}[?25l"
SHOW_CURSOR="${ESC}[?25h"

# ============================================================
# STATE
# ============================================================

CPU_READY=0
CPU_OLD_IDLE=0
CPU_OLD_TOTAL=0

ANIMATION=1

# ============================================================
# CLEANUP
# ============================================================

cleanup() {
    printf '%b' "${RESET}${SHOW_CURSOR}"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ============================================================
# HELPERS
# ============================================================

have() {
    command -v "$1" >/dev/null 2>&1
}

is_uint() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

is_number() {
    [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

terminal_width() {
    local width

    width="$(tput cols 2>/dev/null || true)"

    if ! is_uint "$width" || (( width < 60 )); then
        width=80
    fi

    printf '%s\n' "$width"
}

repeat_char() {
    local char="$1"
    local amount="${2:-0}"
    local i

    is_uint "$amount" || return 0

    for ((i=0; i<amount; i++)); do
        printf '%s' "$char"
    done
}

clamp_percent() {
    local value="${1:-0}"

    is_number "$value" || value=0

    awk -v n="$value" '
    BEGIN {
        if(n < 0) n=0
        if(n > 100) n=100
        printf "%.0f", n
    }'
}

human_bytes() {
    local value="${1:-0}"

    is_number "$value" || value=0

    awk -v n="$value" '
    BEGIN {
        if(n < 1024)
            printf "%.0f B", n
        else if(n < 1048576)
            printf "%.1f KiB", n/1024
        else if(n < 1073741824)
            printf "%.1f MiB", n/1048576
        else if(n < 1099511627776)
            printf "%.2f GiB", n/1073741824
        else
            printf "%.2f TiB", n/1099511627776
    }'
}

# ============================================================
# UI
# ============================================================

section() {
    local name="$1"
    local width
    local used
    local remaining

    width="$(terminal_width)"

    used=$(( ${#name} + 6 ))
    remaining=$(( width - used ))

    (( remaining < 4 )) && remaining=4

    printf "\n%b── %s " "$BLUE" "$name"
    repeat_char "─" "$remaining"
    printf "%b\n" "$RESET"
}

info() {
    printf "  %b%-19s%b %s\n" \
        "$CYAN" \
        "$1" \
        "$RESET" \
        "${2:-N/A}"
}

progress_bar() {
    local percent
    local width=30
    local filled
    local empty

    percent="$(clamp_percent "${1:-0}")"

    filled=$(( percent * width / 100 ))
    empty=$(( width - filled ))

    printf "  %b[" "$CYAN"

    repeat_char "█" "$filled"

    printf "%b" "$DIM"

    repeat_char "░" "$empty"

    printf "%b] %3s%%%b\n" \
        "$RESET" \
        "$percent" \
        "$RESET"
}

# ============================================================
# OS DETECTION
# ============================================================

OS_ID="linux"
OS_NAME="Linux"
OS_VERSION="unknown"

if [[ -r /etc/os-release ]]; then
    . /etc/os-release 2>/dev/null || true

    OS_ID="${ID:-linux}"
    OS_NAME="${PRETTY_NAME:-${NAME:-Linux}}"
    OS_VERSION="${VERSION_ID:-unknown}"
fi

KERNEL="$(uname -r 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"
HOSTNAME_VALUE="$(hostname 2>/dev/null || echo unknown)"
USERNAME="${USER:-$(id -un 2>/dev/null || echo unknown)}"
SHELL_NAME="$(basename "${SHELL:-unknown}")"

# ============================================================
# CPU
# ============================================================

CPU_MODEL="$(
    awk -F': ' '
        /^model name/ {
            print $2
            exit
        }

        /^Hardware/ {
            print $2
            exit
        }

        /^Processor/ {
            print $2
            exit
        }
    ' /proc/cpuinfo 2>/dev/null
)"

[[ -n "$CPU_MODEL" ]] || CPU_MODEL="Unknown CPU"

CPU_THREADS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"

is_uint "$CPU_THREADS" || CPU_THREADS="N/A"

cpu_usage() {
    local idle
    local total
    local idle_delta
    local total_delta

    [[ -r /proc/stat ]] || {
        echo 0
        return
    }

    read -r idle total <<< "$(
        awk '
        $1=="cpu" {
            idle=$5+$6
            total=$2+$3+$4+$5+$6+$7+$8+$9+$10
            print idle,total
            exit
        }' /proc/stat 2>/dev/null
    )"

    if ! is_uint "$idle" || ! is_uint "$total"; then
        echo 0
        return
    fi

    if (( CPU_READY == 0 )); then
        CPU_OLD_IDLE="$idle"
        CPU_OLD_TOTAL="$total"
        CPU_READY=1
        echo 0
        return
    fi

    idle_delta=$((idle - CPU_OLD_IDLE))
    total_delta=$((total - CPU_OLD_TOTAL))

    CPU_OLD_IDLE="$idle"
    CPU_OLD_TOTAL="$total"

    if (( total_delta <= 0 || idle_delta < 0 )); then
        echo 0
        return
    fi

    awk -v i="$idle_delta" -v t="$total_delta" '
    BEGIN {
        usage=((t-i)/t)*100

        if(usage<0) usage=0
        if(usage>100) usage=100

        printf "%.0f",usage
    }'
}

# ============================================================
# MEMORY
# ============================================================

memory_info() {
    [[ -r /proc/meminfo ]] || {
        echo "0 0 0 0 0 0"
        return
    }

    awk '
    /^MemTotal:/      { total=$2 }
    /^MemAvailable:/  { available=$2 }
    /^MemFree:/       { free=$2 }
    /^Buffers:/       { buffers=$2 }
    /^Cached:/        { cached=$2 }
    /^SReclaimable:/  { reclaim=$2 }

    /^SwapTotal:/     { swap_total=$2 }
    /^SwapFree:/      { swap_free=$2 }

    END {
        if(total <= 0) {
            print "0 0 0 0 0 0"
            exit
        }

        if(available <= 0)
            available=free+buffers+cached+reclaim

        used=total-available

        if(used < 0)
            used=0

        swap_used=swap_total-swap_free

        if(swap_used < 0)
            swap_used=0

        ram_percent=(used/total)*100

        if(swap_total > 0)
            swap_percent=(swap_used/swap_total)*100
        else
            swap_percent=0

        printf "%.0f %.0f %.0f %.0f %.0f %.0f\n",
            used*1024,
            total*1024,
            swap_used*1024,
            swap_total*1024,
            ram_percent,
            swap_percent
    }' 2>/dev/null
}

# ============================================================
# DISK
# ============================================================

disk_info() {
    df -P -B1 / 2>/dev/null |
        awk '
        NR==2 {
            gsub("%","",$5)

            if($5 !~ /^[0-9]+$/)
                $5=0

            print $5,$3,$2,$4
            exit
        }'
}

filesystem() {
    df -T / 2>/dev/null |
        awk 'NR==2 {print $2;exit}'
}

# ============================================================
# NETWORK
# ============================================================

network_interface() {
    if have ip; then
        ip route 2>/dev/null |
            awk '$1=="default" {
                print $5
                exit
            }'

        return
    fi

    [[ -r /proc/net/route ]] || return

    awk '
    NR>1 && $2=="00000000" {
        print $1
        exit
    }' /proc/net/route 2>/dev/null
}

network_ipv4() {
    local interface="$1"

    [[ -n "$interface" ]] || {
        echo "offline"
        return
    }

    if have ip; then
        ip -4 addr show "$interface" 2>/dev/null |
            awk '$1=="inet" {
                print $2
                exit
            }'
    fi
}

# ============================================================
# TEMPERATURE
# ============================================================

temperature() {
    local total=0
    local count=0
    local file
    local temp

    shopt -s nullglob

    for file in /sys/class/thermal/thermal_zone*/temp; do
        [[ -r "$file" ]] || continue

        temp="$(cat "$file" 2>/dev/null || true)"

        is_uint "$temp" || continue

        if (( temp > 0 && temp < 125000 )); then
            total=$((total + temp))
            count=$((count + 1))
        fi
    done

    shopt -u nullglob

    if (( count > 0 )); then
        awk -v total="$total" -v count="$count" '
        BEGIN {
            printf "%.0f°C", total/count/1000
        }'
    else
        echo "N/A"
    fi
}

# ============================================================
# SYSTEM
# ============================================================

load_average() {
    [[ -r /proc/loadavg ]] || {
        echo "N/A"
        return
    }

    awk '{print $1 " / " $2 " / " $3}' \
        /proc/loadavg 2>/dev/null
}

uptime_text() {
    [[ -r /proc/uptime ]] || {
        echo "N/A"
        return
    }

    awk '
    {
        seconds=int($1)

        days=int(seconds/86400)
        hours=int((seconds%86400)/3600)
        minutes=int((seconds%3600)/60)

        if(days>0)
            printf "%dd %dh %dm",days,hours,minutes
        else if(hours>0)
            printf "%dh %dm",hours,minutes
        else
            printf "%dm",minutes
    }' /proc/uptime 2>/dev/null
}

process_count() {
    local count=0
    local process

    shopt -s nullglob

    for process in /proc/[0-9]*; do
        [[ -d "$process" ]] && ((count++))
    done

    shopt -u nullglob

    echo "$count"
}

init_system() {
    if [[ -d /run/runit || -d /etc/runit ]]; then
        echo "runit"
    elif [[ -d /run/systemd/system ]]; then
        echo "systemd"
    elif [[ -d /run/openrc ]]; then
        echo "OpenRC"
    elif [[ -d /run/s6 ]]; then
        echo "s6"
    else
        echo "unknown"
    fi
}

libc_name() {
    if [[ \
        -e /lib/ld-musl-x86_64.so.1 ||
        -e /lib/ld-musl-aarch64.so.1 ||
        -e /lib/ld-musl-armhf.so.1
    ]]; then
        echo "musl"
        return
    fi

    if [[ \
        -e /lib64/ld-linux-x86-64.so.2 ||
        -e /lib/ld-linux-x86-64.so.2 ||
        -e /lib/ld-linux-aarch64.so.1 ||
        -e /lib/ld-linux-armhf.so.3
    ]]; then
        echo "glibc"
        return
    fi

    echo "unknown"
}

# ============================================================
# PACKAGE COUNT
# ============================================================

package_count() {
    case "$OS_ID" in

        void)
            if have xbps-query; then
                xbps-query -l 2>/dev/null | wc -l
            else
                echo "N/A"
            fi
            ;;

        arch|artix|manjaro)
            if have pacman; then
                pacman -Q 2>/dev/null | wc -l
            else
                echo "N/A"
            fi
            ;;

        debian|ubuntu|linuxmint|pop)
            if have dpkg-query; then
                dpkg-query -W 2>/dev/null | wc -l
            else
                echo "N/A"
            fi
            ;;

        fedora|rhel|centos)
            if have rpm; then
                rpm -qa 2>/dev/null | wc -l
            else
                echo "N/A"
            fi
            ;;

        alpine)
            if have apk; then
                apk info 2>/dev/null | wc -l
            else
                echo "N/A"
            fi
            ;;

        *)
            echo "N/A"
            ;;
    esac
}

# ============================================================
# NATIVE DISTRO ASCII
# ============================================================

logo_void() {
cat <<'ART'
                 \033[1;36m
                         .--.
                      .-(    )-.
                     /  .----.  \
                    |  /      \  |
                    | |  VOID  | |
                    |  \      /  |
                     \  '----'  /
                      '-.____.-'
                         VOID
                 \033[0m
ART
}

logo_arch() {
cat <<'ART'
                         /\
                        /  \
                       / /\ \
                      / /  \ \
                     / /____\ \
                    /__________\
ART
}

logo_debian() {
cat <<'ART'
                         _____
                       /       \
                      /  .-.    \
                     |  (   )    |
                      \  `-'    /
                       \       /
                        `-._.-'
                         Debian
ART
}

logo_ubuntu() {
cat <<'ART'
                       .-''''-.
                    .-'   ()   '-.
                  .'    /    \    '.
                 /    ()      ()    \
                ;        .--.        ;
                |      .'    '.      |
                ;     /   ()   \     ;
                 \    '.      .'    /
                  '.    '-..-'    .'
                    '-.        .-'
                       '------'
ART
}

logo_fedora() {
cat <<'ART'
                       .-""""-.
                     .'  .--.  '.
                    /   /    \   \
                   ;   |  ()  |   ;
                   |   |      |   |
                   ;    \____/    ;
                    \            /
                     '.        .'
                       '-.__.-'
ART
}

logo_alpine() {
cat <<'ART'
                         /\
                        /  \
                       / /\ \
                      / /  \ \
                     / /____\ \
                    /_/      \_\
                       ALPINE
ART
}

logo_nixos() {
cat <<'ART'
                         /\
                    ____/  \____
                   /   /\  /\   \
                  /___/  \/  \___\
                  \   \  /\  /   /
                   \___\/  \/___/
                       NIXOS
ART
}

logo_manjaro() {
cat <<'ART'
                       ███ ███ ███
                       ███ ███ ███
                       ███ ███ ███
                       ███ ███ ███
                       ███ ███ ███
                       ███ ███ ███
                         MANJARO
ART
}

logo_opensuse() {
cat <<'ART'
                       _________
                     /           \
                    /    .---.    \
                   |    /     \    |
                    \   \_____/   /
                     \           /
                      '---------'
                        openSUSE
ART
}

logo_gentoo() {
cat <<'ART'
                         .-.
                        /   \
                       / /\  \
                      / /  \  \
                     / /    \  \
                    /_/      \__\
                        GENTOO
ART
}

logo_slackware() {
cat <<'ART'
                         ______
                        / ____ \
                       / /    \ \
                      / /      \ \
                     / /        \ \
                    /_/          \_\
                       SLACKWARE
ART
}

logo_generic() {
cat <<'ART'
                         .-""""-.
                       .'  LINUX  '.
                      /             \
                     |   SYSPECT     |
                      \             /
                       '.         .'
                         '-.___.-'
ART
}

show_logo() {
    case "$OS_ID" in
        void)      logo_void ;;
        arch)      logo_arch ;;
        debian)    logo_debian ;;
        ubuntu)    logo_ubuntu ;;
        fedora)    logo_fedora ;;
        alpine)    logo_alpine ;;
        nixos)     logo_nixos ;;
        manjaro)   logo_manjaro ;;
        opensuse*|suse) logo_opensuse ;;
        gentoo)    logo_gentoo ;;
        slackware) logo_slackware ;;
        *)         logo_generic ;;
    esac
}

# ============================================================
# STARTUP ANIMATION
# ============================================================

startup_animation() {
    [[ -t 1 ]] || return
    (( ANIMATION == 1 )) || return

    printf '%b%b' "$CLEAR" "$HIDE_CURSOR"

    printf "\n%b" "$CYAN"

    cat <<'ART'
                 ╔══════════════════════════════╗
                 ║                              ║
                 ║        S Y S P E C T         ║
                 ║          F E T C H           ║
                 ║                              ║
                 ╚══════════════════════════════╝
ART

    printf "%b" "$RESET"

    sleep 0.05

    printf '%b%b' "$CLEAR" "$HIDE_CURSOR"

    printf "\n%b" "$BLUE"

    cat <<'ART'
                 ╔══════════════════════════════╗
                 ║       SYSTEM INITIALIZE      ║
                 ║                              ║
                 ║          ░▒▓████▓▒░          ║
                 ║                              ║
                 ╚══════════════════════════════╝
ART

    printf "%b" "$RESET"

    sleep 0.05

    printf '%b%b' "$CLEAR" "$HIDE_CURSOR"

    show_logo

    sleep 0.05
}

# ============================================================
# FULL RENDER
# ============================================================

render_full() {
    local memory
    local disk

    local ram_used
    local ram_total
    local swap_used
    local swap_total
    local ram_percent
    local swap_percent

    local disk_percent
    local disk_used
    local disk_total

    local cpu
    local iface
    local ip

    memory="$(memory_info)"
    disk="$(disk_info)"

    read -r \
        ram_used \
        ram_total \
        swap_used \
        swap_total \
        ram_percent \
        swap_percent <<< "$memory"

    read -r \
        disk_percent \
        disk_used \
        disk_total \
        _ <<< "$disk"

    cpu="$(cpu_usage)"
    iface="$(network_interface)"
    ip="$(network_ipv4 "$iface")"

    printf '%b%b' "$CLEAR" "$HIDE_CURSOR"

    show_logo

    printf "\n"

    printf "%b%s%b  %bv%s%b\n" \
        "$BOLD" \
        "$APP" \
        "$RESET" \
        "$DIM" \
        "$VERSION" \
        "$RESET"

    printf "%bCreated by %s%b\n" \
        "$DIM" \
        "$AUTHOR" \
        "$RESET"

    section "SYSTEM"

    info "OS" "$OS_NAME"
    info "Kernel" "$KERNEL"
    info "Architecture" "$ARCH"
    info "Hostname" "$HOSTNAME_VALUE"
    info "User" "$USERNAME"
    info "Shell" "$SHELL_NAME"
    info "Init" "$(init_system)"
    info "libc" "$(libc_name)"
    info "Packages" "$(package_count)"

    section "PROCESSOR"

    info "CPU" "$CPU_MODEL"
    info "Threads" "$CPU_THREADS"
    info "Load" "$(load_average)"
    info "Usage" "${cpu}%"

    progress_bar "$cpu"

    section "MEMORY"

    info "RAM" \
        "$(human_bytes "$ram_used") / $(human_bytes "$ram_total")"

    progress_bar "$ram_percent"

    if is_number "$swap_total" &&
       awk -v n="$swap_total" 'BEGIN { exit !(n>0) }'; then

        info "Swap" \
            "$(human_bytes "$swap_used") / $(human_bytes "$swap_total")"

        progress_bar "$swap_percent"
    fi

    section "STORAGE"

    info "Root" \
        "$(human_bytes "$disk_used") / $(human_bytes "$disk_total")"

    progress_bar "$disk_percent"

    info "Filesystem" "$(filesystem)"

    section "NETWORK"

    info "Interface" "${iface:-offline}"
    info "IPv4" "${ip:-offline}"

    section "RUNTIME"

    info "Uptime" "$(uptime_text)"
    info "Processes" "$(process_count)"
    info "Temperature" "$(temperature)"

    section "SYSPECT"

    info "Version" "$VERSION"
    info "GUI" "None"
    info "Telemetry" "None"
    info "Antivirus" "None"
    info "Fastfetch" "Not used"
    info "Neofetch" "Not used"
    info "Pfetch" "Not used"

    printf "\n%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" \
        "$BLUE" \
        "$RESET"

    printf "  %b[a]%b About    " "$CYAN" "$RESET"
    printf "%b[l]%b Live     " "$CYAN" "$RESET"
    printf "%b[w]%b Watch    " "$CYAN" "$RESET"
    printf "%b[d]%b Doctor\n" "$CYAN" "$RESET"

    printf "  %b[j]%b JSON     " "$CYAN" "$RESET"
    printf "%b[m]%b Minimal  " "$CYAN" "$RESET"
    printf "%b[r]%b Refresh  " "$CYAN" "$RESET"
    printf "%b[s]%b Snapshot\n" "$CYAN" "$RESET"

    printf "  %b[L]%b Logo     " "$CYAN" "$RESET"
    printf "%b[q]%b Quit\n" "$CYAN" "$RESET"

    printf "\n%bSyspect-fetch > %b" "$CYAN" "$RESET"
}

# ============================================================
# LIVE
# ============================================================

live_mode() {
    CPU_READY=0

    while :; do
        local memory
        local disk
        local cpu

        memory="$(memory_info)"
        disk="$(disk_info)"
        cpu="$(cpu_usage)"

        printf '%b%b' "$CLEAR" "$HIDE_CURSOR"

        printf "%bSYSPECT-FETCH // LIVE%b\n\n" \
            "$BOLD" \
            "$RESET"

        printf "%b%s%b\n\n" \
            "$DIM" \
            "$(date '+%Y-%m-%d %H:%M:%S')" \
            "$RESET"

        printf "%bCPU%b\n" "$CYAN" "$RESET"
        progress_bar "$cpu"

        printf "%bRAM%b\n" "$CYAN" "$RESET"
        progress_bar "$(awk '{print $5}' <<< "$memory")"

        printf "%bDISK%b\n" "$CYAN" "$RESET"
        progress_bar "$(awk '{print $1}' <<< "$disk")"

        printf "\n"

        info "Load" "$(load_average)"
        info "Temperature" "$(temperature)"
        info "Processes" "$(process_count)"
        info "Uptime" "$(uptime_text)"

        printf "\n%bPress Ctrl+C to exit live mode.%b\n" \
            "$DIM" \
            "$RESET"

        sleep 1
    done
}

# ============================================================
# WATCH
# ============================================================

watch_mode() {
    local delay="${1:-2}"

    is_number "$delay" || delay=2

    CPU_READY=0

    while :; do
        local memory
        local disk
        local cpu

        memory="$(memory_info)"
        disk="$(disk_info)"
        cpu="$(cpu_usage)"

        printf '%b%b' "$CLEAR" "$HIDE_CURSOR"

        printf "%bSYSPECT WATCH%b\n\n" \
            "$BOLD" \
            "$RESET"

        info "CPU" "${cpu}%"
        info "RAM" "$(awk '{print $5 "%"}' <<< "$memory")"
        info "Disk" "$(awk '{print $1 "%"}' <<< "$disk")"
        info "Load" "$(load_average)"
        info "Temperature" "$(temperature)"
        info "Processes" "$(process_count)"

        printf "\n%bRefresh interval: %ss%b\n" \
            "$DIM" \
            "$delay" \
            "$RESET"

        sleep "$delay"
    done
}

# ============================================================
# JSON
# ============================================================

json_escape() {
    local value="${1:-}"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"

    printf '%s' "$value"
}

json_output() {
    local memory
    local disk
    local iface
    local ip

    memory="$(memory_info)"
    disk="$(disk_info)"
    iface="$(network_interface)"
    ip="$(network_ipv4 "$iface")"

    printf '{\n'
    printf '  "application":"%s",\n' "$(json_escape "$APP")"
    printf '  "version":"%s",\n' "$(json_escape "$VERSION")"
    printf '  "author":"%s",\n' "$(json_escape "$AUTHOR")"
    printf '  "os":"%s",\n' "$(json_escape "$OS_NAME")"
    printf '  "os_id":"%s",\n' "$(json_escape "$OS_ID")"
    printf '  "kernel":"%s",\n' "$(json_escape "$KERNEL")"
    printf '  "architecture":"%s",\n' "$(json_escape "$ARCH")"
    printf '  "hostname":"%s",\n' "$(json_escape "$HOSTNAME_VALUE")"
    printf '  "cpu":"%s",\n' "$(json_escape "$CPU_MODEL")"
    printf '  "threads":%s,\n' "${CPU_THREADS:-0}"
    printf '  "cpu_percent":%s,\n' "$(cpu_usage)"
    printf '  "ram_percent":%s,\n' "$(awk '{print $5}' <<< "$memory")"
    printf '  "swap_percent":%s,\n' "$(awk '{print $6}' <<< "$memory")"
    printf '  "disk_percent":%s,\n' "$(awk '{print $1}' <<< "$disk")"
    printf '  "filesystem":"%s",\n' "$(json_escape "$(filesystem)")"
    printf '  "interface":"%s",\n' "$(json_escape "${iface:-offline}")"
    printf '  "ipv4":"%s",\n' "$(json_escape "${ip:-offline}")"
    printf '  "load":"%s",\n' "$(json_escape "$(load_average)")"
    printf '  "temperature":"%s",\n' "$(json_escape "$(temperature)")"
    printf '  "uptime":"%s",\n' "$(json_escape "$(uptime_text)")"
    printf '  "processes":%s\n' "$(process_count)"
    printf '}\n'
}

# ============================================================
# MINIMAL
# ============================================================

minimal_output() {
    local memory
    local disk
    local cpu

    memory="$(memory_info)"
    disk="$(disk_info)"
    cpu="$(cpu_usage)"

    printf "%b%s%b\n" \
        "$CYAN" \
        "$OS_NAME" \
        "$RESET"

    printf "%s | %s | %s\n" \
        "$KERNEL" \
        "$ARCH" \
        "$CPU_MODEL"

    printf "CPU %s%% | RAM %s%% | DISK %s%%\n" \
        "$cpu" \
        "$(awk '{print $5}' <<< "$memory")" \
        "$(awk '{print $1}' <<< "$disk")"
}

# ============================================================
# ABOUT
# ============================================================

about() {
    printf '%b%b' "$CLEAR" "$HIDE_CURSOR"

    printf "%bSYSPECT-FETCH%b\n\n" \
        "$BOLD" \
        "$RESET"

    info "Version" "$VERSION"
    info "Author" "$AUTHOR"
    info "License" "MIT"
    info "Platform" "Linux"
    info "GUI" "None"
    info "Telemetry" "None"
    info "Antivirus" "None"
    info "Fastfetch" "Not used"
    info "Neofetch" "Not used"
    info "Pfetch" "Not used"

    cat <<'TEXT'

Syspect-fetch is a lightweight Linux system information
and monitoring utility.

It is independently implemented and does not rely on
Fastfetch, Neofetch or Pfetch.

Distro artwork is selected from /etc/os-release and
rendered by Syspect-fetch itself.

IMPORTANT SHELL DISCLAIMER

If your terminal displays:

>

and waits for more input, Bash is usually waiting for an
unfinished command.

This is NOT a Syspect-fetch error.

Press:

  Ctrl+C

to cancel the unfinished shell command.

Then return to the normal shell prompt and run:

  syspect-fetch

Do NOT continue past the `>` prompt with the installation
script.

FEATURES

  • Native distro detection
  • Native distro artwork
  • CPU monitoring
  • RAM monitoring
  • Swap monitoring
  • Disk monitoring
  • Network detection
  • Temperature detection
  • Load average
  • Uptime
  • Process count
  • Package count
  • Interactive interface
  • Live mode
  • Watch mode
  • JSON mode
  • Minimal mode
  • Doctor mode
  • Snapshot mode
  • Animated startup
  • No GUI
  • No telemetry
  • No antivirus
  • No Fastfetch dependency

Syspect-fetch is an independent project and is NOT an
official Void Linux project.

Created by Kayan Erkama.

TEXT
}

# ============================================================
# DOCTOR
# ============================================================

doctor() {
    printf '%b%b' "$CLEAR" "$HIDE_CURSOR"

    printf "%bSYSPECT-FETCH DOCTOR%b\n\n" \
        "$BOLD" \
        "$RESET"

    check_file() {
        local label="$1"
        local file="$2"

        if [[ -r "$file" ]]; then
            printf "  %b✓%b %s\n" \
                "$GREEN" "$RESET" "$label"
        else
            printf "  %b!%b %s\n" \
                "$YELLOW" "$RESET" "$label"
        fi
    }

    check_command() {
        local label="$1"
        local command="$2"

        if have "$command"; then
            printf "  %b✓%b %s\n" \
                "$GREEN" "$RESET" "$label"
        else
            printf "  %b!%b %s\n" \
                "$YELLOW" "$RESET" "$label"
        fi
    }

    check_file "/proc/stat" "/proc/stat"
    check_file "/proc/meminfo" "/proc/meminfo"
    check_file "/proc/cpuinfo" "/proc/cpuinfo"
    check_file "/proc/loadavg" "/proc/loadavg"
    check_file "/proc/uptime" "/proc/uptime"

    check_command "bash" bash
    check_command "awk" awk
    check_command "df" df
    check_command "uname" uname

    if have ip; then
        printf "  %b✓%b ip networking utility\n" \
            "$GREEN" "$RESET"
    else
        printf "  %b!%b ip unavailable; reduced network detection\n" \
            "$YELLOW" "$RESET"
    fi

    printf "\n"

    info "Detected OS" "$OS_NAME"
    info "Detected ID" "$OS_ID"
    info "Kernel" "$KERNEL"
    info "Architecture" "$ARCH"
    info "libc" "$(libc_name)"
    info "Init" "$(init_system)"

    printf "\n%bNo external fetcher is required.%b\n" \
        "$GREEN" \
        "$RESET"

    printf "%bDoctor complete.%b\n" \
        "$GREEN" \
        "$RESET"
}

# ============================================================
# SNAPSHOT
# ============================================================

snapshot() {
    local file

    file="$LOG_DIR/snapshot-$(date '+%Y%m%d-%H%M%S').txt"

    {
        echo "Syspect-fetch $VERSION"
        echo "Created by $AUTHOR"
        echo "Date: $(date)"
        echo
        echo "OS: $OS_NAME"
        echo "OS ID: $OS_ID"
        echo "Kernel: $KERNEL"
        echo "Architecture: $ARCH"
        echo "CPU: $CPU_MODEL"
        echo "CPU usage: $(cpu_usage)%"
        echo "RAM: $(awk '{print $5 "%"}' <<< "$(memory_info)")"
        echo "Disk: $(awk '{print $1 "%"}' <<< "$(disk_info)")"
        echo "Load: $(load_average)"
        echo "Temperature: $(temperature)"
        echo "Uptime: $(uptime_text)"
        echo "Processes: $(process_count)"
        echo "Interface: $(network_interface)"
        echo "IPv4: $(network_ipv4 "$(network_interface)")"
    } > "$file"

    printf "%b✓ Snapshot saved:%b %s\n" \
        "$GREEN" \
        "$RESET" \
        "$file"
}

# ============================================================
# LOGO
# ============================================================

logo_command() {
    printf '%b%b' "$CLEAR" "$HIDE_CURSOR"

    show_logo

    printf "\n"

    info "Detected distro" "$OS_NAME"
    info "Logo source" "Syspect-fetch native"
    info "External logo program" "None"
}

# ============================================================
# HELP
# ============================================================

help() {
    cat <<'HELP'

SYSPECT-FETCH

Fast native Linux system information.

USAGE

  syspect-fetch
  syspect-fetch --live
  syspect-fetch --watch 2
  syspect-fetch --json
  syspect-fetch --minimal
  syspect-fetch --doctor
  syspect-fetch --about
  syspect-fetch --logo
  syspect-fetch --snapshot

OPTIONS

  -l, --live        Live monitoring
  -w, --watch N     Watch mode
  -j, --json        JSON output
  -m, --minimal     Minimal output
  -d, --doctor      Diagnostics
  -a, --about       About
      --logo        Show native distro artwork
      --snapshot    Save a system snapshot
  -v, --version     Show version
  -h, --help        Show help

INTERACTIVE COMMANDS

  a     About
  l     Live
  w     Watch
  d     Doctor
  j     JSON
  m     Minimal
  r     Refresh
  s     Snapshot
  L     Logo
  q     Quit

IMPORTANT SHELL DISCLAIMER

If your terminal displays:

>

and waits for more input, Bash is usually waiting for an
unfinished command.

This is NOT a Syspect-fetch error.

Press Ctrl+C to cancel the unfinished shell command.

Then return to the normal shell prompt and run:

  syspect-fetch

Do not continue typing into the `>` prompt.

DEPENDENCIES

Required:

  bash
  awk
  df
  uname

Optional:

  ip

NO Fastfetch.
NO Neofetch.
NO Pfetch.
NO antivirus.
NO GUI.
NO telemetry.

HELP
}

# ============================================================
# COMMAND LINE
# ============================================================

case "${1:-}" in

    --live|-l)
        live_mode
        exit
        ;;

    --watch|-w)
        watch_mode "${2:-2}"
        exit
        ;;

    --json|-j)
        json_output
        exit
        ;;

    --minimal|-m)
        minimal_output
        exit
        ;;

    --doctor|-d)
        doctor
        exit
        ;;

    --about|-a)
        about
        exit
        ;;

    --logo)
        logo_command
        exit
        ;;

    --snapshot)
        snapshot
        exit
        ;;

    --version|-v)
        echo "$APP $VERSION"
        exit
        ;;

    --help|-h)
        help
        exit
        ;;

    "")
        ;;

    *)
        printf "%bUnknown option:%b %s\n\n" \
            "$RED" \
            "$RESET" \
            "$1"

        help
        exit 2
        ;;

esac

# ============================================================
# NON-TTY
# ============================================================

if [[ ! -t 1 ]]; then
    minimal_output
    exit 0
fi

# ============================================================
# START
# ============================================================

startup_animation

# ============================================================
# INTERACTIVE MODE
# ============================================================

while :; do

    render_full

    IFS= read -r command || break

    case "$command" in

        a|A)
            about
            printf "\nPress Enter to return..."
            IFS= read -r _ || true
            ;;

        l)
            live_mode
            ;;

        w)
            watch_mode 2
            ;;

        d|D)
            doctor
            printf "\nPress Enter to return..."
            IFS= read -r _ || true
            ;;

        j|J)
            printf '%b%b' "$CLEAR" "$SHOW_CURSOR"
            json_output
            printf "\nPress Enter to return..."
            IFS= read -r _ || true
            ;;

        m|M)
            printf '%b%b' "$CLEAR" "$SHOW_CURSOR"
            minimal_output
            printf "\nPress Enter to return..."
            IFS= read -r _ || true
            ;;

        r|R)
            CPU_READY=0
            ;;

        s|S)
            printf '%b%b' "$CLEAR" "$SHOW_CURSOR"
            snapshot
            printf "\nPress Enter to return..."
            IFS= read -r _ || true
            ;;

        L)
            logo_command
            printf "\nPress Enter to return..."
            IFS= read -r _ || true
            ;;

        q|Q|quit|exit)
            break
            ;;

        "")
            ;;

        *)
            printf "\n%bUnknown command:%b %s\n" \
                "$YELLOW" \
                "$RESET" \
                "$command"

            sleep 0.4
            ;;

    esac

done

printf '%b%bSyspect-fetch terminated.%b\n' \
    "$RESET" \
    "$SHOW_CURSOR" \
    "$RESET"

SYSP

chmod +x "$HOME/.local/bin/syspect-fetch"

cat > "$HOME/.config/syspect-fetch/README.md" <<'README'
# Syspect-fetch

Fast, lightweight, native Linux system information.

Created by **Kayan Erkama**.

## What is Syspect-fetch?

Syspect-fetch is a terminal system-information and monitoring utility
for Linux.

It is designed to work directly with Linux system interfaces instead
of depending on another system-fetch application.

## Shell disclaimer: the `>` prompt

If your terminal suddenly shows:

```text
>
