#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="dashboard-order-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD='SellerPass123!'
BUYER_EMAIL="dashboard-order-buyer-${CASE_SUFFIX}@example.com"
BUYER_PASSWORD='BuyerPass123!'
STORE_NAME="Order Store ${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
SELLER_REGISTER="$TMP_DIR/seller.json"
BUYER_REGISTER="$TMP_DIR/buyer.json"
RESPONSE_BODY="$TMP_DIR/body.json"
STATUS_FILE="$TMP_DIR/status.txt"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE id = 'oi-123-${CASE_SUFFIX}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id = 'ord-456-${CASE_SUFFIX}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = 'product-order-${CASE_SUFFIX}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE store_name = '${STORE_NAME}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email IN ('${SELLER_EMAIL}','${BUYER_EMAIL}');" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"order bio\"}" > "$SELLER_REGISTER"
TOKEN="$(jq -r '.token' "$SELLER_REGISTER")"
SELLER_USER_ID="$(jq -r '.user.id' "$SELLER_REGISTER")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$SELLER_REGISTER")"
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';" >/dev/null
curl -sS -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${BUYER_PASSWORD}\",\"role\":\"BUYER\"}" > "$BUYER_REGISTER"
BUYER_USER_ID="$(jq -r '.user.id' "$BUYER_REGISTER")"
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at, updated_at) VALUES ('product-order-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Test Product', 'order desc', 'HOME', 7500, 50, ARRAY['https://example.com/test.jpg'], 'ACTIVE', true, NOW(), NOW());" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO orders (id, buyer_id, status, total_cents, shipping_address, created_at, updated_at) VALUES ('ord-456-${CASE_SUFFIX}', '${BUYER_USER_ID}', 'SHIPPED', 7500, 'Ship Addr', TIMESTAMP '2024-02-01 10:30:00+00', NOW());" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO order_items (id, order_id, product_id, qty, price_cents, seller_payout_cents) VALUES ('oi-123-${CASE_SUFFIX}', 'ord-456-${CASE_SUFFIX}', 'product-order-${CASE_SUFFIX}', 3, 7500, 7500);" >/dev/null

# When
curl -sS -o "$RESPONSE_BODY" -w '%{http_code}' -H "Authorization: Bearer ${TOKEN}" "$BASE_URL/seller/dashboard" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
[ "$(jq '.orders | length' "$RESPONSE_BODY")" = "1" ]
[ "$(jq -r '.orders[0].id' "$RESPONSE_BODY")" = "oi-123-${CASE_SUFFIX}" ]
[ "$(jq -r '.orders[0].order_id' "$RESPONSE_BODY")" = "ord-456-${CASE_SUFFIX}" ]
[ "$(jq -r '.orders[0].product_title' "$RESPONSE_BODY")" = "Test Product" ]
[ "$(jq -r '.orders[0].qty' "$RESPONSE_BODY")" = "3" ]
[ "$(jq -r '.orders[0].buyer_email' "$RESPONSE_BODY")" = "$BUYER_EMAIL" ]
[ "$(jq -r '.orders[0].order_status' "$RESPONSE_BODY")" = "SHIPPED" ]
[ "$(jq -r '.orders[0].seller_payout_cents' "$RESPONSE_BODY")" = "7500" ]
[ "$(jq -r '.orders[0].created_at' "$RESPONSE_BODY")" = "2024-02-01T10:30:00.000Z" ]

echo "CODEVALID_TEST_ASSERTION_OK:order_item_mapping_complete"

# Cleanup
