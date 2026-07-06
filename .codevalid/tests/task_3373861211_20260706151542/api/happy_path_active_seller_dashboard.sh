#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="dashboard-happy-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD='SellerPass123!'
BUYER_EMAIL="dashboard-buyer-${CASE_SUFFIX}@example.com"
BUYER_PASSWORD='BuyerPass123!'
STORE_NAME="Artisan Crafts ${CASE_SUFFIX}"
BIO='Handmade goods'
PRODUCT_ONE_TITLE="Ceramic Mug ${CASE_SUFFIX}"
PRODUCT_TWO_TITLE="Wooden Bowl ${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
SELLER_REGISTER_BODY="$TMP_DIR/seller_register.json"
BUYER_REGISTER_BODY="$TMP_DIR/buyer_register.json"
DASHBOARD_BODY="$TMP_DIR/dashboard.json"
STATUS_FILE="$TMP_DIR/status.txt"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE id IN ('oi-${CASE_SUFFIX}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id IN ('order-${CASE_SUFFIX}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id IN ('product-1-${CASE_SUFFIX}','product-2-${CASE_SUFFIX}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE store_name = '${STORE_NAME}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email IN ('${SELLER_EMAIL}','${BUYER_EMAIL}');" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"${BIO}\"}" \
  > "$SELLER_REGISTER_BODY"
SELLER_TOKEN="$(jq -r '.token' "$SELLER_REGISTER_BODY")"
SELLER_USER_ID="$(jq -r '.user.id' "$SELLER_REGISTER_BODY")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$SELLER_REGISTER_BODY")"
[ "$(jq -r '.user.status' "$SELLER_REGISTER_BODY")" = "PENDING" ]

curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${BUYER_PASSWORD}\",\"role\":\"BUYER\"}" \
  > "$BUYER_REGISTER_BODY"
BUYER_USER_ID="$(jq -r '.user.id' "$BUYER_REGISTER_BODY")"

psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at, updated_at) VALUES ('product-1-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', '${PRODUCT_ONE_TITLE}', 'Mug description', 'HOME', 2500, 10, ARRAY['https://example.com/mug.jpg'], 'ACTIVE', true, TIMESTAMP '2024-01-15 00:00:00+00', NOW()), ('product-2-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', '${PRODUCT_TWO_TITLE}', 'Bowl description', 'HOME', 3500, 7, ARRAY['https://example.com/bowl.jpg'], 'ACTIVE', true, TIMESTAMP '2024-01-10 00:00:00+00', NOW());" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO orders (id, buyer_id, status, total_cents, shipping_address, created_at, updated_at) VALUES ('order-${CASE_SUFFIX}', '${BUYER_USER_ID}', 'COMPLETED', 5000, '123 Buyer St', TIMESTAMP '2024-01-20 00:00:00+00', NOW());" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO order_items (id, order_id, product_id, qty, price_cents, seller_payout_cents) VALUES ('oi-${CASE_SUFFIX}', 'order-${CASE_SUFFIX}', 'product-1-${CASE_SUFFIX}', 2, 2500, 5000);" >/dev/null

# When
curl -sS -o "$DASHBOARD_BODY" -w '%{http_code}' \
  -H "Authorization: Bearer ${SELLER_TOKEN}" \
  "$BASE_URL/seller/dashboard" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
[ "$(jq -r '.store_name' "$DASHBOARD_BODY")" = "$STORE_NAME" ]
[ "$(jq -r '.bio' "$DASHBOARD_BODY")" = "$BIO" ]
[ "$(jq -r '.status' "$DASHBOARD_BODY")" = "ACTIVE" ]
[ "$(jq '.products | length' "$DASHBOARD_BODY")" = "2" ]
[ "$(jq -r '.products[0].title' "$DASHBOARD_BODY")" = "$PRODUCT_ONE_TITLE" ]
[ "$(jq -r '.products[1].title' "$DASHBOARD_BODY")" = "$PRODUCT_TWO_TITLE" ]
[ "$(jq '.orders | length' "$DASHBOARD_BODY")" = "1" ]
[ "$(jq -r '.orders[0].qty' "$DASHBOARD_BODY")" = "2" ]
[ "$(jq -r '.orders[0].buyer_email' "$DASHBOARD_BODY")" = "$BUYER_EMAIL" ]
[ "$(jq -r '.orders[0].seller_payout_cents' "$DASHBOARD_BODY")" = "5000" ]
[ "$(jq -r '.total_earnings_cents' "$DASHBOARD_BODY")" = "5000" ]

echo "CODEVALID_TEST_ASSERTION_OK:happy_path_active_seller_dashboard"

# Cleanup
