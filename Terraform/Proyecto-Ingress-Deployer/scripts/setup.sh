#!/usr/bin/env bash
# =============================================================================
# Ingress Deployer — Dependency Setup & Installation
# Idempotent installer for terraform, gcloud, kubectl, yq
#
# Usage:
#   bash scripts/setup.sh               # install/verify all dependencies
#   bash scripts/setup.sh --reconfigure # re-run all checks
#
# Sets up ~/.gnp/ingress/ config, patches ~/.bashrc with tool paths
# =============================================================================

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/ui.sh"

# ---------------------------------------------------------------------------
# Constants / Paths (shared with Dispatch-Executor pattern)
# ---------------------------------------------------------------------------
GNP_HOME="${GNP_HOME:-$HOME/.gnp}"
INGRESS_CONFIG_DIR="$GNP_HOME/ingress"
INSTALL_MARKER="$INGRESS_CONFIG_DIR/.install-marker"
CONFIG_FILE="$INGRESS_CONFIG_DIR/config.env"
BOOTSTRAP_LOG="$INGRESS_CONFIG_DIR/bootstrap.log"
CURRENT_VERSION="v1.0.0"

# Flags
RECONFIGURE=false

for arg in "$@"; do
    case "$arg" in
        --reconfigure) RECONFIGURE=true ;;
        -h|--help)
            printf "Usage: %s [--reconfigure]\n" "$0"
            exit 0 ;;
        *)
            error "Unknown flag: $arg"
            exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
print_banner "Ingress Deployer — Dependency Setup"

# ---------------------------------------------------------------------------
# Step 1: Create config directories
# ---------------------------------------------------------------------------
step "Creating configuration directories"
mkdir -p "$INGRESS_CONFIG_DIR"
success "Config directory ready: $INGRESS_CONFIG_DIR"

# ---------------------------------------------------------------------------
# Step 2: OS Detection
# ---------------------------------------------------------------------------
detect_os() {
    # GCP Cloud Shell detection
    if [ -n "${CLOUDSHELL_ENVIRONMENT:-}" ]; then
        echo "cloudshell"; return
    fi

    if [ -r /etc/os-release ]; then
        local id id_like
        id=$(. /etc/os-release && echo "${ID:-}")
        id_like=$(. /etc/os-release && echo "${ID_LIKE:-}")

        case "$id" in
            fedora)                   echo "fedora";  return ;;
            debian|ubuntu|linuxmint)  echo "debian";  return ;;
        esac

        case "$id_like" in
            *rhel*|*fedora*)  echo "fedora"; return ;;
            *debian*)         echo "debian"; return ;;
        esac
    fi

    if [ "$(uname -s)" = "Darwin" ]; then
        echo "macos"; return
    fi

    echo "unknown"
}

DETECTED_OS=$(detect_os)
step "Environment detected: $DETECTED_OS"
info "OS: $DETECTED_OS"

# ---------------------------------------------------------------------------
# Step 3: Architecture detection for tarball downloads
# ---------------------------------------------------------------------------
detect_arch() {
    case "$(uname -m)" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *)
            error "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac
}

ARCH=$(detect_arch)
info "Architecture: $ARCH"

# ---------------------------------------------------------------------------
# Helper: ~/.bashrc patching (tagged block, idempotent)
# ---------------------------------------------------------------------------
_patch_bashrc() {
    local new_path="$1"
    local bashrc="$HOME/.bashrc"
    local tag_begin="# BEGIN ingress-deployer-managed"
    local tag_end="# END ingress-deployer-managed"
    local new_entry="export PATH=\"${new_path}:\$PATH\""

    # Already present?
    if grep -qF "$new_path" "$bashrc" 2>/dev/null; then
        info "~/.bashrc already has: $new_path"
        return 0
    fi

    local tmp
    tmp=$(mktemp)

    if grep -q "$tag_begin" "$bashrc" 2>/dev/null; then
        # Extract existing lines inside block
        local existing_lines
        existing_lines=$(sed -n "/${tag_begin}/,/${tag_end}/{/${tag_begin}/d;/${tag_end}/d;p}" "$bashrc")

        # Rebuild without old block
        sed "/${tag_begin}/,/${tag_end}/d" "$bashrc" > "$tmp"

        # Append updated block
        {
            printf '\n%s\n' "$tag_begin"
            [ -n "$existing_lines" ] && printf '%s\n' "$existing_lines"
            printf '%s\n' "$new_entry"
            printf '%s\n' "$tag_end"
        } >> "$tmp"
    else
        # No existing block — append fresh one
        cat "$bashrc" > "$tmp" 2>/dev/null || true
        {
            printf '\n%s\n' "$tag_begin"
            printf '%s\n' "$new_entry"
            printf '%s\n' "$tag_end"
        } >> "$tmp"
    fi

    mv "$tmp" "$bashrc"
    info "~/.bashrc updated: PATH += $new_path"
}

