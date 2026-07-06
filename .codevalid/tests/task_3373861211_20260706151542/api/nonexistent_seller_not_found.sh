#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
NONEXISTENT_SELLER_ID="seller_not_found_${CASE_SUFFIX}"
ADMIN_EMAIL="admin_not_found_${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/nonexistent_seller_not_found_${CASE_SUFFIX}.json"
STATUS_CODE=""
cleanup_files() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given
ADMIN_TOKEN="$(curl -sS -X POST "$BASE_URL/register" \n  -H 'Content-Type: application/json' \n  -d "{"email":"${ADMIN_EMAIL}","password":"Password123!","role":"ADMIN"}" \n  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
[ -n "$ADMIN_TOKEN" ]
EXISTING_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM seller_profiles WHERE id = '${NONEXISTENT_SELLER_ID}';")"
[ "$EXISTING_COUNT" = "0" ]

# When
STATUS_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \n  -X PUT "$BASE_URL/sellers/${NONEXISTENT_SELLER_ID}" \n  -H 'Content-Type: application/json' \n  -H "Authorization: Bearer ${ADMIN_TOKEN}" \n  -d '{"status":"ACTIVE"}')"

# Then
[ "$STATUS_CODE" = "404" ]
grep -F '"error":"Seller not found"' "$RESPONSE_FILE" >/dev/null
echo "CODEVALID_TEST_ASSERTION_OK:nonexistent_seller_not_found"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${ADMIN_EMAIL}';" >/dev/null
