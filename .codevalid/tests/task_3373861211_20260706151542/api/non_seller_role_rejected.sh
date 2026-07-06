#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="buyer-${CASE_SUFFIX}@example.com"
PASSWORD='BuyerPass123!'
TOKEN_FILE="/tmp/non_seller_role_rejected_${CASE_SUFFIX}_register.json"
REGISTER_STATUS_FILE="/tmp/non_seller_role_rejected_${CASE_SUFFIX}_register.status"
RESPONSE_FILE="/tmp/non_seller_role_rejected_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/non_seller_role_rejected_${CASE_SUFFIX}.status"
cleanup() {
  USER_ID="$(jq -r '.user.id // empty' "$TOKEN_FILE" 2>/dev/null || true)"
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
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"BUYER\"}" \
  > "$REGISTER_STATUS_FILE"
[ "$(cat "$REGISTER_STATUS_FILE")" = "201" ]
TOKEN="$(jq -r '.token' "$TOKEN_FILE")"
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data '{"title":"Test Product","description":"Test","category":"ELECTRONICS","price_cents":1000,"stock_qty":5,"photos":[]}' \
  > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "403" ]
jq -e '.error == "Seller access required"' "$RESPONSE_FILE" >/dev/null
printf 'CODEVALID_TEST_ASSERTION_OK:non_seller_role_rejected\n'

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
