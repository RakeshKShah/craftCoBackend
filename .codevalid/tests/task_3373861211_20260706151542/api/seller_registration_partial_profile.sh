#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller.partial.${CASE_SUFFIX}@test.com"
PASSWORD="SecurePass123!"
STORE_NAME="Custom Shop Name ${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/seller_registration_partial_profile_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_registration_partial_profile_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EMAIL}'); DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null

# When
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\"}")"
printf '%s' "$HTTP_STATUS" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
[ "$(jq -r '.user.sellerProfile.storeName' "$RESPONSE_FILE")" = "$STORE_NAME" ]
[ "$(jq -r '.user.sellerProfile.bio' "$RESPONSE_FILE")" = "" ]
[ "$(jq -r '.user.status' "$RESPONSE_FILE")" = "PENDING" ]
echo "CODEVALID_TEST_ASSERTION_OK:seller_registration_partial_profile"

# Cleanup
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EMAIL}'); DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null
