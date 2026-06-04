#!/usr/bin/env bash
# Strips GKE controller-managed fields from Kubernetes manifest YAML.
# Required before terraform apply to prevent drift and field manager conflicts.
# Requires: yq v4 (mikefarah/yq)

# clean_ingress_yaml <input-path> <output-path>
# input and output may be the same path (in-place strip).
clean_ingress_yaml() {
  local input="$1" output="$2"
  local tmp
  tmp=$(mktemp)
  yq 'del(
    .metadata.resourceVersion,
    .metadata.uid,
    .metadata.creationTimestamp,
    .metadata.generation,
    .metadata.finalizers,
    .metadata.annotations["ingress.kubernetes.io/backends"],
    .metadata.annotations["ingress.kubernetes.io/forwarding-rule"],
    .metadata.annotations["ingress.kubernetes.io/https-forwarding-rule"],
    .metadata.annotations["ingress.kubernetes.io/https-target-proxy"],
    .metadata.annotations["ingress.kubernetes.io/target-proxy"],
    .metadata.annotations["ingress.kubernetes.io/url-map"],
    .status
  )' "$input" > "$tmp"
  mv "$tmp" "$output"
}

# Allowlist: apiGroup prefixes that identify IaC companion resources
_COMPANION_GROUPS="cloud\\.google\\.com|networking\\.gke\\.io"

# Lifecycle companions: destroyed alongside the ingress on ACTION=destroy
_LIFECYCLE_KINDS="BackendConfig FrontendConfig"

# Create-only companions: deployed but never destroyed by this script
_CREATE_ONLY_KINDS="ManagedCertificate"

# extract_companions <source-yaml> <companions-dir>
# Extracts all IaC companion documents from a (possibly multi-document) YAML file.
# Each companion is written to <companions-dir>/Kind-name.yaml and cleaned.
# Skips: Ingress, Service, Deployment, ConfigMap, Secret regardless of apiGroup.
extract_companions() {
  local src="$1" companions_dir="$2"
  mkdir -p "$companions_dir"

  local companions
  companions=$(yq \
    'select(.apiVersion | test("^('"$_COMPANION_GROUPS"')/"))
     | select(.kind != "Ingress")
     | select(.kind != "Service")
     | select(.kind != "Deployment")
     | select(.kind != "ConfigMap")
     | select(.kind != "Secret")
     | .kind + "/" + (.metadata.namespace // "_") + "/" + .metadata.name' \
    "$src" || true)

  [[ -z "$companions" ]] && return 0

  while IFS='/' read -r kind ns name; do
    [[ -z "$kind" || -z "$name" ]] && continue
    local ns_part="${ns:-_}"
    local out="$companions_dir/${kind}-${ns_part}-${name}.yaml"
    yq "select(.kind == \"$kind\" and (.metadata.namespace // \"_\") == \"${ns_part}\" and .metadata.name == \"$name\")" "$src" > "$out"
    clean_ingress_yaml "$out" "$out"
    ok "Companion extracted: $kind/$ns_part/$name"
  done <<< "$companions"
}
