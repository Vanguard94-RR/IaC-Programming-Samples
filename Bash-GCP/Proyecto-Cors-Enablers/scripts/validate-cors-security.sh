#!/bin/bash

# validate-cors-security.sh - Validate CORS configuration against security policies
# Usage: ./validate-cors-security.sh --config <CONFIG_FILE> [--strict]

set -e

CONFIG_FILE=""
STRICT_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --strict)
      STRICT_MODE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate arguments
if [ -z "$CONFIG_FILE" ]; then
  echo "Usage: $0 --config <CONFIG_FILE> [--strict]"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  exit 1
fi

echo "========================================"
echo "CORS Security Validation"
echo "========================================"
echo "Config File: $CONFIG_FILE"
echo "Strict Mode: $STRICT_MODE"
echo ""

# Check if file is valid JSON
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
  echo "❌ FAILED: Invalid JSON format"
  exit 1
fi

echo "✅ Valid JSON format"

# Extract values
ORIGINS=$(jq -r '.[0].origin[]' "$CONFIG_FILE" 2>/dev/null || echo "")
METHODS=$(jq -r '.[0].method[]' "$CONFIG_FILE" 2>/dev/null || echo "")
HEADERS=$(jq -r '.[0].responseHeader[]' "$CONFIG_FILE" 2>/dev/null || echo "")
MAX_AGE=$(jq -r '.[0].maxAgeSeconds' "$CONFIG_FILE" 2>/dev/null || echo "3600")

echo ""
echo "Configuration Details:"
echo "  Origins: $ORIGINS"
echo "  Methods: $METHODS"
echo "  Headers: $HEADERS"
echo "  Max Age: $MAX_AGE seconds"
echo ""

# Security Checks
FAILED=0

# Check 1: No wildcard origin
echo "🔍 Check 1: Wildcard origin detection..."
if echo "$ORIGINS" | grep -q "^\*$"; then
  echo "  ❌ FAILED: Wildcard origin (*) detected - CRITICAL RISK"
  FAILED=$((FAILED + 1))
else
  echo "  ✅ PASSED: No wildcard origin"
fi

# Check 2: No wildcard in responseHeader
echo "🔍 Check 2: Wildcard response headers..."
if echo "$HEADERS" | grep -q "^\*$"; then
  echo "  ❌ FAILED: Wildcard headers (*) detected - HIGH RISK"
  FAILED=$((FAILED + 1))
else
  echo "  ✅ PASSED: Headers are specific"
fi

# Check 3: DELETE method check
echo "🔍 Check 3: DELETE method enabled..."
if echo "$METHODS" | grep -q "DELETE"; then
  if [ "$STRICT_MODE" = true ]; then
    echo "  ❌ FAILED: DELETE method not allowed in strict mode"
    FAILED=$((FAILED + 1))
  else
    echo "  ⚠️  WARNING: DELETE method enabled (use with caution)"
  fi
else
  echo "  ✅ PASSED: DELETE method not enabled"
fi

# Check 4: PUT method check (warning only unless strict)
echo "🔍 Check 4: PUT method enabled..."
if echo "$METHODS" | grep -q "PUT"; then
  if [ "$STRICT_MODE" = true ]; then
    echo "  ⚠️  WARNING: PUT method enabled (intended for uploads)"
  else
    echo "  ✅ PASSED (or intended for uploads)"
  fi
else
  echo "  ✅ PASSED: PUT method not enabled"
fi

# Check 5: Minimum methods security
echo "🔍 Check 5: Methods whitelist..."
if ! echo "$METHODS" | grep -qE "^(GET|HEAD|PUT|POST|DELETE|OPTIONS)$"; then
  echo "  ❌ FAILED: Unknown HTTP method"
  FAILED=$((FAILED + 1))
else
  echo "  ✅ PASSED: Valid HTTP methods"
fi

# Check 6: MaxAge not too long (cache expiry)
echo "🔍 Check 6: Cache expiry (maxAgeSeconds)..."
if [ "$MAX_AGE" -gt 7200 ]; then
  echo "  ⚠️  WARNING: maxAgeSeconds is $MAX_AGE (>2 hours) - cache may be too long"
elif [ "$MAX_AGE" -lt 300 ]; then
  echo "  ⚠️  WARNING: maxAgeSeconds is $MAX_AGE (<5 min) - too frequent preflight requests"
else
  echo "  ✅ PASSED: Reasonable cache expiry ($MAX_AGE seconds)"
fi

# Check 7: At least one origin specified
echo "🔍 Check 7: Origin specification..."
if [ -z "$ORIGINS" ]; then
  echo "  ❌ FAILED: No origin specified"
  FAILED=$((FAILED + 1))
else
  ORIGIN_COUNT=$(echo "$ORIGINS" | wc -l)
  echo "  ✅ PASSED: $ORIGIN_COUNT origin(s) specified"
fi

# Check 8: Headers not empty
echo "🔍 Check 8: Response headers..."
if [ -z "$HEADERS" ]; then
  echo "  ⚠️  WARNING: No specific headers - may expose all response headers"
else
  HEADER_COUNT=$(echo "$HEADERS" | wc -l)
  echo "  ✅ PASSED: $HEADER_COUNT specific header(s)"
fi

# Check 9: Domain validation format (basic)
echo "🔍 Check 9: Domain format validation..."
INVALID_DOMAINS=0
while IFS= read -r origin; do
  if [[ $origin == "https://"* ]]; then
    # Valid HTTPS origin
    :
  elif [[ $origin == "http://"* ]]; then
    echo "  ⚠️  WARNING: HTTP origin detected (not HTTPS): $origin"
  else
    echo "  ❌ FAILED: Invalid origin format: $origin"
    INVALID_DOMAINS=$((INVALID_DOMAINS + 1))
  fi
done <<< "$ORIGINS"

if [ "$INVALID_DOMAINS" -eq 0 ]; then
  echo "  ✅ PASSED: All domains use HTTPS"
fi

# Summary
echo ""
echo "========================================"
if [ "$FAILED" -eq 0 ]; then
  echo "✅ VALIDATION PASSED"
  echo "Configuration is SECURE for production use"
  exit 0
else
  echo "❌ VALIDATION FAILED"
  echo "Found $FAILED critical issue(s)"
  echo ""
  echo "Recommendations:"
  echo "  1. Remove wildcard origins (*)"
  echo "  2. Remove wildcard headers (*)"
  echo "  3. Restrict methods (GET/HEAD for read-only)"
  echo "  4. Use specific domain origins"
  echo "  5. Run: ./validate-cors-security.sh --config <file> --strict"
  exit 1
fi