# ---------------------------------------------------------------------------
# Helper: Version checking
# ---------------------------------------------------------------------------
_terraform_version_ok() {
    command -v terraform &>/dev/null || return 1
    local ver major minor
    ver=$(terraform version 2>/dev/null | grep -oP 'Terraform v\K[0-9]+\.[0-9]+' | head -1)
    [ -z "$ver" ] && return 1
    major=$(echo "$ver" | cut -d. -f1)
    minor=$(echo "$ver" | cut -d. -f2)
    [ "$major" -gt 1 ] && return 0
    [ "$major" -eq 1 ] && [ "$minor" -ge 0 ] && return 0
    return 1
}

_gcloud_installed() {
    command -v gcloud &>/dev/null || return 1
}

_kubectl_version_ok() {
    command -v kubectl &>/dev/null || return 1
}

_yq_version_ok() {
    command -v yq &>/dev/null || return 1
    local ver
    ver=$(yq --version 2>/dev/null | grep -oP 'yq \K[0-9]+' | head -1)
    [ -z "$ver" ] && return 1
    [ "$ver" -ge 4 ]
}

# ---------------------------------------------------------------------------
# Terraform install
# ---------------------------------------------------------------------------
ensure_terraform() {
    step "Terraform (>= 1.0)"

    if _terraform_version_ok; then
        ok "Terraform $(terraform version | head -1 | grep -oP 'v[0-9.]+') ✓"
        return 0
    fi

    info "Installing terraform..."

    case "$DETECTED_OS" in
        cloudshell)
            error "Terraform should be pre-installed in Cloud Shell"
            return 1
            ;;
        fedora)
            if command -v dnf &>/dev/null; then
                sudo dnf install -y terraform 2>/dev/null && ok "Terraform installed via dnf" && return 0
            fi
            ;;
        debian)
            if command -v apt-get &>/dev/null; then
                curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add - 2>/dev/null || true
                sudo apt-add-repository "deb [arch=$(dpkg --print-architecture)] https://apt.releases.hashicorp.com $(lsb_release -cs) main" 2>/dev/null || true
                sudo apt-get update -q 2>/dev/null || true
                sudo apt-get install -y terraform 2>/dev/null && ok "Terraform installed via apt" && return 0
            fi
            ;;
        macos)
            if command -v brew &>/dev/null; then
                brew install terraform 2>/dev/null && ok "Terraform installed via brew" && return 0
            fi
            ;;
    esac

    # Fallback: tarball
    _install_terraform_tarball
}

_install_terraform_tarball() {
    local tf_home="$GNP_HOME/terraform"
    info "Falling back to tarball install: $tf_home"

    local version
    version=$(curl -fsSL "https://api.github.com/repos/hashicorp/terraform/releases/latest" 2>/dev/null | grep -oP '"tag_name": "v\K[0-9.]+' | head -1)
    if [ -z "$version" ]; then
        error "Could not determine latest Terraform version"
        return 1
    fi

    local tarball="terraform_${version}_linux_${ARCH}.zip"
    local url="https://releases.hashicorp.com/terraform/${version}/${tarball}"
    local tmp
    tmp=$(mktemp --suffix=".zip")

    info "Downloading terraform v$version..."
    if ! curl -fsSL "$url" -o "$tmp"; then
        error "Download failed: $url"
        rm -f "$tmp"
        return 1
    fi

    mkdir -p "$tf_home/bin"
    unzip -o "$tmp" -d "$tf_home/bin" >/dev/null
    rm -f "$tmp"

    export PATH="$tf_home/bin:$PATH"
    _patch_bashrc "$tf_home/bin"
    success "Terraform installed to $tf_home ($(terraform version | head -1 | grep -oP 'v[0-9.]+'))"
}

