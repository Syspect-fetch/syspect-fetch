mkdir -p "$HOME/.local/bin" "$HOME/.config/syspect-fetch"

cat > "$HOME/.local/bin/syspect-fetch" <<'SYSP'
#!/usr/bin/env bash

# ============================================================
# SYSPECT FETCH
# Version 3.0.0 "NOVA"
# ============================================================

VERSION="3.0.0"
APP="Syspect Fetch"

# ---------- ANSI ----------
ESC=$'\033'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
CURSOR_HOME="${ESC}[H"
CLEAR_LINE="${ESC}[2K"
HIDE_CURSOR="${ESC}[?25l"
SHOW_CURSOR="${ESC}[?25h"

# ---------- Defaults ----------
THEME="${SYSP_THEME:-nova}"
INTERVAL="${SYSP_INTERVAL:-1}"
LIVE=0
LOGO_ONLY=0
ASCII=0
ANIMATION=1
TIP=1
DEBUG=0

# ---------- Theme ----------
set_theme() {
    case "$1" in
        nova|cyan)
            C1="${ESC}[96m"
            C2="${ESC}[36m"
            C3="${ESC}[94m"
            ;;
        matrix|green)
            C1="${ESC}[92m"
            C2="${ESC}[32m"
            C3="${ESC}[90m"
            ;;
        cyber|purple)
            C1="${ESC}[95m"
            C2="${ESC}[35m"
            C3="${ESC}[94m"
            ;;
        fire|red)
            C1="${ESC}[91m"
            C2="${ESC}[31m"
            C3="${ESC}[93m"
            ;;
        ocean|blue)
            C1="${ESC}[94m"
            C2="${ESC}[34m"
            C3="${ESC}[96m"
            ;;
        gold|yellow)
            C1="${ESC}[93m"
            C2="${ESC}[33m"
            C3="${ESC}[97m"
            ;;
        mono|white)
            C1="${ESC}[97m"
            C2="${ESC}[37m"
            C3="${ESC}[90m"
            ;;
        *)
            THEME="nova"
            C1="${ESC}[96m"
            C2="${ESC}[36m"
            C3="${ESC}[94m"
            ;;
    esac
}

set_theme "$THEME"

# ---------- Utilities ----------
have() {
    command -v "$1" >/dev/null 2>&1
}

safe_cat() {
    [ -r "$1" ] && cat "$1" 2>/dev/null || true
}

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

num() {
    printf '%s' "${1:-}" | grep -Eq '^[0-9]+([.][0-9]+)?$'
}

clamp() {
    awk -v n="${1:-0}" '
    BEGIN {
        if (n < 0) n=0
        if (n > 100) n=100
        printf "%.0f",n
    }'
}

term_width() {
    if [ -t 1 ]; then
        printf '%s\n' "${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
    else
        echo 80
    fi
}

# ---------- Bars ----------
bar() {
    local p="${1:-0}"
    local width="${2:-20}"

    p="$(clamp "$p")"

    local filled
    filled="$(awk -v p="$p" -v w="$width" \
        'BEGIN{x=int(p*w/100+0.5);if(x<0)x=0;if(x>w)x=w;print x}')"

    local empty=$((width-filled))

    printf "%b" "$C1"
    printf '%*s' "$filled" '' | tr ' ' '█'
    printf "%b" "$C2"
    printf '%*s' "$empty" '' | tr ' ' '·'
    printf "%b" "$RESET"
}

ascii_bar() {
    local p="${1:-0}"
    local width=20

    p="$(clamp "$p")"

    local filled
    filled="$(awk -v p="$p" -v w="$width" \
        'BEGIN{x=int(p*w/100+0.5);if(x<0)x=0;if(x>w)x=w;print x}')"

    local empty=$((width-filled))

    printf "%b[" "$C2"
    printf '%*s' "$filled" '' | tr ' ' '#'
    printf '%*s' "$empty" '' | tr ' ' '-'
    printf "]%b" "$RESET"
}

metric() {
    local label="$1"
    local percent="$2"
    local extra="$3"

    printf "  %b%-14s%b " "$C1" "$label" "$RESET"

    if [ "$ASCII" -eq 1 ]; then
        ascii_bar "$percent"
    else
        bar "$percent"
    fi

    printf " %b%3s%%%b" "$WHITE" "$percent" "$RESET"

    [ -n "$extra" ] &&
        printf "  %b%s%b" "$DIM" "$extra" "$RESET"

    printf "\n"
}

info() {
    printf "  %b%-16s%b %s\n" "$C1" "$1" "$RESET" "${2:-N/A}"
}

section() {
    printf "\n%b  // %s%b\n" "$C1" "$1" "$RESET"
    printf "%b  ──────────────────────────────────────────────%b\n" \
        "$C3" "$RESET"
}

