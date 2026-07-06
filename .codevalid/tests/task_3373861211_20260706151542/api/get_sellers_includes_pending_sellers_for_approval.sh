#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-pending-${CASE_SUFFIX}@example.com"
SELLER_USER_ID="user_pending_${CASE_SUFFIX}"
SELLER_PROFILE_ID="sp_pending_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/get_sellers_includes_pending_sellers_for_approval_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/get_sellers_includes_pending_sellers_for_approval_${CASE_SUFFIX}.status"

cleanup() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM "SellerProfile" WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM "User" WHERE id = '${SELLER_USER_ID}';
DELETE FROM "User" WHERE email = '${ADMIN_EMAIL}';
SQL
}
trap cleanup EXIT

# Given
ADMIN_TOKEN="$(curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"Password123!\",\"role\":\"ADMIN\"}" | jq -r '.token')"
[ -n "$ADMIN_TOKEN" ]
[ "$ADMIN_TOKEN" != "null" ]

psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO "User" (id, email, "passwordHash", role, status, "createdAt", "updatedAt") VALUES
  ('${SELLER_USER_ID}', 'newapplicant-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'PENDING', '2024-01-18T09:00:00.000Z', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, "createdAt", "updatedAt") VALUES
  ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'New Crafts Store', 'Handmade artisan products', NOW(), NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "$BASE_URL/admin/sellers" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e --arg id "$SELLER_PROFILE_ID" '
  any(.[]; .id == $id and .status == "PENDING" and .store_name == "New Crafts Store" and .bio == "Handmade artisan products" and .product_count == 0)
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:get_sellers_includes_pending_sellers_for_approval"

# Cleanup
# Executed by trap.
