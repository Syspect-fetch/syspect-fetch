mkdir -p "$HOME/.local/bin" "$HOME/.config/syspect-fetch" "$HOME/.config/syspect-fetch/logs" && \
rm -f \
  "$HOME/.local/bin/syspect-fetch" \
  "$HOME/.local/bin/syspect-fetch-av" \
  "$HOME/.local/bin/syspectav" \
  "$HOME/.local/bin/SyspectAV" \
  "$HOME/.local/bin/syspectAV" \
  "$HOME/.config/syspect-fetch/fastfetch.conf" \
  "$HOME/.config/syspect-fetch/fastfetch.jsonc" && \
cat > "$HOME/.local/bin/syspect-fetch" <<'SYSP'
#!/usr/bin/env bash

# ╔══════════════════════════════════════════════════════════════════════╗
# ║                         SYSPECT-FETCH                               ║
# ║                         Version 10.0.0                              ║
# ║                                                                    ║
# ║  Native Linux system information / monitoring utility.             ║
# ║  No Fastfetch • No Neofetch • No Pfetch • No telemetry             ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -u
set -o pipefail

VERSION="10.0.0"
APP="SYSPECT-FETCH"
AUTHOR="Kayan Erkama"
CONFIG_DIR="${HOME}/.config/syspect-fetch"
LOG_DIR="${CONFIG_DIR}/logs"

mkdir -p "$CONFIG_DIR" "$LOG_DIR" 2>/dev/null || true

ESC=$'\033'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
BLACK="${ESC}[30m"
RED="${ESC}[91m"
GREEN="${ESC}[92m"
YELLOW="${ESC}[93m"
BLUE="${ESC}[94m"
MAGENTA="${ESC}[95m"
CYAN="${ESC}[96m"
WHITE="${ESC}[97m"

CLEAR="${ESC}[2J${ESC}[H"
HIDE="${ESC}[?25l"
SHOW="${ESC}[?25h"
BELL="${ESC}[?5h"
NOBELL="${ESC}[?5l"

ANIMATION=1
CPU_READY=0
CPU_OLD_IDLE=0
CPU_OLD_TOTAL=0

# ──────────────────────────────────────────────────────────────────────
# Cleanup
# ──────────────────────────────────────────────────────────────────────