# ---------- OS ----------
OS_ID="linux"
OS_NAME="Linux"
OS_VERSION=""

if [ -r /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-linux}"
    OS_NAME="${PRETTY_NAME:-${NAME:-Linux}}"
    OS_VERSION="${VERSION_ID:-}"
fi

if [ -n "${WSL_DISTRO_NAME:-}" ]; then
    OS_NAME="$WSL_DISTRO_NAME / WSL"
fi

# ---------- Identity ----------
KERNEL="$(uname -r 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"
HOSTNAME_VALUE="$(hostname 2>/dev/null || echo unknown)"
SHELL_NAME="$(basename "${SHELL:-unknown}")"
TERM_NAME="${TERM:-unknown}"
SESSION="${XDG_SESSION_TYPE:-unknown}"

# ---------- CPU ----------
CPU_MODEL="$(
    awk -F': ' '
    /^model name/ {print $2; exit}
    /^Hardware/ {print $2; exit}
    /^Processor/ {print $2; exit}
    ' /proc/cpuinfo 2>/dev/null
)"
[ -n "$CPU_MODEL" ] || CPU_MODEL="Unknown"

CPU_THREADS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo '?')"

CPU_CORES="$(
    awk '
    /^physical id/ {p[$4]=1}
    END {
        n=0
        for(x in p)n++
        if(n>0) print n
        else print "?"
    }' /proc/cpuinfo 2>/dev/null
)"

[ "$CPU_CORES" = "?" ] && CPU_CORES="$CPU_THREADS"

CPU_FREQ="$(
    awk '/cpu MHz/ {
        printf "%.0f",$4
        exit
    }' /proc/cpuinfo 2>/dev/null
)"
[ -n "$CPU_FREQ" ] || CPU_FREQ="N/A"

# ---------- CPU sampler ----------
OLD_IDLE=0
OLD_TOTAL=0
CPU_READY=0

cpu_sample() {
    awk '
    $1=="cpu" {
        idle=$5+$6
        total=$2+$3+$4+$5+$6+$7+$8+$9+$10
        print idle,total
        exit
    }' /proc/stat 2>/dev/null
}

cpu_usage() {
    local idle total di dt

    read -r idle total <<< "$(cpu_sample)"

    if ! num "$idle" || ! num "$total"; then
        echo 0
        return
    fi

    if [ "$CPU_READY" -eq 0 ]; then
        OLD_IDLE="$idle"
        OLD_TOTAL="$total"
        CPU_READY=1
        echo 0
        return
    fi

    di=$((idle-OLD_IDLE))
    dt=$((total-OLD_TOTAL))

    OLD_IDLE="$idle"
    OLD_TOTAL="$total"

    if [ "$dt" -le 0 ]; then
        echo 0
        return
    fi

    awk -v i="$di" -v t="$dt" '
    BEGIN {
        x=((t-i)/t)*100
        if(x<0)x=0
        if(x>100)x=100
        printf "%.0f",x
    }'
}

# ---------- Memory ----------
memory_info() {
    awk '
    /^MemTotal:/ {total=$2}
    /^MemAvailable:/ {avail=$2}
    /^SwapTotal:/ {swap_total=$2}
    /^SwapFree:/ {swap_free=$2}

    END {
        used=total-avail
        swap_used=swap_total-swap_free

        ram_pct=(total>0 ? used/total*100 : 0)
        swap_pct=(swap_total>0 ? swap_used/swap_total*100 : 0)

        printf "%.0f %s %s %.0f %s %s\n",
            ram_pct,
            used*1024,
            total*1024,
            swap_pct,
            swap_used*1024,
            swap_total*1024
    }' /proc/meminfo 2>/dev/null
}

# ---------- Disk ----------
disk_info() {
    df -P -B1 / 2>/dev/null |
        awk 'NR==2 {
            gsub("%","",$5)
            print $5,$3,$2
        }'
}

filesystem() {
    df -T / 2>/dev/null |
        awk 'NR==2 {print $2}'
}

# ---------- Load ----------
load_average() {
    awk '{print $1 " / " $2 " / " $3}' /proc/loadavg 2>/dev/null
}

uptime_text() {
    awk '
    {
        s=int($1)
        d=int(s/86400)
        h=int((s%86400)/3600)
        m=int((s%3600)/60)

        if(d>0) printf "%dd %dh %dm",d,h,m
        else if(h>0) printf "%dh %dm",h,m
        else printf "%dm",m
    }' /proc/uptime 2>/dev/null
}