# ---------------------------------------------------------------------------
# gcloud install
# ---------------------------------------------------------------------------
ensure_gcloud() {
    step "gcloud SDK"

    if _gcloud_installed; then
        ok "gcloud $(gcloud --version 2>/dev/null | head -1 | grep -oP '[0-9]+\.[0-9.]+') ✓"
        return 0
    fi

    info "Installing gcloud SDK..."

    case "$DETECTED_OS" in
        cloudshell)
            ok "gcloud pre-installed in Cloud Shell ✓"
            return 0
            ;;
        fedora)
            if command -v sudo &>/dev/null; then
                sudo tee /etc/yum.repos.d/google-cloud-sdk.repo > /dev/null <<'REPO' 2>/dev/null
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
REPO
                sudo dnf install -y google-cloud-cli 2>/dev/null && ok "gcloud installed via dnf" && return 0
            fi
            ;;
        debian)
            if command -v sudo &>/dev/null; then
                curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg 2>/dev/null | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg 2>/dev/null || true
                echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null 2>/dev/null || true
                sudo apt-get update -q 2>/dev/null && sudo apt-get install -y google-cloud-cli 2>/dev/null && ok "gcloud installed via apt" && return 0
            fi
            ;;
        macos)
            if command -v brew &>/dev/null; then
                brew install --cask google-cloud-sdk 2>/dev/null && ok "gcloud installed via brew" && return 0
            fi
            ;;
    esac

    # Fallback: official script
    _install_gcloud_script
}

_install_gcloud_script() {
    local install_dir="$HOME/google-cloud-sdk-install"
    info "Installing gcloud SDK to $install_dir (this may take a few minutes)..."
    if ! curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir="$install_dir" >/dev/null 2>&1; then
        error "gcloud install script failed"
        return 1
    fi
    _patch_bashrc "$install_dir/bin"
    export PATH="$install_dir/bin:$PATH"
    success "gcloud installed to $install_dir"
}

# ---------------------------------------------------------------------------
# kubectl install
# ---------------------------------------------------------------------------
ensure_kubectl() {
    step "kubectl"

    if _kubectl_version_ok; then
        ok "kubectl $(kubectl version --client --short 2>/dev/null | grep -oP 'v[0-9.]+') ✓"
        return 0
    fi

    info "Installing kubectl..."

    case "$DETECTED_OS" in
        cloudshell)
            ok "kubectl pre-installed in Cloud Shell ✓"
            return 0
            ;;
        fedora)
            if command -v dnf &>/dev/null; then
                sudo dnf install -y kubernetes-client 2>/dev/null && ok "kubectl installed via dnf" && return 0
            fi
            ;;
        debian)
            if command -v apt-get &>/dev/null; then
                curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null || true
                echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null 2>/dev/null || true
                sudo apt-get update -q 2>/dev/null && sudo apt-get install -y kubectl 2>/dev/null && ok "kubectl installed via apt" && return 0
            fi
            ;;
        macos)
            if command -v brew &>/dev/null; then
                brew install kubectl 2>/dev/null && ok "kubectl installed via brew" && return 0
            fi
            ;;
    esac

    # Fallback: tarball
    _install_kubectl_tarball
}

_install_kubectl_tarball() {
    local kubectl_home="$GNP_HOME/kubectl"
    info "Falling back to tarball install: $kubectl_home"

    local version
    version=$(curl -fsSL "https://dl.k8s.io/release/stable.txt" 2>/dev/null)
    if [ -z "$version" ]; then
        error "Could not determine latest kubectl version"
        return 1
    fi

    local url="https://dl.k8s.io/release/${version}/bin/linux/${ARCH}/kubectl"
    local tmp
    tmp=$(mktemp)

    info "Downloading kubectl $version..."
    if ! curl -fsSL "$url" -o "$tmp"; then
        error "Download failed: $url"
        rm -f "$tmp"
        return 1
    fi

    mkdir -p "$kubectl_home/bin"
    chmod +x "$tmp"
    mv "$tmp" "$kubectl_home/bin/kubectl"
    export PATH="$kubectl_home/bin:$PATH"
    _patch_bashrc "$kubectl_home/bin"
    success "kubectl installed to $kubectl_home"
}

