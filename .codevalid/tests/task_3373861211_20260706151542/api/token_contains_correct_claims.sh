#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="token.test.${CASE_SUFFIX}@test.com"
PASSWORD="SecurePass123!"
STORE_NAME="Token Test Shop ${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/token_contains_correct_claims_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/token_contains_correct_claims_${CASE_SUFFIX}.status"
PAYLOAD_FILE="/tmp/token_contains_correct_claims_${CASE_SUFFIX}.payload.json"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$PAYLOAD_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EMAIL}'); DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null

# When
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\"}")"
printf '%s' "$HTTP_STATUS" > "$STATUS_FILE"
TOKEN="$(jq -r '.token' "$RESPONSE_FILE")"
TOKEN_PAYLOAD_B64="$(printf '%s' "$TOKEN" | cut -d '.' -f 2)"
TOKEN_PAYLOAD_B64_PADDED="$TOKEN_PAYLOAD_B64"
while [ $(( ${#TOKEN_PAYLOAD_B64_PADDED} % 4 )) -ne 0 ]; do TOKEN_PAYLOAD_B64_PADDED="${TOKEN_PAYLOAD_B64_PADDED}="; done
printf '%s' "$TOKEN_PAYLOAD_B64_PADDED" | tr '_-' '/+' | base64 -d > "$PAYLOAD_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
[ "$(jq -r '.email' "$PAYLOAD_FILE")" = "$EMAIL" ]
[ "$(jq -r '.role' "$PAYLOAD_FILE")" = "SELLER" ]
[ "$(jq -r '.status' "$PAYLOAD_FILE")" = "PENDING" ]
[ "$(jq -r '.sellerProfileId' "$PAYLOAD_FILE")" = "$(jq -r '.user.sellerProfile.id' "$RESPONSE_FILE")" ]
[ "$(jq -r '.id' "$PAYLOAD_FILE")" = "$(jq -r '.user.id' "$RESPONSE_FILE")" ]
echo "CODEVALID_TEST_ASSERTION_OK:token_contains_correct_claims"

# Cleanup
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EMAIL}'); DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null