boot_time() {
    local t
    t="$(awk '/^btime /{print $2}' /proc/stat 2>/dev/null)"

    if [ -n "$t" ] && have date; then
        date -d "@$t" '+%Y-%m-%d %H:%M:%S' 2>/dev/null ||
            echo N/A
    else
        echo N/A
    fi
}

# ---------- Hardware ----------
VENDOR="$(safe_cat /sys/class/dmi/id/sys_vendor)"
MODEL="$(safe_cat /sys/class/dmi/id/product_name)"
BIOS="$(safe_cat /sys/class/dmi/id/bios_version)"

[ -n "$VENDOR" ] || VENDOR="N/A"
[ -n "$MODEL" ] || MODEL="N/A"
[ -n "$BIOS" ] || BIOS="N/A"

libc_name() {
    if [ -e /lib/ld-musl-x86_64.so.1 ] ||
       [ -e /lib/ld-musl-aarch64.so.1 ]; then
        echo musl
        return
    fi

    if [ -e /lib64/ld-linux-x86-64.so.2 ] ||
       [ -e /lib/ld-linux-aarch64.so.1 ]; then
        echo glibc
        return
    fi

    echo unknown
}

init_name() {
    if [ -d /run/runit ] || [ -d /etc/runit ]; then
        echo runit
    elif [ -d /run/systemd/system ]; then
        echo systemd
    elif [ -d /run/openrc ]; then
        echo OpenRC
    elif [ -r /proc/1/comm ]; then
        safe_cat /proc/1/comm
    else
        echo unknown
    fi
}

virtualization() {
    if have systemd-detect-virt; then
        local v
        v="$(systemd-detect-virt 2>/dev/null)"
        if [ -n "$v" ] && [ "$v" != "none" ]; then
            echo "$v"
            return
        fi
    fi

    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo WSL
        return
    fi

    if grep -qi hypervisor /proc/cpuinfo 2>/dev/null; then
        echo virtualized
        return
    fi

    echo "bare metal"
}

secure_boot() {
    local f

    f="$(
        find /sys/firmware/efi/efivars \
            -maxdepth 1 \
            -name 'SecureBoot-*' \
            2>/dev/null |
            head -n1
    )"

    [ -n "$f" ] || {
        echo N/A
        return
    }

    if od -An -t u1 "$f" 2>/dev/null | grep -Eq ' 1$'; then
        echo enabled
    else
        echo disabled
    fi
}

# ---------- GPU ----------
gpu_info() {
    if have lspci; then
        lspci 2>/dev/null |
            grep -Ei \
            'VGA compatible controller|3D controller|Display controller' |
            sed -E 's/^[^:]+: //' |
            head -n1
    else
        echo N/A
    fi
}

gpu_driver() {
    if ! have lspci; then
        echo N/A
        return
    fi

    local id
    id="$(
        lspci 2>/dev/null |
            grep -Ei \
            'VGA compatible controller|3D controller|Display controller' |
            head -n1 |
            awk '{print $1}'
    )"

    [ -n "$id" ] || {
        echo N/A
        return
    }

    lspci -k -s "$id" 2>/dev/null |
        awk -F': ' '/Kernel driver in use/ {print $2; exit}'

    return 0
}

display_info() {
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        echo "Wayland"
        return
    fi

    if [ -n "${DISPLAY:-}" ] && have xrandr; then
        xrandr --current 2>/dev/null |
            awk '/ connected/ {print $3; exit}'
        return
    fi

    echo N/A
}

desktop_name() {
    echo "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-TTY}}}"
}