cleanup() {
    printf '%b' "${RESET}${SHOW}${NOBELL}"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ──────────────────────────────────────────────────────────────────────
# Generic helpers
# ──────────────────────────────────────────────────────────────────────

have() {
    command -v "$1" >/dev/null 2>&1
}

is_uint() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

is_decimal() {
    [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

num_or_zero() {
    if is_decimal "${1:-}"; then
        printf '%s\n' "$1"
    else
        printf '0\n'
    fi
}

term_width() {
    local w

    if have tput; then
        w="$(tput cols 2>/dev/null || true)"
    else
        w=""
    fi

    if ! is_uint "$w" || (( w < 60 )); then
        w=80
    fi

    printf '%s\n' "$w"
}

repeat_char() {
    local char="${1:-}"
    local count="${2:-0}"
    local i

    is_uint "$count" || count=0

    for ((i=0; i<count; i++)); do
        printf '%s' "$char"
    done
}

clamp_percent() {
    awk -v n="$(num_or_zero "${1:-0}")" '
        BEGIN {
            if (n < 0) n=0
            if (n > 100) n=100
            printf "%.0f", n
        }
    '
}

human_bytes() {
    awk -v n="$(num_or_zero "${1:-0}")" '
        BEGIN {
            if (n < 1024)
                printf "%.0f B", n
            else if (n < 1024^2)
                printf "%.1f KiB", n/1024
            else if (n < 1024^3)
                printf "%.1f MiB", n/(1024^2)
            else if (n < 1024^4)
                printf "%.2f GiB", n/(1024^3)
            else
                printf "%.2f TiB", n/(1024^4)
        }
    '
}

json_escape() {
    local value="${1:-}"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"

    printf '%s' "$value"
}

# ──────────────────────────────────────────────────────────────────────
# Static system information
# ──────────────────────────────────────────────────────────────────────

OS_ID="linux"
OS_NAME="Linux"
OS_VERSION="unknown"

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release 2>/dev/null || true

    OS_ID="${ID:-linux}"
    OS_NAME="${PRETTY_NAME:-${NAME:-Linux}}"
    OS_VERSION="${VERSION_ID:-unknown}"
fi

KERNEL="$(uname -r 2>/dev/null || printf 'unknown')"
ARCH="$(uname -m 2>/dev/null || printf 'unknown')"
HOSTNAME_VALUE="$(hostname 2>/dev/null || printf 'unknown')"
USERNAME="${USER:-$(id -un 2>/dev/null || printf 'unknown')}"
SHELL_PATH="${SHELL:-unknown}"
SHELL_NAME="$(basename -- "$SHELL_PATH" 2>/dev/null || printf 'unknown')"

CPU_MODEL="$(
    awk -F': ' '
        /^model name[[:space:]]*:/ { print $2; exit }
        /^Hardware[[:space:]]*:/   { print $2; exit }
        /^Processor[[:space:]]*:/  { print $2; exit }
    ' /proc/cpuinfo 2>/dev/null
)"

[[ -n "$CPU_MODEL" ]] || CPU_MODEL="Unknown CPU"

CPU_THREADS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
is_uint "$CPU_THREADS" || CPU_THREADS=0

# ──────────────────────────────────────────────────────────────────────
# CPU
# ──────────────────────────────────────────────────────────────────────

cpu_usage() {
    local idle total idle_delta total_delta

    [[ -r /proc/stat ]] || {
        printf '0\n'
        return
    }

    read -r idle total <<< "$(
        awk '
            $1 == "cpu" {
                idle=$5+$6
                total=$2+$3+$4+$5+$6+$7+$8+$9+$10
                print idle, total
                exit
            }
        ' /proc/stat 2>/dev/null
    )"

    if ! is_uint "${idle:-}" || ! is_uint "${total:-}"; then
        printf '0\n'
        return
    fi

    if (( CPU_READY == 0 )); then
        CPU_OLD_IDLE=$idle
        CPU_OLD_TOTAL=$total
        CPU_READY=1
        printf '0\n'
        return
    fi

    idle_delta=$((idle - CPU_OLD_IDLE))
    total_delta=$((total - CPU_OLD_TOTAL))

    CPU_OLD_IDLE=$idle
    CPU_OLD_TOTAL=$total

    if (( total_delta <= 0 || idle_delta < 0 )); then
        printf '0\n'
        return
    fi

    awk -v i="$idle_delta" -v t="$total_delta" '
        BEGIN {
            u=((t-i)/t)*100
            if (u < 0) u=0
            if (u > 100) u=100
            printf "%.0f", u
        }
    '
}

cpu_frequency() {
    local freq=""

    if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
        freq="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || true)"
        if is_uint "$freq"; then
            awk -v n="$freq" 'BEGIN { printf "%.2f GHz", n/1000000 }'
            return
        fi
    fi

    awk -F': ' '
        /cpu MHz/ {
            printf "%.2f GHz", $2/1000
            exit
        }
    ' /proc/cpuinfo 2>/dev/null
}

# ──────────────────────────────────────────────────────────────────────
# Memory
# ──────────────────────────────────────────────────────────────────────

memory_info() {
    [[ -r /proc/meminfo ]] || {
        printf '0 0 0 0 0 0\n'
        return
    }

    awk '
        /^MemTotal:/     { total=$2 }
        /^MemAvailable:/ { available=$2 }
        /^MemFree:/      { free=$2 }
        /^Buffers:/      { buffers=$2 }
        /^Cached:/       { cached=$2 }
        /^SReclaimable:/ { reclaim=$2 }

        /^SwapTotal:/    { swap_total=$2 }
        /^SwapFree:/     { swap_free=$2 }

        END {
            if (total <= 0) {
                print "0 0 0 0 0 0"
                exit
            }

            if (available <= 0)
                available=free+buffers+cached+reclaim

            used=total-available
            if (used < 0) used=0

            swap_used=swap_total-swap_free
            if (swap_used < 0) swap_used=0

            ram_percent=(used/total)*100

            if (swap_total > 0)
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
        }
    ' /proc/meminfo 2>/dev/null
}

# ──────────────────────────────────────────────────────────────────────
# Disk
# ──────────────────────────────────────────────────────────────────────

disk_info() {
    df -P -B1 / 2>/dev/null |
        awk '
            NR == 2 {
                gsub("%", "", $5)

                if ($5 !~ /^[0-9]+$/) $5=0
                if ($3 !~ /^[0-9]+$/) $3=0
                if ($2 !~ /^[0-9]+$/) $2=0
                if ($4 !~ /^[0-9]+$/) $4=0

                print $5, $3, $2, $4
                exit
            }
        '
}

filesystem() {
    df -T / 2>/dev/null |
        awk 'NR == 2 { print $2; exit }'
}

# ──────────────────────────────────────────────────────────────────────
# Network
# ──────────────────────────────────────────────────────────────────────

network_interface() {
    if have ip; then
        ip route 2>/dev/null |
            awk '$1 == "default" { print $5; exit }'
        return
    fi

    [[ -r /proc/net/route ]] || return

    awk '
        NR > 1 && $2 == "00000000" {
            print $1
            exit
        }
    ' /proc/net/route 2>/dev/null
}

network_ipv4() {
    local interface="${1:-}"

    [[ -n "$interface" ]] || {
        printf 'offline\n'
        return
    }

    if have ip; then
        ip -4 addr show dev "$interface" 2>/dev/null |
            awk '$1 == "inet" { print $2; exit }'
    fi
}

network_state() {
    local iface="${1:-}"

    [[ -n "$iface" ]] || {
        printf 'offline\n'
        return
    }

    if [[ -r "/sys/class/net/$iface/operstate" ]]; then
        cat "/sys/class/net/$iface/operstate" 2>/dev/null || printf 'unknown\n'
    else
        printf 'unknown\n'
    fi
}

# ──────────────────────────────────────────────────────────────────────
# Temperature
# ──────────────────────────────────────────────────────────────────────

temperature() {
    local total=0
    local count=0
    local file temp

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
        awk -v total="$total" -v count="$count" \
            'BEGIN { printf "%.0f°C", total/count/1000 }'
    else
        printf 'N/A\n'
    fi
}

# ──────────────────────────────────────────────────────────────────────
# System information
# ──────────────────────────────────────────────────────────────────────

load_average() {
    if [[ -r /proc/loadavg ]]; then
        awk '{ print $1 " / " $2 " / " $3 }' /proc/loadavg 2>/dev/null
    else
        printf 'N/A\n'
    fi
}

uptime_text() {
    [[ -r /proc/uptime ]] || {
        printf 'N/A\n'
        return
    }

    awk '
        {
            seconds=int($1)
            days=int(seconds/86400)
            hours=int((seconds%86400)/3600)
            minutes=int((seconds%3600)/60)

            if (days > 0)
                printf "%dd %dh %dm", days, hours, minutes
            else if (hours > 0)
                printf "%dh %dm", hours, minutes
            else
                printf "%dm", minutes
        }
    ' /proc/uptime 2>/dev/null
}

process_count() {
    local count=0
    local entry

    shopt -s nullglob

    for entry in /proc/[0-9]*; do
        [[ -d "$entry" ]] && ((count+=1))
    done

    shopt -u nullglob

    printf '%s\n' "$count"
}

init_system() {
    if [[ -d /run/systemd/system ]]; then
        printf 'systemd\n'
    elif [[ -d /run/runit || -d /etc/runit ]]; then
        printf 'runit\n'
    elif [[ -d /run/openrc ]]; then
        printf 'OpenRC\n'
    elif [[ -d /run/s6 ]]; then
        printf 's6\n'
    elif [[ -x /sbin/init ]]; then
        basename "$(readlink -f /sbin/init 2>/dev/null || printf '/sbin/init')" 2>/dev/null
    else
        printf 'unknown\n'
    fi
}

libc_name() {
    local ldd_version=""

    if have ldd; then
        ldd_version="$(ldd --version 2>&1 | head -n 1 || true)"

        case "$ldd_version" in
            *musl*|*musl-libc*)
                printf 'musl\n'
                return
                ;;
            *GNU*|*glibc*)
                printf 'glibc\n'
                return
                ;;
        esac
    fi

    if compgen -G '/lib/ld-musl-*.so.1' >/dev/null 2>&1; then
        printf 'musl\n'
    elif compgen -G '/lib*/ld-linux-*.so.*' >/dev/null 2>&1; then
        printf 'glibc\n'
    else
        printf 'unknown\n'
    fi
}

