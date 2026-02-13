#!/usr/bin/env bash
# Simple smoke test: run the v2 entrypoint in dry-run + verbose mode

set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRY="$ROOT_DIR/bin/update_ingress.v2.sh"

if [ ! -x "$ENTRY" ]; then
    echo "Entrypoint not found or not executable: $ENTRY"
    exit 2
fi

TMP_INGRESS="$(pwd)/ingress.yaml"
FIXTURE="$ROOT_DIR/test/fixtures/ingress_sample.yaml"

cleanup() {
    rm -f "$TMP_INGRESS" || true
}
trap cleanup EXIT INT TERM

echo "Preparing fixture ingress.yaml"
cp "$FIXTURE" "$TMP_INGRESS"

export NO_CLUSTER=1

echo "Running smoke test: dry-run + verbose"
"$ENTRY" --dry-run --verbose || {
    echo "Smoke test failed"
    exit 1
}
echo "Smoke test completed (exit 0)"
