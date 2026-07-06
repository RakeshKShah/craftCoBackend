#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="dashboard-earn-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD='SellerPass123!'
BUYER_EMAIL="dashboard-earn-buyer-${CASE_SUFFIX}@example.com"
BUYER_PASSWORD='BuyerPass123!'
STORE_NAME="Earner Store ${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
SELLER_REGISTER="$TMP_DIR/seller.json"
BUYER_REGISTER="$TMP_DIR/buyer.json"
RESPONSE_BODY="$TMP_DIR/body.json"
STATUS_FILE="$TMP_DIR/status.txt"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE id IN ('oi1-${CASE_SUFFIX}','oi2-${CASE_SUFFIX}','oi3-${CASE_SUFFIX}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id IN ('order1-${CASE_SUFFIX}','order2-${CASE_SUFFIX}','order3-${CASE_SUFFIX}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = 'product-earn-${CASE_SUFFIX}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE store_name = '${STORE_NAME}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email IN ('${SELLER_EMAIL}','${BUYER_EMAIL}');" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"earnings bio\"}" > "$SELLER_REGISTER"
TOKEN="$(jq -r '.token' "$SELLER_REGISTER")"
SELLER_USER_ID="$(jq -r '.user.id' "$SELLER_REGISTER")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$SELLER_REGISTER")"
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';" >/dev/null
curl -sS -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${BUYER_PASSWORD}\",\"role\":\"BUYER\"}" > "$BUYER_REGISTER"
BUYER_USER_ID="$(jq -r '.user.id' "$BUYER_REGISTER")"
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at, updated_at) VALUES ('product-earn-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Earning Product ${CASE_SUFFIX}', 'earn desc', 'HOME', 3000, 20, ARRAY['https://example.com/earn.jpg'], 'ACTIVE', true, NOW(), NOW());" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO orders (id, buyer_id, status, total_cents, shipping_address, created_at, updated_at) VALUES ('order1-${CASE_SUFFIX}', '${BUYER_USER_ID}', 'COMPLETED', 1000, 'A', TIMESTAMP '2024-01-01 00:00:00+00', NOW()), ('order2-${CASE_SUFFIX}', '${BUYER_USER_ID}', 'COMPLETED', 2500, 'B', TIMESTAMP '2024-01-02 00:00:00+00', NOW()), ('order3-${CASE_SUFFIX}', '${BUYER_USER_ID}', 'COMPLETED', 1500, 'C', TIMESTAMP '2024-01-03 00:00:00+00', NOW());" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO order_items (id, order_id, product_id, qty, price_cents, seller_payout_cents) VALUES ('oi1-${CASE_SUFFIX}', 'order1-${CASE_SUFFIX}', 'product-earn-${CASE_SUFFIX}', 1, 1000, 1000), ('oi2-${CASE_SUFFIX}', 'order2-${CASE_SUFFIX}', 'product-earn-${CASE_SUFFIX}', 1, 2500, 2500), ('oi3-${CASE_SUFFIX}', 'order3-${CASE_SUFFIX}', 'product-earn-${CASE_SUFFIX}', 1, 1500, 1500);" >/dev/null

# When
curl -sS -o "$RESPONSE_BODY" -w '%{http_code}' -H "Authorization: Bearer ${TOKEN}" "$BASE_URL/seller/dashboard" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
[ "$(jq '.orders | length' "$RESPONSE_BODY")" = "3" ]
[ "$(jq -r '.total_earnings_cents' "$RESPONSE_BODY")" = "5000" ]

echo "CODEVALID_TEST_ASSERTION_OK:earnings_calculation_multiple_orders"

# Cleanup