# ──────────────────────────────────────────────────────────────────────
# Package count
# ──────────────────────────────────────────────────────────────────────

package_count() {
    case "$OS_ID" in
        arch|artix|manjaro|endeavouros)
            if have pacman; then
                pacman -Qq 2>/dev/null | wc -l
            else
                printf 'N/A\n'
            fi
            ;;

        debian|ubuntu|linuxmint|pop|elementary)
            if have dpkg-query; then
                dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | wc -l
            else
                printf 'N/A\n'
            fi
            ;;

        fedora|rhel|centos|rocky|almalinux)
            if have rpm; then
                rpm -qa 2>/dev/null | wc -l
            else
                printf 'N/A\n'
            fi
            ;;

        alpine)
            if have apk; then
                apk info 2>/dev/null | wc -l
            else
                printf 'N/A\n'
            fi
            ;;

        void)
            if have xbps-query; then
                xbps-query -l 2>/dev/null | wc -l
            else
                printf 'N/A\n'
            fi
            ;;

        opensuse*|sles|suse)
            if have rpm; then
                rpm -qa 2>/dev/null | wc -l
            else
                printf 'N/A\n'
            fi
            ;;

        gentoo)
            if have qlist; then
                qlist -I 2>/dev/null | wc -l
            elif have equery; then
                equery list 2>/dev/null | wc -l
            else
                printf 'N/A\n'
            fi
            ;;

        *)
            printf 'N/A\n'
            ;;
    esac
}

# ──────────────────────────────────────────────────────────────────────
# GPU
# ──────────────────────────────────────────────────────────────────────

gpu_info() {
    local gpu=""

    if have lspci; then
        gpu="$(
            lspci 2>/dev/null |
                awk -F': ' '
                    /VGA compatible controller|3D controller|Display controller/ {
                        print $2
                        exit
                    }
                '
        )"
    fi

    if [[ -n "$gpu" ]]; then
        printf '%s\n' "$gpu"
        return
    fi

    if [[ -r /sys/class/drm/card0/device/uevent ]]; then
        gpu="$(awk -F= '/DRIVER=/{print $2;exit}' \
            /sys/class/drm/card0/device/uevent 2>/dev/null)"
    fi

    [[ -n "$gpu" ]] && printf '%s\n' "$gpu" || printf 'N/A\n'
}

# ──────────────────────────────────────────────────────────────────────
# Desktop / terminal
# ──────────────────────────────────────────────────────────────────────