# ---------------------------------------------------------------------------
# yq install
# ---------------------------------------------------------------------------
ensure_yq() {
    step "yq (>= 4.0)"

    if _yq_version_ok; then
        ok "yq $(yq --version 2>/dev/null | grep -oP '[0-9]+\.[0-9.]+') ✓"
        return 0
    fi

    info "Installing yq..."

    case "$DETECTED_OS" in
        cloudshell)
            warn "yq not pre-installed in Cloud Shell, installing..."
            ;;
        fedora)
            if command -v dnf &>/dev/null; then
                sudo dnf install -y yq 2>/dev/null && ok "yq installed via dnf" && return 0
            fi
            ;;
        debian)
            if command -v apt-get &>/dev/null; then
                sudo apt-get install -y yq 2>/dev/null && ok "yq installed via apt" && return 0
            fi
            ;;
        macos)
            if command -v brew &>/dev/null; then
                brew install yq 2>/dev/null && ok "yq installed via brew" && return 0
            fi
            ;;
    esac

    # Fallback: tarball
    _install_yq_tarball
}

_install_yq_tarball() {
    local yq_home="$GNP_HOME/yq"
    info "Falling back to tarball install: $yq_home"

    local version
    version=$(curl -fsSL "https://api.github.com/repos/mikefarah/yq/releases/latest" 2>/dev/null | grep -oP '"tag_name": "v\K[0-9.]+' | head -1)
    if [ -z "$version" ]; then
        error "Could not determine latest yq version"
        return 1
    fi

    local binary="yq_linux_${ARCH}"
    local url="https://github.com/mikefarah/yq/releases/download/v${version}/${binary}"
    local tmp
    tmp=$(mktemp)

    info "Downloading yq v$version..."
    if ! curl -fsSL "$url" -o "$tmp"; then
        error "Download failed: $url"
        rm -f "$tmp"
        return 1
    fi

    mkdir -p "$yq_home/bin"
    chmod +x "$tmp"
    mv "$tmp" "$yq_home/bin/yq"
    export PATH="$yq_home/bin:$PATH"
    _patch_bashrc "$yq_home/bin"
    success "yq installed to $yq_home"
}

# ---------------------------------------------------------------------------
# Main orchestrator: ensure all dependencies
# ---------------------------------------------------------------------------
step "Dependency Check & Installation"
ensure_terraform
ensure_gcloud
ensure_kubectl
ensure_yq

# ---------------------------------------------------------------------------
# Step 4: Save config marker and log
# ---------------------------------------------------------------------------
step "Saving configuration"

# Create install marker
cat > "$INSTALL_MARKER" <<MARKER
INSTALLED_VERSION=$CURRENT_VERSION
INSTALL_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OS=$DETECTED_OS
ARCH=$ARCH
MARKER

ok "Install marker: $INSTALL_MARKER"

# Save log
{
    echo "=== Ingress Deployer Setup ==="
    echo "Date: $(date)"
    echo "OS: $DETECTED_OS"
    echo "Architecture: $ARCH"
    echo "Terraform: $(terraform version 2>/dev/null | head -1 || echo 'ERROR')"
    echo "gcloud: $(gcloud --version 2>/dev/null | head -1 || echo 'ERROR')"
    echo "kubectl: $(kubectl version --client --short 2>/dev/null || echo 'ERROR')"
    echo "yq: $(yq --version 2>/dev/null || echo 'ERROR')"
} > "$BOOTSTRAP_LOG"

ok "Bootstrap log: $BOOTSTRAP_LOG"

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
echo ""
print_banner "Setup Complete ✓"
echo ""
info "Next steps:"
echo "  1. Authenticate with GCP:"
echo "     $ gcloud auth login"
echo "  2. Set your project (or export PROJECT_ID env var)"
echo "  3. Initialize backend and deploy:"
echo "     $ make backend    # Initialize GCS state bucket"
echo "     $ make deploy     # Deploy ingress"
echo ""
info "Configuration saved to: $INGRESS_CONFIG_DIR"
info "Bootstrap log: $BOOTSTRAP_LOG"
info "See README.md for detailed operations guide"
echo ""
