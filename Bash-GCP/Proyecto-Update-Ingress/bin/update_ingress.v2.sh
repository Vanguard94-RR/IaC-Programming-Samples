#!/usr/bin/env bash
# Entrypoint for UpdateIngress v2

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/downloader.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/healthcheck.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/kube.sh"

print_banner_box "GNP Cloud Infrastructure Team"
print_banner_box "Kubernetes Ingress Updater — v2"

# Flags: --dry-run and --verbose (positional URL allowed)
VERBOSE=false
DRY_RUN=false
DOWNLOAD_URL=""
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true; shift;;
        --verbose)
            VERBOSE=true; shift;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--verbose] [gitlab-blob-url]"; exit 0;;
        --*)
            echo "Unknown option: $1"; exit 1;;
        *)
            if [ -z "$DOWNLOAD_URL" ]; then DOWNLOAD_URL="$1"; fi; shift;;
    esac
done

# Solicitar Ticket ID y cambiar al directorio del ticket
if [ "${NO_CLUSTER:-0}" != "1" ]; then
    step "Configuración de Ticket"
    
    # Verificar si ya estamos en un directorio de ticket
    if [[ "$PWD" =~ /Tickets/(CTASK[0-9]+|TASK[0-9]+) ]]; then
        TICKET_ID="${BASH_REMATCH[1]}"
        info "Ticket detectado desde directorio actual: $TICKET_ID"
    else
        # Solicitar ticket ID
        read_input TICKET_ID "${CYAN}Ingrese el ID del Ticket (ej: CTASK0337281): ${WHITE}${BOLD}"
        printf '%b' "${NC}"
        
        if [ -z "$TICKET_ID" ]; then
            error "El ID del ticket no puede estar vacío"
            exit 1
        fi
        
        # Validar formato del ticket
        if ! [[ "$TICKET_ID" =~ ^(CTASK|TASK)[0-9]+$ ]]; then
            error "Formato de ticket inválido. Use CTASK######## o TASK#######"
            exit 1
        fi
    fi
    
    # Definir directorio base de tickets
    TICKETS_BASE="/home/admin/Documents/GNP/Tickets"
    TICKET_DIR="$TICKETS_BASE/$TICKET_ID"
    
    # Verificar si el directorio del ticket existe
    if [ ! -d "$TICKET_DIR" ]; then
        warn "El directorio del ticket no existe: $TICKET_DIR"
        read_input CREATE_DIR "${CYAN}¿Desea crear el directorio? (Y/N): ${NC}"
        CREATE_DIR_LOWER=$(printf "%s" "$CREATE_DIR" | tr '[:upper:]' '[:lower:]')
        
        if [ "$CREATE_DIR_LOWER" = "yes" ] || [ "$CREATE_DIR_LOWER" = "y" ]; then
            if mkdir -p "$TICKET_DIR"; then
                success "Directorio creado: $TICKET_DIR"
            else
                error "No se pudo crear el directorio"
                exit 1
            fi
        else
            error "Operación cancelada: El directorio del ticket es necesario"
            exit 1
        fi
    fi
    
    # Cambiar al directorio del ticket
    if cd "$TICKET_DIR"; then
        success "Trabajando en: $TICKET_DIR"
        export TICKET_ID
        export TICKET_DIR
    else
        error "No se pudo cambiar al directorio: $TICKET_DIR"
        exit 1
    fi
fi
# If running in test/no-cluster mode, skip cluster prerequisites
if [ "${NO_CLUSTER:-0}" = "1" ]; then
    info "NO_CLUSTER=1 detected: skipping kubectl and cluster prerequisite checks (test mode)."
else
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl not found"
        exit 1
    fi
fi

# Ensure ingress.yaml available (download if requested)
if [ ! -f "ingress.yaml" ]; then
    if [ -n "$DOWNLOAD_URL" ]; then
        info "Using provided download URL"
        if ! download_gitlab_raw "$DOWNLOAD_URL"; then
            error "Failed to download ingress.yaml from provided URL"
            exit 1
        fi
    else
        # If running non-interactively (no TTY) or in dry-run/test mode, don't prompt; fail fast
        if [ "${DRY_RUN:-false}" = "true" ] || [ "${NO_CLUSTER:-0}" = "1" ] || [ ! -t 0 ]; then
            error "ingress.yaml not found and no download URL provided. Set DOWNLOAD_URL or run interactively to provide a URL."
            exit 1
        fi

        # Interactive prompt
        read_input url "Enter GitLab blob URL to download ingress.yaml (or empty to abort): "
        if [ -n "$url" ]; then
            if ! download_gitlab_raw "$url"; then
                error "Failed to download ingress.yaml from provided URL"
                exit 1
            fi
        else
            error "No URL provided and ingress.yaml missing. Aborting."
            exit 1
        fi
    fi
fi

success "Prereqs OK"

# If running smoke tests or in environments without cluster access, allow skipping
# cluster selection and apply steps by setting NO_CLUSTER=1 in the environment.
if [ "${NO_CLUSTER:-0}" = "1" ]; then
    info "NO_CLUSTER=1 detected: skipping cluster selection and apply steps (test mode)."
    exit 0
fi

# Full flow
select_gcp_project
select_cluster
connect_to_cluster
namespace_and_ingress_name
backup_current_ingress
apply_new_ingress

echo -e "${CYAN}Script finished.${NC}"