desktop_environment() {
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        printf '%s\n' "$XDG_CURRENT_DESKTOP"
    elif [[ -n "${DESKTOP_SESSION:-}" ]]; then
        printf '%s\n' "$DESKTOP_SESSION"
    elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        printf 'Wayland\n'
    elif [[ -n "${DISPLAY:-}" ]]; then
        printf 'X11\n'
    else
        printf 'TTY\n'
    fi
}

terminal_name() {
    if [[ -n "${TERM_PROGRAM:-}" ]]; then
        printf '%s\n' "$TERM_PROGRAM"
    elif [[ -n "${WT_SESSION:-}" ]]; then
        printf 'Windows Terminal\n'
    elif [[ -n "${TERM:-}" ]]; then
        printf '%s\n' "$TERM"
    else
        printf 'unknown\n'
    fi
}

# ──────────────────────────────────────────────────────────────────────
# UI
# ──────────────────────────────────────────────────────────────────────

section() {
    local name="${1:-}"
    local width used remaining

    width="$(term_width)"
    used=$(( ${#name} + 7 ))
    remaining=$(( width - used ))

    (( remaining < 3 )) && remaining=3

    printf '\n%b── %s ' "$BLUE" "$name"
    repeat_char '─' "$remaining"
    printf '%b\n' "$RESET"
}

info() {
    printf '  %b%-18s%b %s\n' \
        "$CYAN" "$1" "$RESET" "${2:-N/A}"
}

progress_bar() {
    local percent width filled empty color

    percent="$(clamp_percent "${1:-0}")"
    width=32
    filled=$((percent * width / 100))
    empty=$((width - filled))

    if (( percent >= 90 )); then
        color="$RED"
    elif (( percent >= 70 )); then
        color="$YELLOW"
    else
        color="$GREEN"
    fi

    printf '  %b[%b' "$DIM" "$color"
    repeat_char '█' "$filled"
    printf '%b' "$DIM"
    repeat_char '░' "$empty"
    printf '%b] %3s%%%b\n' "$RESET" "$percent" "$RESET"
}

# ──────────────────────────────────────────────────────────────────────
# SYSPECT logo
# ──────────────────────────────────────────────────────────────────────

syspect_logo() {
    local color="${1:-$CYAN}"

    printf '%b' "$color"
    cat <<'ART'
   ███████╗██╗   ██╗███████╗██████╗ ███████╗ ██████╗████████╗
   ██╔════╝╚██╗ ██╔╝██╔════╝██╔══██╗██╔════╝██╔════╝╚══██╔══╝
   ███████╗ ╚████╔╝ ███████╗██████╔╝█████╗  ██║        ██║
   ╚════██║  ╚██╔╝  ╚════██║██╔═══╝ ██╔══╝  ██║        ██║
   ███████║   ██║   ███████║██║     ███████╗╚██████╗   ██║
   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚══════╝ ╚═════╝   ╚═╝

                       ┌───────────────┐
                       │    F E T C H  │
                       └───────────────┘
ART
    printf '%b' "$RESET"
}

mini_logo() {
    printf '%b' "$CYAN"
    cat <<'ART'
      ███████╗██╗   ██╗███████╗██████╗ ███████╗ ██████╗████████╗
      ██╔════╝╚██╗ ██╔╝██╔════╝██╔══██╗██╔════╝██╔════╝╚══██╔══╝
      ███████╗ ╚████╔╝ ███████╗██████╔╝█████╗  ██║        ██║
      ╚════██║  ╚██╔╝  ╚════██║██╔═══╝ ██╔══╝  ██║        ██║
      ███████║   ██║   ███████║██║     ███████╗╚██████╗   ██║
      ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚══════╝ ╚═════╝   ╚═╝
ART
    printf '%b' "$RESET"
}

# ──────────────────────────────────────────────────────────────────────
# Native distro logos
# ──────────────────────────────────────────────────────────────────────

logo_arch() {
cat <<'ART'
                         /\
                        /  \
                       / /\ \
                      / /  \ \
                     / /____\ \
                    /__________\
                         ARCH
ART
}

logo_debian() {
cat <<'ART'
                       .--.
                    .-(    )-.
                   (___.__)__) 
                     Debian
ART
}

logo_ubuntu() {
cat <<'ART'
                         .-.
                      .-(   )-.
                    .'   \ /   '.
                   /  .-  O  -.  \
                   \ (   / \   ) /
                    '.         .'
                      '-.___.-'
                       Ubuntu
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
                        Fedora
ART
}

logo_void() {
cat <<'ART'
                         .--.
                      .-(    )-.
                     /  .----.  \
                    |  /      \  |
                    | |  VOID  | |
                    |  \      /  |
                     \  '----'  /
                      '-.____.-'
                          Void
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
                        NixOS
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
                        Alpine
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
                         Manjaro
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
                         Gentoo
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
                       Slackware
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

logo_generic() {
cat <<'ART'
                       .────────.
                     .'  LINUX   '.
                    /   ┌─────┐   \
                   |    │ SYS │    |
                   |    │ PECT│    |
                    \   └─────┘   /
                     '.         .'
                       '───────'
ART
}

show_distro_logo() {
    case "$OS_ID" in
        arch|artix) logo_arch ;;
        debian) logo_debian ;;
        ubuntu|pop|linuxmint|elementary) logo_ubuntu ;;
        fedora|rhel|centos|rocky|almalinux) logo_fedora ;;
        void) logo_void ;;
        nixos) logo_nixos ;;
        alpine) logo_alpine ;;
        manjaro) logo_manjaro ;;
        gentoo) logo_gentoo ;;
        slackware) logo_slackware ;;
        opensuse*|suse|sles) logo_opensuse ;;
        *) logo_generic ;;
    esac
}