wm_name() {
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        echo Hyprland
    elif [ -n "${SWAYSOCK:-}" ]; then
        echo Sway
    elif [ -n "${I3SOCK:-}" ]; then
        echo i3
    elif [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
        echo "$XDG_CURRENT_DESKTOP"
    else
        echo N/A
    fi
}

# ---------- Battery ----------
battery_path() {
    find /sys/class/power_supply \
        -maxdepth 1 \
        -type l \
        -name 'BAT*' \
        2>/dev/null |
        head -n1
}

battery_info() {
    local b
    b="$(battery_path)"

    [ -n "$b" ] || {
        echo "none"
        return
    }

    local cap status health
    cap="$(safe_cat "$b/capacity")"
    status="$(safe_cat "$b/status")"
    health="$(safe_cat "$b/health")"

    [ -n "$cap" ] || cap="?"
    [ -n "$status" ] || status="Unknown"
    [ -n "$health" ] || health="Unknown"

    echo "$cap|$status|$health"
}

# ---------- Temperature ----------
temperature() {
    local total=0
    local count=0
    local f t

    for f in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$f" ] || continue

        t="$(cat "$f" 2>/dev/null)"

        if printf '%s' "$t" | grep -Eq '^[0-9]+$'; then
            if [ "$t" -gt 0 ]; then
                total=$((total+t))
                count=$((count+1))
            fi
        fi
    done

    if [ "$count" -gt 0 ]; then
        awk -v t="$total" -v c="$count" \
            'BEGIN{printf "%.0f°C",t/c/1000}'
    else
        echo N/A
    fi
}

# ---------- Network ----------
network_interface() {
    if have ip; then
        ip route 2>/dev/null |
            awk '$1=="default" {print $5;exit}'
        return
    fi

    awk -F: '$1!="lo" && $1!~/^ *$/ {gsub(/ /,"",$1);print $1;exit}' \
        /proc/net/dev 2>/dev/null
}

network_ip() {
    local iface="$1"

    [ -n "$iface" ] || {
        echo N/A
        return
    }

    if have ip; then
        ip -4 addr show "$iface" 2>/dev/null |
            awk '$1=="inet" {print $2;exit}'
    else
        echo N/A
    fi
}

RX_OLD=0
TX_OLD=0
NET_OLD_TIME=0
NET_READY=0

network_speed() {
    local iface="$1"

    [ -n "$iface" ] || {
        echo "0 0"
        return
    }

    local rx_file="/sys/class/net/$iface/statistics/rx_bytes"
    local tx_file="/sys/class/net/$iface/statistics/tx_bytes"

    [ -r "$rx_file" ] && [ -r "$tx_file" ] || {
        echo "0 0"
        return
    }

    local rx tx now dt down up

    rx="$(cat "$rx_file" 2>/dev/null)"
    tx="$(cat "$tx_file" 2>/dev/null)"
    now="$(date +%s)"

    if [ "$NET_READY" -eq 0 ]; then
        RX_OLD="$rx"
        TX_OLD="$tx"
        NET_OLD_TIME="$now"
        NET_READY=1
        echo "0 0"
        return
    fi

    dt=$((now-NET_OLD_TIME))
    [ "$dt" -lt 1 ] && dt=1

    down=$(( (rx-RX_OLD)/dt ))
    up=$(( (tx-TX_OLD)/dt ))

    [ "$down" -lt 0 ] && down=0
    [ "$up" -lt 0 ] && up=0

    RX_OLD="$rx"
    TX_OLD="$tx"
    NET_OLD_TIME="$now"

    echo "$down $up"
}

dns_servers() {
    awk '/^nameserver/ {print $2}' /etc/resolv.conf 2>/dev/null |
        paste -sd',' -
}

# ---------- Software ----------
package_info() {
    if have xbps-query; then
        echo "$(xbps-query -l 2>/dev/null | wc -l | tr -d ' ') XBPS"
    elif have pacman; then
        echo "$(pacman -Q 2>/dev/null | wc -l | tr -d ' ') pacman"
    elif have dpkg-query; then
        echo "$(dpkg-query -W 2>/dev/null | wc -l | tr -d ' ') dpkg"
    elif have rpm; then
        echo "$(rpm -qa 2>/dev/null | wc -l | tr -d ' ') rpm"
    else
        echo "N/A"
    fi
}

compiler_info() {
    if have gcc; then
        gcc --version 2>/dev/null | head -n1
    elif have clang; then
        clang --version 2>/dev/null | head -n1
    else
        echo N/A
    fi
}

git_info() {
    if have git; then
        git --version 2>/dev/null
    else
        echo N/A
    fi
}

shell_version() {
    case "$SHELL_NAME" in
        bash)
            bash --version 2>/dev/null |
                head -n1 |
                sed 's/.*version //'
            ;;
        zsh)
            zsh --version 2>/dev/null |
                sed 's/.*version //'
            ;;
        fish)
            fish --version 2>/dev/null |
                sed 's/fish, version //'
            ;;
        *)
            echo N/A
            ;;
    esac
}

# ---------- Runtime ----------
process_count() {
    find /proc -maxdepth 1 -type d \
        -regextype posix-extended \
        -regex '.*/[0-9]+' \
        2>/dev/null |
        wc -l |
        tr -d ' '
}

logged_users() {
    if have who; then
        who 2>/dev/null |
            awk '{print $1}' |
            sort -u |
            paste -sd',' -
    else
        echo N/A
    fi
}

service_count() {
    if [ -d /var/service ]; then
        find /var/service \
            -mindepth 1 \
            -maxdepth 1 \
            2>/dev/null |
            wc -l |
            tr -d ' '
    elif have systemctl; then
        systemctl list-units \
            --type=service \
            --state=running \
            --no-legend \
            2>/dev/null |
            wc -l |
            tr -d ' '
    else
        echo N/A
    fi
}

