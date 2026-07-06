#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="dashboard-busy-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD='SellerPass123!'
BUYER_EMAIL="dashboard-busy-buyer-${CASE_SUFFIX}@example.com"
BUYER_PASSWORD='BuyerPass123!'
STORE_NAME="Busy Store ${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
SELLER_REGISTER="$TMP_DIR/seller.json"
BUYER_REGISTER="$TMP_DIR/buyer.json"
RESPONSE_BODY="$TMP_DIR/body.json"
STATUS_FILE="$TMP_DIR/status.txt"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE id LIKE 'busy-oi-%-${CASE_SUFFIX}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id LIKE 'busy-order-%-${CASE_SUFFIX}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = 'busy-product-${CASE_SUFFIX}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE store_name = '${STORE_NAME}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email IN ('${SELLER_EMAIL}','${BUYER_EMAIL}');" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"busy bio\"}" > "$SELLER_REGISTER"
TOKEN="$(jq -r '.token' "$SELLER_REGISTER")"
SELLER_USER_ID="$(jq -r '.user.id' "$SELLER_REGISTER")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$SELLER_REGISTER")"
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';" >/dev/null
curl -sS -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${BUYER_PASSWORD}\",\"role\":\"BUYER\"}" > "$BUYER_REGISTER"
BUYER_USER_ID="$(jq -r '.user.id' "$BUYER_REGISTER")"
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at, updated_at) VALUES ('busy-product-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Busy Product ${CASE_SUFFIX}', 'busy desc', 'HOME', 1999, 100, ARRAY['https://example.com/busy.jpg'], 'ACTIVE', true, NOW(), NOW());" >/dev/null
i=1
while [ "$i" -le 75 ]; do
  ORDER_ID="busy-order-${i}-${CASE_SUFFIX}"
  OI_ID="busy-oi-${i}-${CASE_SUFFIX}"
  DAY=$(( ((i - 1) % 28) + 1 ))
  MINUTE=$(( i % 60 ))
  TS="2024-03-$(printf '%02d' "$DAY") 10:$(printf '%02d' "$MINUTE"):00+00"
  psql "$DATABASE_URL" -c "INSERT INTO orders (id, buyer_id, status, total_cents, shipping_address, created_at, updated_at) VALUES ('${ORDER_ID}', '${BUYER_USER_ID}', 'COMPLETED', 1999, 'Busy Addr ${i}', TIMESTAMP '${TS}', NOW());" >/dev/null
  psql "$DATABASE_URL" -c "INSERT INTO order_items (id, order_id, product_id, qty, price_cents, seller_payout_cents) VALUES ('${OI_ID}', '${ORDER_ID}', 'busy-product-${CASE_SUFFIX}', 1, 1999, ${i});" >/dev/null
  i=$((i + 1))
done

# When
curl -sS -o "$RESPONSE_BODY" -w '%{http_code}' -H "Authorization: Bearer ${TOKEN}" "$BASE_URL/seller/dashboard" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
[ "$(jq '.orders | length' "$RESPONSE_BODY")" = "50" ]
FIRST_CREATED_AT="$(jq -r '.orders[0].created_at' "$RESPONSE_BODY")"
LAST_CREATED_AT="$(jq -r '.orders[49].created_at' "$RESPONSE_BODY")"
[ "$FIRST_CREATED_AT" != "null" ]
[ "$LAST_CREATED_AT" != "null" ]
[ "$FIRST_CREATED_AT" \> "$LAST_CREATED_AT" ] || [ "$FIRST_CREATED_AT" = "$LAST_CREATED_AT" ]

echo "CODEVALID_TEST_ASSERTION_OK:orders_limited_to_fifty"

# Cleanup
