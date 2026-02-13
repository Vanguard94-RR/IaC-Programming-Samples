#!/usr/bin/env bash
# UI helpers for update_ingress v2

set -o errexit
set -o nounset
set -o pipefail

# TTY-aware colors
if [ -t 1 ] && [ -z "${NO_COLOR-}" ]; then
    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    RED="\033[0;31m"
    CYAN="\033[0;36m"
    WHITE="\033[1;37m"
    BOLD="\033[1m"
    NC="\033[0m"
else
    GREEN=""
    YELLOW=""
    RED=""
    CYAN=""
    WHITE=""
    BOLD=""
    NC=""
fi

bold() { printf "%s%s%s" "${BOLD}" "*$*" "${NC}"; }

# Verbose logging control
: ${VERBOSE:=false}
: ${DRY_RUN:=false}

vprint() {
    if [ "${VERBOSE}" = "true" ]; then
        printf "${CYAN}» %s${NC}\n" "$1"
    fi
}

print_banner_box() {
    local title="$1"
    local width=44
    local line_top="╔"
    local line_mid="║"
    local line_bot="╚"
    local bar=""
    for ((i=1; i<=width; i++)); do bar+="═"; done

    printf '%b\n' "${CYAN}${line_top}${bar}╗${NC}"

    local pad_left pad_right
    pad_left=$(( (width - ${#title}) / 2 ))
    pad_right=$(( width - pad_left - ${#title} ))

    printf '%b' "${CYAN}${line_mid}${NC}"
    printf '%*s' "$pad_left" ""
    printf '%b' "${WHITE}${BOLD}${title}${NC}"
    printf '%*s' "$pad_right" ""
    printf '%b\n' "${CYAN}${line_mid}${NC}"

    printf '%b\n' "${CYAN}${line_bot}${bar}╝${NC}"
}

step() { printf "\n${YELLOW}➜ ${WHITE}${BOLD}%s${NC}\n" "$1"; }
info() { printf "${CYAN}• ${WHITE}%s${NC}\n" "$1"; }
success() { printf "${GREEN}✔ ${WHITE}%s${NC}\n" "$1"; }
warn() { printf "${YELLOW}⚠ ${WHITE}${BOLD}%s${NC}\n" "$1"; }
error() { printf "${RED}✖ ${WHITE}${BOLD}%s${NC}\n" "$1"; }

spinner_start() {
    local msg=$1
    if [ -t 1 ]; then
        printf "${CYAN}%s... ${NC}" "$msg"
        (
            i=0
            while :; do
                printf "."
                i=$(( (i + 1) % 4 ))
                sleep 0.6
                if [ $i -eq 0 ]; then printf "\b\b\b   \b\b\b"; fi
            done
        ) &
        SPIN_PID=$!
    else
        printf "${CYAN}%s...${NC}\n" "$msg"
        SPIN_PID=""
    fi
}

spinner_stop() {
    if [ -n "${SPIN_PID:-}" ]; then
        kill "$SPIN_PID" 2>/dev/null || true
        wait "$SPIN_PID" 2>/dev/null || true
        unset SPIN_PID
        printf "\r"
    fi
}

# Progress bar utilities (TTY-safe)
progress_bar_start() {
    # track start time for potential future use
    PROG_START_TIME=$(date +%s) || true
    PROG_TOTAL=$1 || true
    if [ -t 1 ]; then
        printf "${CYAN}%s${NC}\n" "Progress: (max ${PROG_TOTAL}s)"
    fi
}

progress_bar_update() {
    local elapsed=$1
    local total=$2
    if [ -t 1 ]; then
        local pct=0
        if [ "$total" -gt 0 ]; then
            pct=$(( (elapsed * 100) / total ))
        fi
        local filled=$(( (pct * 30) / 100 ))
        local empty=$((30 - filled))
        local left
        local right
        left=$(printf '%0.s█' $(seq 1 $filled))
        right=$(printf '%0.s ' $(seq 1 $empty))
        local bar="${left}${right}"
        # Calculate ETA using PROG_START_TIME if available
        local eta="?"
        if [ -n "${PROG_START_TIME:-}" ] && [ "$elapsed" -gt 0 ]; then
            local remaining=$(( total - elapsed ))
            eta=$(printf "%02d:%02d" $((remaining/60)) $((remaining%60)))
        fi
        printf "\r[%-30s] %3d%% (%ds/%ds) ETA %s" "$bar" "$pct" "$elapsed" "$total" "$eta"
    else
        printf "."
    fi
}

progress_bar_stop() {
    if [ -t 1 ]; then
        printf "\n"
    else
        printf "\n"
    fi
}

# Abort helper for signal-handling: prints a message and exits
abort() {
    if [ "$#" -gt 0 ]; then
        error "$1"
    else
        error "Operation aborted by user"
    fi
    exit 130
}

# Read input with interrupt handling: read_input <varname> [prompt]
read_input() {
    local __var="$1"
    local prompt="${2-}"
    if [ -n "$prompt" ]; then
        # Use printf %b so ANSI escape sequences are interpreted (e.g. ${CYAN})
        printf '%b' "$prompt"
    fi
    # shellcheck disable=SC2034
    if ! IFS= read -r input_val; then
        # read returned non-zero: likely EOF or signal (Ctrl+C)
        abort "Input interrupted"
    fi
    printf -v "$__var" '%s' "$input_val"
}
