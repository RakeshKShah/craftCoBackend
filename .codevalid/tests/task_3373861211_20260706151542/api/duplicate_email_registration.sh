#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="existing.user.${CASE_SUFFIX}@test.com"
RESPONSE_FILE="/tmp/duplicate_email_registration_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/duplicate_email_registration_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EMAIL}'); DELETE FROM users WHERE email = '${EMAIL}'; INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('dup${CASE_SUFFIX}', '${EMAIL}', 'already-hashed', 'BUYER', 'ACTIVE', NOW());" >/dev/null

# When
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"NewPass123!\",\"role\":\"SELLER\",\"storeName\":\"New Store ${CASE_SUFFIX}\"}")"
printf '%s' "$HTTP_STATUS" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
[ "$(jq -r '.error' "$RESPONSE_FILE")" = "Email already registered" ]
echo "CODEVALID_TEST_ASSERTION_OK:duplicate_email_registration"

# Cleanup
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EMAIL}'); DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null
