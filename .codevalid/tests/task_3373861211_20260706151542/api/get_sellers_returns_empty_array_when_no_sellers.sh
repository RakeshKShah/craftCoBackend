#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-empty-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/get_sellers_returns_empty_array_when_no_sellers_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/get_sellers_returns_empty_array_when_no_sellers_${CASE_SUFFIX}.status"

cleanup() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM "User" WHERE email = '${ADMIN_EMAIL}';
SQL
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM "Product";
DELETE FROM "SellerProfile";
DELETE FROM "User" WHERE role = 'SELLER';
SQL

ADMIN_TOKEN="$(curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"Password123!\",\"role\":\"ADMIN\"}" | jq -r '.token')"
[ -n "$ADMIN_TOKEN" ]
[ "$ADMIN_TOKEN" != "null" ]

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "$BASE_URL/admin/sellers" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array" and length == 0' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:get_sellers_returns_empty_array_when_no_sellers"

# Cleanup
# Executed by trap.
