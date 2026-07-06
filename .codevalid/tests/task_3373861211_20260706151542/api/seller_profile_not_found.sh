#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_EMAIL="dashboard-noprofile-${CASE_SUFFIX}@example.com"
BUYER_PASSWORD='BuyerPass123!'
TMP_DIR="$(mktemp -d)"
REGISTER_BODY="$TMP_DIR/register.json"
RESPONSE_BODY="$TMP_DIR/body.json"
STATUS_FILE="$TMP_DIR/status.txt"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${BUYER_EMAIL}';" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${BUYER_PASSWORD}\",\"role\":\"BUYER\"}" > "$REGISTER_BODY"
TOKEN="$(jq -r '.token' "$REGISTER_BODY")"
USER_ID="$(jq -r '.user.id' "$REGISTER_BODY")"
psql "$DATABASE_URL" -c "UPDATE users SET role = 'SELLER', status = 'ACTIVE' WHERE id = '${USER_ID}';" >/dev/null

# When
curl -sS -o "$RESPONSE_BODY" -w '%{http_code}' -H "Authorization: Bearer ${TOKEN}" "$BASE_URL/seller/dashboard" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "404" ]
grep -F 'Seller profile not found' "$RESPONSE_BODY" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_profile_not_found"

# Cleanup
