#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TMP_DIR="$(mktemp -d)"
RESPONSE_BODY="$TMP_DIR/body.json"
STATUS_FILE="$TMP_DIR/status.txt"
trap 'rm -rf "$TMP_DIR"' EXIT

# Given
REQUEST_ID="unauth-${CASE_SUFFIX}"

# When
curl -sS -o "$RESPONSE_BODY" -w '%{http_code}' "$BASE_URL/seller/dashboard" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "401" ]
grep -E 'error|Unauthorized|unauthorized|authentication' "$RESPONSE_BODY" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:unauthenticated_access_blocked"

# Cleanup
