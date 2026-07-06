#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-profile-${CASE_SUFFIX}@example.com"
SELLER_USER_ID="user_profile_${CASE_SUFFIX}"
SELLER_PROFILE_ID="sp_profile_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/get_sellers_complete_store_profile_data_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/get_sellers_complete_store_profile_data_${CASE_SUFFIX}.status"

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
  ('${SELLER_USER_ID}', 'bakery-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE', NOW(), NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, "createdAt", "updatedAt") VALUES
  ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Artisan Bakery', 'Freshly baked goods delivered daily. Family-owned since 2020.', NOW(), NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "$BASE_URL/admin/sellers" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e --arg id "$SELLER_PROFILE_ID" '
  any(.[]; .id == $id and .store_name == "Artisan Bakery" and .bio == "Freshly baked goods delivered daily. Family-owned since 2020.")
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:get_sellers_complete_store_profile_data"

# Cleanup
# Executed by trap.
