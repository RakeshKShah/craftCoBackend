#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-suspended-${CASE_SUFFIX}@example.com"
SELLER_USER_ID="user_suspended_${CASE_SUFFIX}"
SELLER_PROFILE_ID="sp_suspended_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/get_sellers_includes_suspended_sellers_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/get_sellers_includes_suspended_sellers_${CASE_SUFFIX}.status"

cleanup() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM "Product" WHERE "sellerId" = '${SELLER_PROFILE_ID}';
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
  ('${SELLER_USER_ID}', 'suspended-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'SUSPENDED', '2024-01-10T08:00:00.000Z', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, "createdAt", "updatedAt") VALUES
  ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Banned Electronics', 'Permanently suspended seller', NOW(), NOW());
INSERT INTO "Product" (id, "sellerId", title, description, category, "priceCents", "stockQty", photos, status, visible, "createdAt", "updatedAt")
SELECT 'suspended_' || gs::text || '_${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Hidden Product ' || gs::text, 'Seed product', 'ELECTRONICS', 2500, 1, ARRAY[]::TEXT[], 'ACTIVE', false, NOW(), NOW()
FROM generate_series(1, 10) AS gs;
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "$BASE_URL/admin/sellers" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e --arg id "$SELLER_PROFILE_ID" '
  any(.[]; .id == $id and .status == "SUSPENDED" and .store_name == "Banned Electronics" and .bio == "Permanently suspended seller" and .product_count == 10)
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:get_sellers_includes_suspended_sellers"

# Cleanup
# Executed by trap.
