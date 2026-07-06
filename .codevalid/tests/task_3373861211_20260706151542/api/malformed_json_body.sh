#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/malformed_json_body_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/malformed_json_body_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
: "registration endpoint available"

# When
HTTP_STATUS="$(printf '%s' '{ "email": "broken@test.com", "password": ' | curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' --data-binary @-)"
printf '%s' "$HTTP_STATUS" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ] || [ "$STATUS" = "500" ]
grep -q 'error' "$RESPONSE_FILE"
echo "CODEVALID_TEST_ASSERTION_OK:malformed_json_body"