# ──────────────────────────────────────────────────────────────────────
# Animation
# ──────────────────────────────────────────────────────────────────────

startup_animation() {
    [[ -t 1 ]] || return
    (( ANIMATION == 1 )) || return

    printf '%b%b' "$CLEAR" "$HIDE"

    local frames=(
        '░▒▓ SYSPECT-FETCH ▓▒░'
        '▒▓█ SYSPECT-FETCH █▓▒'
        '▓██ SYSPECT-FETCH ██▓'
        '████ SYSPECT-FETCH ████'
    )

    local frame

    for frame in "${frames[@]}"; do
        printf '%b\n\n' "$CYAN"
        printf '                    %s\n' "$frame"
        printf '%b' "$RESET"
        sleep 0.055
        printf '%b' "${ESC}[2K${ESC}[1A"
    done

    printf '%b%b' "$CLEAR" "$HIDE"
}

# ──────────────────────────────────────────────────────────────────────
# Full screen renderer
# ──────────────────────────────────────────────────────────────────────

render_full() {
    local memory disk
    local ram_used ram_total swap_used swap_total ram_percent swap_percent
    local disk_percent disk_used disk_total
    local cpu iface ip

    memory="$(memory_info)"
    disk="$(disk_info)"

    read -r ram_used ram_total swap_used swap_total ram_percent swap_percent <<< "$memory"
    read -r disk_percent disk_used disk_total _ <<< "$disk"

    cpu="$(cpu_usage)"
    iface="$(network_interface)"
    ip="$(network_ipv4 "$iface")"

    printf '%b%b' "$CLEAR" "$HIDE"

    printf '%b' "$CYAN"
    mini_logo
    printf '%b' "$RESET"

    printf '\n  %b%s%b %bv%s%b\n' \
        "$BOLD" "$APP" "$RESET" "$DIM" "$VERSION" "$RESET"

    printf '  %bNative Linux system intelligence%b\n' "$DIM" "$RESET"

    section "SYSTEM"

    info "OS" "$OS_NAME"
    info "Kernel" "$KERNEL"
    info "Architecture" "$ARCH"
    info "Hostname" "$HOSTNAME_VALUE"
    info "User" "$USERNAME"
    info "Shell" "$SHELL_NAME"
    info "Init" "$(init_system)"
    info "libc" "$(libc_name)"
    info "Desktop" "$(desktop_environment)"
    info "Terminal" "$(terminal_name)"
    info "Packages" "$(package_count)"

    section "PROCESSOR"

    info "CPU" "$CPU_MODEL"
    info "Threads" "$CPU_THREADS"
    info "Frequency" "$(cpu_frequency)"
    info "Load" "$(load_average)"
    info "Usage" "${cpu}%"
    progress_bar "$cpu"

    section "MEMORY"

    info "RAM" "$(human_bytes "$ram_used") / $(human_bytes "$ram_total")"
    progress_bar "$ram_percent"

    if awk -v n="$(num_or_zero "$swap_total")" 'BEGIN { exit !(n > 0) }'; then
        info "Swap" "$(human_bytes "$swap_used") / $(human_bytes "$swap_total")"
        progress_bar "$swap_percent"
    else
        info "Swap" "Disabled"
    fi

    section "STORAGE"

    info "Root" "$(human_bytes "$disk_used") / $(human_bytes "$disk_total")"
    progress_bar "$disk_percent"
    info "Filesystem" "$(filesystem)"

    section "GRAPHICS"

    info "GPU" "$(gpu_info)"

    section "NETWORK"

    info "Interface" "${iface:-offline}"
    info "State" "$(network_state "$iface")"
    info "IPv4" "${ip:-offline}"

    section "RUNTIME"

    info "Uptime" "$(uptime_text)"
    info "Processes" "$(process_count)"
    info "Temperature" "$(temperature)"

    section "SYSPECT"

    info "Version" "$VERSION"
    info "Telemetry" "Disabled"
    info "External fetcher" "None"
    info "Antivirus" "None"
    info "GUI" "None"

    printf '\n%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' \
        "$BLUE" "$RESET"

    printf '  %b[a]%b About   ' "$CYAN" "$RESET"
    printf '%b[l]%b Live   ' "$CYAN" "$RESET"
    printf '%b[w]%b Watch   ' "$CYAN" "$RESET"
    printf '%b[d]%b Doctor\n' "$CYAN" "$RESET"

    printf '  %b[j]%b JSON    ' "$CYAN" "$RESET"
    printf '%b[m]%b Minimal ' "$CYAN" "$RESET"
    printf '%b[r]%b Refresh ' "$CYAN" "$RESET"
    printf '%b[s]%b Snapshot\n' "$CYAN" "$RESET"

    printf '  %b[L]%b Logo    ' "$CYAN" "$RESET"
    printf '%b[q]%b Quit\n\n' "$CYAN" "$RESET"

    printf '  %bSYSPECT>%b ' "$CYAN" "$RESET"
}

