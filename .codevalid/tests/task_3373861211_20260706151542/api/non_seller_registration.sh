#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="buyer.${CASE_SUFFIX}@test.com"
PASSWORD="SecurePass123!"
RESPONSE_FILE="/tmp/non_seller_registration_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/non_seller_registration_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null

# When
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"BUYER\"}")"
printf '%s' "$HTTP_STATUS" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
[ "$(jq -r '.user.email' "$RESPONSE_FILE")" = "$EMAIL" ]
[ "$(jq -r '.user.status' "$RESPONSE_FILE")" = "ACTIVE" ]
[ "$(jq -r '.user.role' "$RESPONSE_FILE")" = "BUYER" ]
[ "$(jq -r '.user.sellerProfile' "$RESPONSE_FILE")" = "null" ]
echo "CODEVALID_TEST_ASSERTION_OK:non_seller_registration"

# Cleanup
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null
