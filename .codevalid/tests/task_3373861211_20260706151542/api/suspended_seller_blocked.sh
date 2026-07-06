#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="dashboard-suspended-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD='SellerPass123!'
STORE_NAME="Suspended Store ${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
REGISTER_BODY="$TMP_DIR/register.json"
RESPONSE_BODY="$TMP_DIR/body.json"
STATUS_FILE="$TMP_DIR/status.txt"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE store_name = '${STORE_NAME}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${SELLER_EMAIL}';" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"suspended bio\"}" > "$REGISTER_BODY"
TOKEN="$(jq -r '.token' "$REGISTER_BODY")"
USER_ID="$(jq -r '.user.id' "$REGISTER_BODY")"
psql "$DATABASE_URL" -c "UPDATE users SET status = 'SUSPENDED' WHERE id = '${USER_ID}';" >/dev/null

# When
curl -sS -o "$RESPONSE_BODY" -w '%{http_code}' -H "Authorization: Bearer ${TOKEN}" "$BASE_URL/seller/dashboard" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "403" ]
grep -E 'suspended|active|approved|Seller' "$RESPONSE_BODY" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:suspended_seller_blocked"

# Cleanup
