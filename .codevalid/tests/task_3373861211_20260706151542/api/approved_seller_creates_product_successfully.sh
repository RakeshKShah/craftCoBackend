#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="approved-seller-${CASE_SUFFIX}@example.com"
PASSWORD='SellerPass123!'
TOKEN_FILE="/tmp/approved_seller_creates_product_successfully_${CASE_SUFFIX}_register.json"
REGISTER_STATUS_FILE="/tmp/approved_seller_creates_product_successfully_${CASE_SUFFIX}_register.status"
RESPONSE_FILE="/tmp/approved_seller_creates_product_successfully_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/approved_seller_creates_product_successfully_${CASE_SUFFIX}.status"
TITLE="Handmade Ceramic Mug ${CASE_SUFFIX}"
cleanup() {
  PRODUCT_ID="$(jq -r '.id // empty' "$RESPONSE_FILE" 2>/dev/null || true)"
  SELLER_ID="$(jq -r '.user.sellerProfile.id // empty' "$TOKEN_FILE" 2>/dev/null || true)"
  USER_ID="$(jq -r '.user.id // empty' "$TOKEN_FILE" 2>/dev/null || true)"
  if [ -n "$PRODUCT_ID" ]; then
    psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
  fi
  if [ -n "$SELLER_ID" ]; then
    psql "$DATABASE_URL" -c "DELETE FROM products WHERE seller_id = '${SELLER_ID}';" >/dev/null 2>&1 || true
    psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '${SELLER_ID}';" >/dev/null 2>&1 || true
  fi
  if [ -n "$USER_ID" ]; then
    psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${USER_ID}';" >/dev/null 2>&1 || true
  fi
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$TOKEN_FILE" "$REGISTER_STATUS_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup EXIT

# Given
curl -sS -o "$TOKEN_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Approved Store ${CASE_SUFFIX}\",\"bio\":\"Approved seller bio ${CASE_SUFFIX}\"}" \
  > "$REGISTER_STATUS_FILE"
[ "$(cat "$REGISTER_STATUS_FILE")" = "201" ]
TOKEN="$(jq -r '.token' "$TOKEN_FILE")"
USER_ID="$(jq -r '.user.id' "$TOKEN_FILE")"
SELLER_ID="$(jq -r '.user.sellerProfile.id' "$TOKEN_FILE")"
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${USER_ID}';" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"title\":\"${TITLE}\",\"description\":\"A beautiful handcrafted mug\",\"category\":\"HOME_GOODS\",\"price_cents\":2999,\"stock_qty\":10,\"photos\":[\"https://example.com/mug1.jpg\"]}" \
  > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "201" ]
jq -e --arg sellerId "$SELLER_ID" '.sellerId == $sellerId' "$RESPONSE_FILE" >/dev/null
jq -e --arg title "$TITLE" '.title == $title' "$RESPONSE_FILE" >/dev/null
jq -e '.status == "ACTIVE"' "$RESPONSE_FILE" >/dev/null
jq -e '.visible == true' "$RESPONSE_FILE" >/dev/null
jq -e '.id | type == "string" and length > 0' "$RESPONSE_FILE" >/dev/null
printf 'CODEVALID_TEST_ASSERTION_OK:approved_seller_creates_product_successfully\n'

# Cleanup
PRODUCT_ID="$(jq -r '.id' "$RESPONSE_FILE")"
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null