timezone_name() {
    if [ -L /etc/localtime ]; then
        readlink /etc/localtime 2>/dev/null |
            sed 's#.*/zoneinfo/##'
    elif [ -r /etc/timezone ]; then
        cat /etc/timezone 2>/dev/null
    else
        echo N/A
    fi
}

# ============================================================
# LOGOS
# ============================================================

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

logo_arch() {
cat <<'EOF'
              /\
             /  \
            / /\ \
           / /  \ \
          / / /\ \ \
         /_/ /  \ \_\
            /____\
             ARCH
             LINUX
EOF
}

logo_debian() {
cat <<'EOF'
             .-''''-.
          .-'  .--.  '-.
        .'   .'    '.   '.
       /    /  DEB   \    \
      ;     \  IAN   /     ;
       \     '.___.'     /
        '.             .'
          '-.________.-'
             DEBIAN
EOF
}

logo_ubuntu() {
cat <<'EOF'
              .-.
          .-'     '-.
        .'   o   o   '.
       /      \ /      \
      ;    o   ●   o    ;
       \      / \      /
        '.  o     o  .'
          '-._____.-'
             UBUNTU
EOF
}

logo_fedora() {
cat <<'EOF'
             _______
          .-'       '-.
        .'     .-.     '.
       /      /   \      \
      |      | FED |      |
      |      | ORA |      |
       \      \___/      /
        '.             .'
          '-.________.-'
             FEDORA
EOF
}

logo_opensuse() {
cat <<'EOF'
             _______
          .-'       '-.
        .'   .-----.   '.
       /   .'  ___  '.   \
      |   /   / _ \   \   |
      |   |   \___/   |   |
       \   '.       .'   /
        '.   '-----'   .'
          '-.______.-'
            openSUSE
EOF
}

logo_gentoo() {
cat <<'EOF'
              /\
             /  \
            / /\ \
           / /  \ \
          / / /\ \ \
         /_/ /  \ \_\
            GENTOO
EOF
}

logo_alpine() {
cat <<'EOF'
              /\
             /  \
            / /\ \
           / /  \ \
          / / /\ \ \
         /_/ /  \ \_\
             ALPINE
EOF
}

logo_nixos() {
cat <<'EOF'
           _.._.._.._
        .-'           '-.
       /      N I X      \
      |        /\         |
      |       /__\        |
       \                 /
        '._           _.'
           '-._____.-'
              NIXOS
EOF
}

logo_mint() {
cat <<'EOF'
          _____________
        .'             '.
       /    M I N T      \
      |       ____        |
      |      /    \       |
       \     \____/      /
        '.             .'
          '-----------'
            LINUX MINT
EOF
}

logo_manjaro() {
cat <<'EOF'
          ╱╲      ╱╲
         ╱  ╲    ╱  ╲
        ╱    ╲  ╱    ╲
       ╱  M A N J A R O ╲
      ╱__________________╲
EOF
}

logo_endeavour() {
cat <<'EOF'
               /\
              /  \
             / /\ \
            / /  \ \
           /_/    \_\
            ENDEAVOUR
                OS
EOF
}

logo_generic() {
cat <<'EOF'
             .--.
            |o_o |
            |:_/ |
           //   \ \
          (|     | )
         /'\_   _/`\
         \___)=(___/
EOF
}

show_logo() {
    printf "%b" "$C1"

    case "$OS_ID" in
        void) logo_void ;;
        arch) logo_arch ;;
        debian) logo_debian ;;
        ubuntu) logo_ubuntu ;;
        fedora) logo_fedora ;;
        opensuse*|suse) logo_opensuse ;;
        gentoo) logo_gentoo ;;
        alpine) logo_alpine ;;
        nixos) logo_nixos ;;
        linuxmint|mint) logo_mint ;;
        manjaro) logo_manjaro ;;
        endeavouros) logo_endeavour ;;
        *) logo_generic ;;
    esac

    printf "%b" "$RESET"
}

# ---------- Tips ----------
tip() {
    local tips=(
        "Use --live for the realtime dashboard."
        "Use --interval 0.25 for faster monitoring."
        "Try --theme matrix for a green cyber terminal."
        "Try --theme fire for a red/orange terminal."
        "Use --ascii if your terminal cannot display Unicode."
        "Use --logo to display only the detected distro artwork."
        "Run --self-test if something looks wrong."
        "Set SYSP_THEME=cyber to make cyber your default theme."
        "Syspect reads Linux kernel interfaces directly where possible."
        "Live mode redraws in place instead of repeatedly clearing the terminal."
    )

    echo "${tips[$((RANDOM % ${#tips[@]}))]}"
}

# ============================================================
# RENDERING
# ============================================================

render_full() {
    local cpu ram disk
    cpu="$(cpu_usage)"
    ram="$(memory_info)"
    disk="$(disk_info)"

    local rp ru rt sp su st
    read -r rp ru rt sp su st <<< "$ram"

    local dp du dt
    read -r dp du dt <<< "$disk"

    local iface ip
    iface="$(network_interface)"
    ip="$(network_ip "$iface")"

    local speeds down up
    speeds="$(network_speed "$iface")"
    read -r down up <<< "$speeds"

    local battery
    battery="$(battery_info)"

    printf "\n"

    show_logo

    printf "\n"
    printf "%b╔══════════════════════════════════════════════════════════════╗%b\n" \
        "$C1" "$RESET"
    printf "%b║  SYSPECT FETCH  v%-6s  NOVA SYSTEM INTELLIGENCE             ║%b\n" \
        "$C1" "$VERSION" "$RESET"
    printf "%b╚══════════════════════════════════════════════════════════════╝%b\n" \
        "$C1" "$RESET"

    section "SYSTEM"
    info "OS" "$OS_NAME"
    info "Kernel" "$KERNEL"
    info "Architecture" "$ARCH"
    info "Hostname" "$HOSTNAME_VALUE"
    info "Machine" "$VENDOR $MODEL"
    info "BIOS" "$BIOS"
    info "Init" "$(init_name)"
    info "libc" "$(libc_name)"
    info "Virtualization" "$(virtualization)"
    info "Secure Boot" "$(secure_boot)"

    section "PROCESSOR"
    info "CPU" "$CPU_MODEL"
    info "Cores" "$CPU_CORES"
    info "Threads" "$CPU_THREADS"
    info "Frequency" "$CPU_FREQ MHz"
    info "Load" "$(load_average)"
    metric "CPU" "$cpu" ""

    section "MEMORY"
    metric "RAM" "$rp" "$(bytes "$ru") / $(bytes "$rt")"
    metric "SWAP" "$sp" "$(bytes "$su") / $(bytes "$st")"

    section "STORAGE"
    metric "Root disk" "$dp" "$(bytes "$du") / $(bytes "$dt")"
    info "Filesystem" "$(filesystem)"

    section "GRAPHICS"
    info "GPU" "$(gpu_info)"
    info "Driver" "$(gpu_driver)"
    info "Display" "$(display_info)"

    section "DESKTOP"
    info "Desktop" "$(desktop_name)"
    info "Window manager" "$(wm_name)"
    info "Session" "$SESSION"
    info "Terminal" "$TERM_NAME"
    info "Shell" "$SHELL_NAME"
    info "Shell version" "$(shell_version)"

    section "NETWORK"
    info "Interface" "${iface:-offline}"
    info "IPv4" "$ip"
    info "DNS" "$(dns_servers)"

    [ "${down:-0}" -gt 0 ] 2>/dev/null &&
        info "Download" "$(bytes "$down")/s"

    [ "${up:-0}" -gt 0 ] 2>/dev/null &&
        info "Upload" "$(bytes "$up")/s"

    section "POWER & THERMALS"

    if [ "$battery" = "none" ]; then
        info "Battery" "No battery detected"
    else
        local bc bs bh
        IFS='|' read -r bc bs bh <<< "$battery"
        info "Battery" "$bc% ($bs)"
        info "Health" "$bh"
    fi

    info "Temperature" "$(temperature)"

    section "RUNTIME"
    info "Uptime" "$(uptime_text)"
    info "Boot" "$(boot_time)"
    info "Processes" "$(process_count)"
    info "Users" "$(logged_users)"
    info "Services" "$(service_count)"

    section "SOFTWARE"
    info "Packages" "$(package_info)"
    info "Compiler" "$(compiler_info)"
    info "Git" "$(git_info)"

    section "ENVIRONMENT"
    info "Timezone" "$(timezone_name)"
    info "Locale" "${LANG:-${LC_ALL:-C}}"
    info "Directory" "$PWD"

    section "SYSPECT"
    info "Version" "$VERSION"
    info "Theme" "$THEME"
    info "Animation" "$([ "$ANIMATION" -eq 1 ] && echo enabled || echo disabled)"
    info "Live mode" disabled
    info "Interval" "${INTERVAL}s"

    printf "\n  %b● SYSTEM STATUS%b  " "$C1" "$RESET"

    if [ "$cpu" -ge 90 ] 2>/dev/null; then
        printf "%bHIGH CPU LOAD%b\n" "$C1" "$RESET"
    else
        printf "%bHEALTHY%b\n" "$C1" "$RESET"
    fi

    if [ "$TIP" -eq 1 ]; then
        printf "\n  %bTIP%b  %s\n" "$C1" "$RESET" "$(tip)"
    fi

    printf "\n"
}

render_live() {
    local cpu ram disk iface ip speeds down up battery
    cpu="$(cpu_usage)"
    ram="$(memory_info)"
    disk="$(disk_info)"

    local rp ru rt sp su st
    read -r rp ru rt sp su st <<< "$ram"

    local dp du dt
    read -r dp du dt <<< "$disk"

    iface="$(network_interface)"
    ip="$(network_ip "$iface")"

    speeds="$(network_speed "$iface")"
    read -r down up <<< "$speeds"

    battery="$(battery_info)"

    # IMPORTANT:
    # Move cursor to the top and erase each printed line.
    # We do NOT use clear, so the terminal doesn't flash.
    printf "%s" "$CURSOR_HOME"

    printf "%s\n" "$CLEAR_LINE"
    printf "%b%bSYSPECT FETCH%b  %b● LIVE%b  %s\n" \
        "$CLEAR_LINE" "$C1" "$BOLD" "$RESET" "$C1" "$RESET" \
        "$(date '+%H:%M:%S')"

    printf "%b\n" "$CLEAR_LINE"
    printf "%b  %s%b\n" "$CLEAR_LINE" "$OS_NAME" "$RESET"
    printf "%b  Kernel: %s   Uptime: %s%b\n" \
        "$CLEAR_LINE" "$KERNEL" "$(uptime_text)" "$RESET"

    printf "%b\n" "$CLEAR_LINE"
    metric "CPU" "$cpu" ""
    metric "RAM" "$rp" "$(bytes "$ru") / $(bytes "$rt")"
    metric "SWAP" "$sp" "$(bytes "$su")"
    metric "DISK" "$dp" "$(bytes "$du") / $(bytes "$dt")"

    printf "%b\n" "$CLEAR_LINE"
    info "Load" "$(load_average)"
    info "Temperature" "$(temperature)"
    info "Processes" "$(process_count)"
    info "Network" "${iface:-offline} $ip"

    if [ "${down:-0}" -gt 0 ] 2>/dev/null; then
        info "Download" "$(bytes "$down")/s"
    else
        info "Download" "0 B/s"
    fi

    if [ "${up:-0}" -gt 0 ] 2>/dev/null; then
        info "Upload" "$(bytes "$up")/s"
    else
        info "Upload" "0 B/s"
    fi

    if [ "$battery" != "none" ]; then
        local bc bs bh
        IFS='|' read -r bc bs bh <<< "$battery"
        info "Battery" "$bc% ($bs)"
    fi

    printf "%b\n" "$CLEAR_LINE"
    printf "  %bTheme:%b %s    %bRefresh:%b %ss\n" \
        "$C1" "$RESET" "$THEME" \
        "$C1" "$RESET" "$INTERVAL"

    if [ "$TIP" -eq 1 ]; then
        printf "  %bTIP:%b %s\n" "$C1" "$RESET" "$(tip)"
    fi

    printf "%b\n" "$CLEAR_LINE"
    printf "  %bCtrl+C%b to exit\n" "$DIM" "$RESET"

    # Clear anything left from a previous longer frame.
    printf "%b" "$CLEAR_LINE"
}

# ============================================================
# HELP / TEST
# ============================================================

show_help() {
cat <<EOF

$APP $VERSION

USAGE

  syspect-fetch
      Show full system information.

  syspect-fetch --live
      Start realtime monitoring.

OPTIONS

  --live, -l              Realtime dashboard
  --interval, -i VALUE    Refresh interval
  --theme, -t NAME        Select theme
  --logo                  Show distro logo only
  --ascii                 ASCII-only bars
  --no-animation          Disable startup animation
  --no-tip                Disable tips
  --themes                List themes
  --self-test             Test Syspect
  --debug                 Debug mode
  --version, -v           Version
  --help, -h              Help

THEMES

  nova
  matrix
  cyber
  fire
  ocean
  gold
  mono

EXAMPLES

  syspect-fetch
  syspect-fetch --live
  syspect-fetch --live --interval 0.5
  syspect-fetch --live --interval 0.25 --theme matrix
  syspect-fetch --theme fire
  syspect-fetch --logo
  syspect-fetch --ascii
  syspect-fetch --self-test

ENVIRONMENT

  SYSP_THEME=matrix
  SYSP_INTERVAL=0.5

EOF
}

self_test() {
    local failed=0

    echo
    printf "%bSYSPECT FETCH SELF-TEST%b\n\n" "$C1" "$RESET"

    printf "  Bash                 "
    if [ -n "${BASH_VERSION:-}" ]; then
        printf "%bOK%b\n" "$C1" "$RESET"
    else
        printf "FAIL\n"
        failed=1
    fi

    printf "  /proc                "
    if [ -r /proc/stat ] && [ -r /proc/meminfo ]; then
        printf "%bOK%b\n" "$C1" "$RESET"
    else
        printf "FAIL\n"
        failed=1
    fi

    printf "  OS detection         "
    if [ -r /etc/os-release ]; then
        printf "%bOK%b (%s)\n" "$C1" "$RESET" "$OS_ID"
    else
        printf "FALLBACK\n"
    fi

    printf "  CPU detection        "
    if [ -n "$CPU_MODEL" ] && [ "$CPU_MODEL" != "Unknown" ]; then
        printf "%bOK%b\n" "$C1" "$RESET"
    else
        printf "N/A\n"
    fi

    printf "  Memory detection     "
    if [ -r /proc/meminfo ]; then
        printf "%bOK%b\n" "$C1" "$RESET"
    else
        printf "FAIL\n"
        failed=1
    fi

    printf "  Terminal output      "
    if [ -t 1 ]; then
        printf "%bOK%b\n" "$C1" "$RESET"
    else
        printf "PIPE\n"
    fi

    printf "\n"

    if [ "$failed" -eq 0 ]; then
        printf "%b✓ All required tests passed.%b\n\n" "$C1" "$RESET"
        return 0
    fi

    printf "%b✗ One or more required tests failed.%b\n\n" "$C1" "$RESET"
    return 1
}

# ============================================================
# ARGUMENTS
# ============================================================

while [ "$#" -gt 0 ]; do
    case "$1" in
        --live|-l)
            LIVE=1
            ;;
        --interval|-i)
            shift
            INTERVAL="${1:-1}"
            ;;
        --theme|-t)
            shift
            THEME="${1:-nova}"
            set_theme "$THEME"
            ;;
        --logo)
            LOGO_ONLY=1
            ;;
        --ascii)
            ASCII=1
            ;;
        --no-animation|--no-anim)
            ANIMATION=0
            ;;
        --no-tip)
            TIP=0
            ;;
        --themes)
            echo "nova matrix cyber fire ocean gold mono"
            exit 0
            ;;
        --self-test)
            self_test
            exit $?
            ;;
        --debug)
            DEBUG=1
            ;;
        --version|-v)
            echo "$APP $VERSION"
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run: syspect-fetch --help"
            exit 1
            ;;
    esac
    shift
done

# ---------- Validate interval ----------
if ! printf '%s' "$INTERVAL" |
    grep -Eq '^[0-9]+([.][0-9]+)?$'; then
    INTERVAL=1
fi

if awk -v x="$INTERVAL" 'BEGIN{exit !(x>0)}'; then
    :
else
    INTERVAL=1
fi

# ---------- Terminal ----------
cleanup() {
    printf "%b" "$SHOW_CURSOR"
    printf "\n"
}

trap cleanup INT TERM EXIT

# ---------- Logo only ----------
if [ "$LOGO_ONLY" -eq 1 ]; then
    show_logo
    exit 0
fi

# ---------- Startup ----------
if [ "$LIVE" -eq 0 ] && [ "$ANIMATION" -eq 1 ]; then
    printf "%bSYSPECT FETCH%b " "$C1" "$RESET"
    printf "%binitializing%b" "$DIM" "$RESET"

    for x in 1 2 3; do
        printf "."
        sleep 0.08
    done

    printf "\n\n"
fi

# ---------- Live ----------
if [ "$LIVE" -eq 1 ]; then
    # Prime counters.
    cpu_usage >/dev/null
    network_speed "$(network_interface)" >/dev/null

    # Take a short initial sample so CPU/network become meaningful,
    # while still rendering immediately.
    render_live

    while :; do
        sleep "$INTERVAL"
        render_live
    done
fi

# ---------- Normal ----------
render_full

SYSP

chmod +x "$HOME/.local/bin/syspect-fetch"

# Syntax check BEFORE doing anything else.
bash -n "$HOME/.local/bin/syspect-fetch" || {
    echo "ERROR: Syspect Fetch failed its Bash syntax check."
    exit 1
}

echo
echo "✓ Syspect Fetch 3.0.0 installed."
echo "✓ Bash syntax check passed."
echo
echo "Run:"
echo "  $HOME/.local/bin/syspect-fetch"
echo
echo "Realtime:"
echo "  $HOME/.local/bin/syspect-fetch --live"
echo
echo "Fast realtime:"
echo "  $HOME/.local/bin/syspect-fetch --live --interval 0.25"
echo
echo "Matrix:"
echo "  $HOME/.local/bin/syspect-fetch --live --theme matrix"
echo
echo "If anything is wrong:"
echo "  $HOME/.local/bin/syspect-fetch --self-test"