# ──────────────────────────────────────────────────────────────────────
# Live mode
# ──────────────────────────────────────────────────────────────────────

live_mode() {
    CPU_READY=0

    while :; do
        local memory disk cpu

        memory="$(memory_info)"
        disk="$(disk_info)"
        cpu="$(cpu_usage)"

        printf '%b%b' "$CLEAR" "$HIDE"

        printf '%b' "$CYAN"
        mini_logo
        printf '%b\n' "$RESET"

        printf '  %bLIVE MONITOR%b  %s\n\n' \
            "$BOLD" "$RESET" "$(date '+%Y-%m-%d %H:%M:%S')"

        printf '%bCPU%b\n' "$CYAN" "$RESET"
        progress_bar "$cpu"

        printf '%bRAM%b\n' "$CYAN" "$RESET"
        progress_bar "$(awk '{print $5}' <<< "$memory")"

        printf '%bDISK%b\n' "$CYAN" "$RESET"
        progress_bar "$(awk '{print $1}' <<< "$disk")"

        printf '\n'
        info "Load" "$(load_average)"
        info "Temperature" "$(temperature)"
        info "Processes" "$(process_count)"
        info "Uptime" "$(uptime_text)"

        printf '\n%bPress Ctrl+C to exit.%b\n' "$DIM" "$RESET"

        sleep 1
    done
}

watch_mode() {
    local delay="${1:-2}"

    is_decimal "$delay" || delay=2

    # sleep rejects negative values.
    if awk -v n="$delay" 'BEGIN { exit !(n >= 0.1) }'; then
        :
    else
        delay=2
    fi

    CPU_READY=0

    while :; do
        local memory disk cpu

        memory="$(memory_info)"
        disk="$(disk_info)"
        cpu="$(cpu_usage)"

        printf '%b%b' "$CLEAR" "$HIDE"

        printf '%bSYSPECT WATCH%b\n\n' "$BOLD" "$RESET"

        info "CPU" "${cpu}%"
        info "RAM" "$(awk '{print $5 "%"}' <<< "$memory")"
        info "Disk" "$(awk '{print $1 "%"}' <<< "$disk")"
        info "Load" "$(load_average)"
        info "Temperature" "$(temperature)"
        info "Processes" "$(process_count)"
        info "Uptime" "$(uptime_text)"

        printf '\n%bRefresh: %ss%b\n' "$DIM" "$delay" "$RESET"

        sleep "$delay"
    done
}

# ──────────────────────────────────────────────────────────────────────
# JSON
# ──────────────────────────────────────────────────────────────────────

json_output() {
    local memory disk iface ip

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
    printf '  "os_version":"%s",\n' "$(json_escape "$OS_VERSION")"
    printf '  "kernel":"%s",\n' "$(json_escape "$KERNEL")"
    printf '  "architecture":"%s",\n' "$(json_escape "$ARCH")"
    printf '  "hostname":"%s",\n' "$(json_escape "$HOSTNAME_VALUE")"
    printf '  "user":"%s",\n' "$(json_escape "$USERNAME")"
    printf '  "shell":"%s",\n' "$(json_escape "$SHELL_NAME")"
    printf '  "init":"%s",\n' "$(json_escape "$(init_system)")"
    printf '  "libc":"%s",\n' "$(json_escape "$(libc_name)")"
    printf '  "desktop":"%s",\n' "$(json_escape "$(desktop_environment)")"
    printf '  "terminal":"%s",\n' "$(json_escape "$(terminal_name)")"
    printf '  "cpu":"%s",\n' "$(json_escape "$CPU_MODEL")"
    printf '  "threads":%s,\n' "$CPU_THREADS"
    printf '  "cpu_percent":%s,\n' "$(cpu_usage)"
    printf '  "ram_percent":%s,\n' "$(awk '{print $5}' <<< "$memory")"
    printf '  "swap_percent":%s,\n' "$(awk '{print $6}' <<< "$memory")"
    printf '  "disk_percent":%s,\n' "$(awk '{print $1}' <<< "$disk")"
    printf '  "filesystem":"%s",\n' "$(json_escape "$(filesystem)")"
    printf '  "gpu":"%s",\n' "$(json_escape "$(gpu_info)")"
    printf '  "interface":"%s",\n' "$(json_escape "${iface:-offline}")"
    printf '  "network_state":"%s",\n' "$(json_escape "$(network_state "$iface")")"
    printf '  "ipv4":"%s",\n' "$(json_escape "${ip:-offline}")"
    printf '  "load":"%s",\n' "$(json_escape "$(load_average)")"
    printf '  "temperature":"%s",\n' "$(json_escape "$(temperature)")"
    printf '  "uptime":"%s",\n' "$(json_escape "$(uptime_text)")"
    printf '  "processes":%s\n' "$(process_count)"
    printf '}\n'
}

