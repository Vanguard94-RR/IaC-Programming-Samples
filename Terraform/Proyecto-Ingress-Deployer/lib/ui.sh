#!/usr/bin/env bash
# Shared UI and logging for ingress deployer scripts

if { [[ -t 1 ]] || [[ "${FORCE_COLOR:-0}" == "1" ]]; } && [[ -z "${NO_COLOR:-}" ]]; then
  GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"
  CYAN="\033[0;36m"; WHITE="\033[1;37m"; BOLD="\033[1m"; NC="\033[0m"
else
  GREEN=""; YELLOW=""; RED=""; CYAN=""; WHITE=""; BOLD=""; NC=""
fi

# LOG_FILE and CENTRAL_PROJECT must be set by the calling script before sourcing
LOG_FILE="${LOG_FILE:-/dev/null}"
CENTRAL_PROJECT="${CENTRAL_PROJECT:-gnp-fleets-qa}"

_ts() { date '+%Y-%m-%d %H:%M:%S'; }

_log_persist() {
  local level="$1"; shift
  local msg; msg="[$(_ts)] [$level] $*"
  echo "$msg" >> "$LOG_FILE"
  gcloud logging write ingress-deployer "$msg" \
    --project="$CENTRAL_PROJECT" --severity="$level" 2>/dev/null || true
}

step()    { printf "\n${CYAN}➜ ${BOLD}%s${NC}\n" "$*"; }
info()    { printf "${WHITE}• %s${NC}\n" "$*"; _log_persist "INFO" "$@"; }
ok()      { printf "${GREEN}✔ %s${NC}\n" "$*"; _log_persist "INFO" "$@"; }
warn()    { printf "${YELLOW}⚠ %s${NC}\n" "$*"; _log_persist "WARNING" "$@"; }
error()   { printf "${RED}✗ %s${NC}\n" "$*" >&2; _log_persist "ERROR" "$@"; }

print_banner() {
  local title="$1"; local width=48; local bar=""
  for (( i=0; i<width; i++ )); do bar+="═"; done
  printf '%b\n' "${CYAN}╔${bar}╗${NC}"
  printf '%b' "${CYAN}║${NC}"
  printf "%*s" $(( (width + ${#title}) / 2 )) "$title"
  printf "%*s" $(( width - (width + ${#title}) / 2 )) ""
  printf '%b\n' "${CYAN}║${NC}"
  printf '%b\n' "${CYAN}╚${bar}╝${NC}"
}

wait_for_ingress_ip() {
  local ns="$1" name="$2" timeout="${3:-300}" elapsed=0
  info "Waiting for ingress IP assignment (timeout ${timeout}s)..."
  while [[ $elapsed -lt $timeout ]]; do
    local ip
    ip=$(kubectl get ingress -n "$ns" "$name" \
           -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [[ -n "$ip" ]]; then
      ok "Ingress IP assigned: $ip"
      return 0
    fi
    sleep 15; (( elapsed += 15 ))
    info "Still waiting... (${elapsed}s elapsed)"
  done
  error "Timeout: ingress $name in $ns did not receive IP within ${timeout}s"
  return 1
}

_get_credentials() {
  local project="$1" cluster="$2" location="$3"
  if [[ "$location" =~ ^[a-z]+-[a-z0-9]+-[a-z]$ ]]; then
    gcloud container clusters get-credentials "$cluster" \
      --zone="$location" --project="$project"
  else
    gcloud container clusters get-credentials "$cluster" \
      --region="$location" --project="$project"
  fi
}
