#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-${CASE_SUFFIX}@example.com"
SELLER1_USER_ID="user_a_${CASE_SUFFIX}"
SELLER1_PROFILE_ID="sp_a_${CASE_SUFFIX}"
SELLER2_USER_ID="user_b_${CASE_SUFFIX}"
SELLER2_PROFILE_ID="sp_b_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/get_sellers_returns_all_sellers_for_admin_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/get_sellers_returns_all_sellers_for_admin_${CASE_SUFFIX}.status"

cleanup() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM "Product" WHERE "sellerId" IN ('${SELLER1_PROFILE_ID}','${SELLER2_PROFILE_ID}');
DELETE FROM "SellerProfile" WHERE id IN ('${SELLER1_PROFILE_ID}','${SELLER2_PROFILE_ID}');
DELETE FROM "User" WHERE id IN ('${SELLER1_USER_ID}','${SELLER2_USER_ID}');
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
  ('${SELLER1_USER_ID}', 'seller1-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE', '2024-01-15T10:00:00.000Z', NOW()),
  ('${SELLER2_USER_ID}', 'seller2-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'PENDING', '2024-01-16T14:30:00.000Z', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, "createdAt", "updatedAt") VALUES
  ('${SELLER1_PROFILE_ID}', '${SELLER1_USER_ID}', 'Tech Gadgets', 'Quality electronics seller', NOW(), NOW()),
  ('${SELLER2_PROFILE_ID}', '${SELLER2_USER_ID}', 'Fashion Hub', 'Trendy clothing and accessories', NOW(), NOW());
INSERT INTO "Product" (id, "sellerId", title, description, category, "priceCents", "stockQty", photos, status, visible, "createdAt", "updatedAt") VALUES
  ('prod1_${CASE_SUFFIX}', '${SELLER1_PROFILE_ID}', 'Item 1', 'Seed product', 'ELECTRONICS', 1000, 3, ARRAY[]::TEXT[], 'ACTIVE', true, NOW(), NOW()),
  ('prod2_${CASE_SUFFIX}', '${SELLER1_PROFILE_ID}', 'Item 2', 'Seed product', 'ELECTRONICS', 1000, 3, ARRAY[]::TEXT[], 'ACTIVE', true, NOW(), NOW()),
  ('prod3_${CASE_SUFFIX}', '${SELLER1_PROFILE_ID}', 'Item 3', 'Seed product', 'ELECTRONICS', 1000, 3, ARRAY[]::TEXT[], 'ACTIVE', true, NOW(), NOW()),
  ('prod4_${CASE_SUFFIX}', '${SELLER1_PROFILE_ID}', 'Item 4', 'Seed product', 'ELECTRONICS', 1000, 3, ARRAY[]::TEXT[], 'ACTIVE', true, NOW(), NOW()),
  ('prod5_${CASE_SUFFIX}', '${SELLER1_PROFILE_ID}', 'Item 5', 'Seed product', 'ELECTRONICS', 1000, 3, ARRAY[]::TEXT[], 'ACTIVE', true, NOW(), NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "$BASE_URL/admin/sellers" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e --arg id1 "$SELLER1_PROFILE_ID" --arg id2 "$SELLER2_PROFILE_ID" --arg u1 "$SELLER1_USER_ID" --arg u2 "$SELLER2_USER_ID" --arg e1 "seller1-${CASE_SUFFIX}@example.com" --arg e2 "seller2-${CASE_SUFFIX}@example.com" '
  type == "array" and
  length >= 2 and
  .[0].id == $id2 and
  .[0].user_id == $u2 and
  .[0].email == $e2 and
  .[0].store_name == "Fashion Hub" and
  .[0].bio == "Trendy clothing and accessories" and
  .[0].status == "PENDING" and
  .[0].product_count == 0 and
  any(.[]; .id == $id1 and .user_id == $u1 and .email == $e1 and .store_name == "Tech Gadgets" and .bio == "Quality electronics seller" and .status == "ACTIVE" and .product_count == 5)
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:get_sellers_returns_all_sellers_for_admin"

# Cleanup
# Executed by trap.