# ──────────────────────────────────────────────────────────────────────
# Minimal
# ──────────────────────────────────────────────────────────────────────

minimal_output() {
    local memory disk cpu

    memory="$(memory_info)"
    disk="$(disk_info)"
    cpu="$(cpu_usage)"

    printf '%b%s%b\n' "$CYAN" "$OS_NAME" "$RESET"

    printf '%s | %s | %s\n' \
        "$KERNEL" "$ARCH" "$CPU_MODEL"

    printf 'CPU %s%% | RAM %s%% | DISK %s%%\n' \
        "$cpu" \
        "$(awk '{print $5}' <<< "$memory")" \
        "$(awk '{print $1}' <<< "$disk")"
}

# ──────────────────────────────────────────────────────────────────────
# About
# ──────────────────────────────────────────────────────────────────────

about() {
    printf '%b%b' "$CLEAR" "$HIDE"

    printf '%bSYSPECT-FETCH%b\n\n' "$BOLD" "$RESET"

    info "Version" "$VERSION"
    info "Author" "$AUTHOR"
    info "License" "MIT"
    info "Platform" "Linux"
    info "Architecture" "$ARCH"

    cat <<'TEXT'

Syspect-fetch is a native Linux system information and
monitoring utility.

DESIGN

  • Native Linux interfaces
  • No Fastfetch dependency
  • No Neofetch dependency
  • No Pfetch dependency
  • No telemetry
  • No antivirus component
  • No background service
  • No root requirement
  • JSON output
  • Live monitoring
  • Watch mode
  • Diagnostics
  • Snapshots
  • Animated startup
  • Native distro artwork
  • SYSPECT ASCII branding

The program is intended to be safe to install in:

  ~/.local/bin/syspect-fetch

Created by Kayan Erkama.

TEXT
}

# ──────────────────────────────────────────────────────────────────────
# Doctor
# ──────────────────────────────────────────────────────────────────────

doctor() {
    printf '%b%b' "$CLEAR" "$HIDE"

    printf '%bSYSPECT-FETCH DOCTOR%b\n\n' "$BOLD" "$RESET"

    check_file() {
        local label="$1"
        local file="$2"

        if [[ -r "$file" ]]; then
            printf '  %b✓%b %s\n' "$GREEN" "$RESET" "$label"
        else
            printf '  %b!%b %s\n' "$YELLOW" "$RESET" "$label"
        fi
    }

    check_command() {
        local label="$1"
        local command="$2"

        if have "$command"; then
            printf '  %b✓%b %s\n' "$GREEN" "$RESET" "$label"
        else
            printf '  %b!%b %s\n' "$YELLOW" "$RESET" "$label"
        fi
    }

    check_file "/proc/stat" /proc/stat
    check_file "/proc/meminfo" /proc/meminfo
    check_file "/proc/cpuinfo" /proc/cpuinfo
    check_file "/proc/loadavg" /proc/loadavg
    check_file "/proc/uptime" /proc/uptime
    check_file "/etc/os-release" /etc/os-release

    check_command "bash" bash
    check_command "awk" awk
    check_command "df" df
    check_command "uname" uname
    check_command "hostname" hostname

    if have ip; then
        printf '  %b✓%b ip networking utility\n' "$GREEN" "$RESET"
    else
        printf '  %b!%b ip unavailable; network detection is reduced\n' \
            "$YELLOW" "$RESET"
    fi

    printf '\n'

    info "Detected OS" "$OS_NAME"
    info "Detected ID" "$OS_ID"
    info "Kernel" "$KERNEL"
    info "Architecture" "$ARCH"
    info "CPU" "$CPU_MODEL"
    info "libc" "$(libc_name)"
    info "Init" "$(init_system)"

    printf '\n%bDoctor complete.%b\n' "$GREEN" "$RESET"
}

# ──────────────────────────────────────────────────────────────────────
# Snapshot
# ──────────────────────────────────────────────────────────────────────

snapshot() {
    local file

    file="$LOG_DIR/snapshot-$(date '+%Y%m%d-%H%M%S').txt"

    if ! {
        printf 'SYSPECT-FETCH %s\n' "$VERSION"
        printf 'Created by %s\n' "$AUTHOR"
        printf 'Date: %s\n\n' "$(date)"

        printf 'OS: %s\n' "$OS_NAME"
        printf 'OS ID: %s\n' "$OS_ID"
        printf 'Kernel: %s\n' "$KERNEL"
        printf 'Architecture: %s\n' "$ARCH"
        printf 'Hostname: %s\n' "$HOSTNAME_VALUE"
        printf 'CPU: %s\n' "$CPU_MODEL"
        printf 'CPU usage: %s%%\n' "$(cpu_usage)"
        printf 'RAM: %s%%\n' "$(awk '{print $5}' <<< "$(memory_info)")"
        printf 'Disk: %s%%\n' "$(awk '{print $1}' <<< "$(disk_info)")"
        printf 'GPU: %s\n' "$(gpu_info)"
        printf 'Load: %s\n' "$(load_average)"
        printf 'Temperature: %s\n' "$(temperature)"
        printf 'Uptime: %s\n' "$(uptime_text)"
        printf 'Processes: %s\n' "$(process_count)"
        printf 'Interface: %s\n' "$(network_interface)"
        printf 'IPv4: %s\n' "$(network_ipv4 "$(network_interface)")"
    } > "$file"; then
        printf '%bFailed to write snapshot.%b\n' "$RED" "$RESET"
        return 1
    fi

    printf '%b✓%b Snapshot saved: %s\n' \
        "$GREEN" "$RESET" "$file"
}

