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
    .metadata.annotations["ingress.kubernetes.io/target-proxy"],
    .metadata.annotations["ingress.kubernetes.io/url-map"],
    .status
  )' "$input" > "$tmp"
  mv "$tmp" "$output"
}
