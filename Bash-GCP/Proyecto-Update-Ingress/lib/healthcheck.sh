#!/usr/bin/env bash
# Healthcheck helpers for UpdateIngress v2

set -o errexit
set -o nounset
set -o pipefail

# Lightweight wrappers: call UI functions if available, otherwise fallback to echo
_has_func() { type "$1" >/dev/null 2>&1; }
_step()   { if _has_func step; then step "$1"; else printf "STEP: %s\n" "$1"; fi }
_info()   { if _has_func info; then info "$1"; else printf "INFO: %s\n" "$1"; fi }
_warn()   { if _has_func warn; then warn "$1"; else printf "WARN: %s\n" "$1"; fi }
_success(){ if _has_func success; then success "$1"; else printf "OK: %s\n" "$1"; fi }
_error()  { if _has_func error; then error "$1"; else printf "ERROR: %s\n" "$1"; fi }
_vprint(){ if _has_func vprint; then vprint "$1"; else printf "» %s\n" "$1"; fi }


# Validate health-check paths for each backend service referenced by the Ingress
# Parameters:
#   $1 - ingress name
#   $2 - namespace
#   $3 - loadbalancer IP to call
# Behavior:
#   - For each service in the Ingress, find a pod, read readinessProbe.httpGet.path
#   - If readinessProbe HTTP path is missing, the service is ignored
#   - Perform HTTP HEAD to http://<lb_ip><path> and consider 2xx/3xx as success
#   - Return 0 only if all non-ignored services return healthy; otherwise return 1
validate_health_checks() {
    local ingress_name="$1"
    local namespace="$2"
    local lb_ip="$3"

    _step "Validating backend health-check paths against LB IP: ${lb_ip:-<none>}"

    if [ -z "${lb_ip:-}" ]; then
        _warn "No LoadBalancer IP provided to validate_health_checks"
        return 1
    fi

    # Build a list of ingress rule entries containing: host|path|service
    # We'll prefer the Ingress rule's host and path when performing checks so
    # the request matches how the LB routes traffic. If an ingress path is
    # missing for a service, we fall back to the pod's readinessProbe.httpGet.path.
    local rules
    rules=$(kubectl get ingress "$ingress_name" -n "$namespace" -o jsonpath='{range .spec.rules[*]}{.host}"|"{.http.paths[*].path}"|"{.http.paths[*].backend.service.name}{"\n"}{end}' 2>/dev/null || true)
    if [ -z "${rules}" ]; then
        _info "No rules with services found in Ingress to validate."
        return 0
    fi

    local all_ok=true
    local line host path svc
    # rules format per-line: host|path|service
    while IFS= read -r line; do
        # Skip empty lines
        [ -z "${line}" ] && continue
        host=$(printf "%s" "$line" | awk -F'"|"' '{print $1}')
        path=$(printf "%s" "$line" | awk -F'"|"' '{print $2}')
        svc=$(printf "%s" "$line" | awk -F'"|"' '{print $3}')

        # normalize empty fields
        host=${host:-}
        path=${path:-}

        _info "Checking service: ${svc} (ingress host: ${host:-<none>} path: ${path:-<none>})"

        # Resolve a pod for the service so we can inspect container ports and readinessProbe if needed
        local selector pods pod
        selector=$(kubectl get svc "$svc" -n "$namespace" -o jsonpath='{.spec.selector}' 2>/dev/null || true)
        if [ -n "$selector" ]; then
            # attempt to use common label keys (app, app.kubernetes.io/name)
            pods=$(kubectl get pods -n "$namespace" -l app -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
        fi
        if [ -z "$pods" ]; then
            pods=$(kubectl get pods -n "$namespace" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | grep "^${svc}" || true)
        fi
        if [ -z "$pods" ]; then
            _warn "No pods found for service $svc; cannot inspect container ports. Will still attempt host/path check if available."
        else
            pod=$(printf "%s" "$pods" | awk '{print $1}')
        fi

        # Determine check path: prefer ingress path, fallback to readinessProbe.httpGet.path on pod
        local check_path
        if [ -n "$path" ]; then
            check_path="$path"
        else
            if [ -n "${pod:-}" ]; then
                check_path=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[0].readinessProbe.httpGet.path}' 2>/dev/null || true)
            fi
        fi

        if [ -z "$check_path" ]; then
            _warn "No HTTP path available for service $svc (no ingress path and no readinessProbe) — ignoring this service for health-checks."
            continue
        fi

        # Determine port exposed by the Service -> needs to be the port the LB expects.
        # Try to get the service port number from the Service resource. If the port is named
        # (string), attempt to resolve the targetPort number from the service spec.
        local svc_port svc_targetport resolved_port
        svc_port=$(kubectl get svc "$svc" -n "$namespace" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)
        svc_targetport=$(kubectl get svc "$svc" -n "$namespace" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || true)
        resolved_port=""
        if printf '%s' "$svc_port" | grep -qE '^[0-9]+$'; then
            resolved_port="$svc_port"
        elif printf '%s' "$svc_targetport" | grep -qE '^[0-9]+$'; then
            resolved_port="$svc_targetport"
        else
            # could be named port; try to inspect the container port mapping on pod
            if [ -n "${pod:-}" ]; then
                # find first container port number
                resolved_port=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[0].ports[0].containerPort}' 2>/dev/null || true)
            fi
        fi

        # Build URL to the LoadBalancer IP. If we resolved a port, append it.
        local url
        if [ -n "$resolved_port" ]; then
            url="http://${lb_ip}:${resolved_port}${check_path}"
        else
            url="http://${lb_ip}${check_path}"
        fi

        _info "Testing health URL: $url (Host header: ${host:-<none>})"

        # Use Host header when ingress host is present so that the request is routed correctly
        local curl_opts=(--max-time 10 -s -o /dev/null -w "%{http_code}" -I)
        if [ -n "$host" ]; then
            curl_opts+=( -H "Host: ${host}" )
        fi

        # perform the request
        local status_code
        status_code=$(curl "${curl_opts[@]}" "$url" || echo "000")

        # numeric compare: fallback to 0 on non-numeric
        if ! printf '%s' "$status_code" | grep -qE '^[0-9]+$'; then
            status_code=0
        fi

        if [ "$status_code" -ge 200 ] && [ "$status_code" -lt 400 ]; then
            _success "Health check OK for $svc -> $url returned $status_code"
        else
            _warn "Health check FAILED for $svc -> $url returned $status_code"
            if [ -n "${pod:-}" ]; then
                _info "Inspect readinessProbe in pod: kubectl describe pod $pod -n $namespace"
            fi
            all_ok=false
        fi

    done < <(printf "%s" "$rules" | sed '/^$/d')

    if [ "$all_ok" = true ]; then
        return 0
    else
        return 1
    fi
}