# ──────────────────────────────────────────────────────────────────────
# Logo command
# ──────────────────────────────────────────────────────────────────────

logo_command() {
    printf '%b%b' "$CLEAR" "$HIDE"

    printf '%b' "$CYAN"
    syspect_logo "$CYAN"
    printf '%b\n' "$RESET"

    printf '%bDISTRO ARTWORK%b\n\n' "$BOLD" "$RESET"

    show_distro_logo

    printf '\n'
    info "Detected distro" "$OS_NAME"
    info "Logo renderer" "Syspect-fetch native"
    info "External logo program" "None"
}

# ──────────────────────────────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────────────────────────────

help() {
    cat <<'HELP'

SYSPECT-FETCH

Native Linux system information and monitoring.

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
  -w, --watch N     Refresh every N seconds
  -j, --json        JSON output
  -m, --minimal     Compact output
  -d, --doctor      Diagnostics
  -a, --about       About
      --logo        SYSPECT + distro artwork
      --snapshot    Save a system snapshot
  -v, --version     Show version
  -h, --help        Show help

INTERACTIVE

  a       About
  l       Live
  w       Watch
  d       Doctor
  j       JSON
  m       Minimal
  r       Refresh
  s       Snapshot
  L       Logo
  q       Quit

DEPENDENCIES

Required:
  bash
  awk
  df
  uname
  hostname

Optional:
  ip
  lspci

The program does not require Fastfetch, Neofetch, Pfetch,
sudo, root access, a GUI, or a background daemon.

HELP
}

# ──────────────────────────────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────────────────────────────

case "${1:-}" in
    --live|-l)
        live_mode
        exit 0
        ;;

    --watch|-w)
        watch_mode "${2:-2}"
        exit 0
        ;;

    --json|-j)
        json_output
        exit 0
        ;;

    --minimal|-m)
        minimal_output
        exit 0
        ;;

    --doctor|-d)
        doctor
        exit 0
        ;;

    --about|-a)
        about
        exit 0
        ;;

    --logo)
        logo_command
        exit 0
        ;;

    --snapshot)
        snapshot
        exit $?
        ;;

    --version|-v)
        printf '%s %s\n' "$APP" "$VERSION"
        exit 0
        ;;

    --help|-h)
        help
        exit 0
        ;;

    "")
        ;;

    *)
        printf '%bUnknown option:%b %s\n\n' "$RED" "$RESET" "$1"
        help
        exit 2
        ;;
esac

# Non-interactive terminals get useful output instead of
# an interactive prompt.
if [[ ! -t 1 || ! -t 0 ]]; then
    minimal_output
    exit 0
fi

startup_animation

while :; do
    render_full

    IFS= read -r command || break

    case "$command" in
        a|A)
            about
            printf '\nPress Enter to return...'
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
            printf '\nPress Enter to return...'
            IFS= read -r _ || true
            ;;

        j|J)
            printf '%b%b' "$CLEAR" "$SHOW"
            json_output
            printf '\nPress Enter to return...'
            IFS= read -r _ || true
            ;;

        m|M)
            printf '%b%b' "$CLEAR" "$SHOW"
            minimal_output
            printf '\nPress Enter to return...'
            IFS= read -r _ || true
            ;;

        r|R)
            CPU_READY=0
            ;;

        s|S)
            printf '%b%b' "$CLEAR" "$SHOW"
            snapshot
            printf '\nPress Enter to return...'
            IFS= read -r _ || true
            ;;

        L)
            logo_command
            printf '\nPress Enter to return...'
            IFS= read -r _ || true
            ;;

        q|Q|quit|exit)
            break
            ;;

        "")
            ;;

        *)
            printf '\n%bUnknown command:%b %s\n' \
                "$YELLOW" "$RESET" "$command"
            sleep 0.4
            ;;
    esac
done

printf '%b%bSYSPECT-FETCH terminated.%b\n' \
    "$RESET" "$SHOW" "$RESET"

SYSP

chmod +x "$HOME/.local/bin/syspect-fetch" && \
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi && \
if "$HOME/.local/bin/syspect-fetch" --version >/dev/null 2>&1 && \
   "$HOME/.local/bin/syspect-fetch" --json >/dev/null 2>&1; then
    printf '\033[92m✓ SYSPECT-FETCH installed successfully.\033[0m\n'
    printf '\033[96m→\033[0m Run: \033[1msyspect-fetch\033[0m\n'
    printf '\033[96m→\033[0m Try: \033[1msyspect-fetch --doctor\033[0m\n'
else
    printf '\033[91m✗ Installation verification failed.\033[0m\n' >&2
    exit 1
fi
