#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-order-${CASE_SUFFIX}@example.com"
OLD_USER_ID="user_old_${CASE_SUFFIX}"
MIDDLE_USER_ID="user_middle_${CASE_SUFFIX}"
NEW_USER_ID="user_new_${CASE_SUFFIX}"
OLD_PROFILE_ID="sp_old_${CASE_SUFFIX}"
MIDDLE_PROFILE_ID="sp_middle_${CASE_SUFFIX}"
NEW_PROFILE_ID="sp_new_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/get_sellers_orders_by_created_at_descending_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/get_sellers_orders_by_created_at_descending_${CASE_SUFFIX}.status"

cleanup() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM "SellerProfile" WHERE id IN ('${OLD_PROFILE_ID}','${MIDDLE_PROFILE_ID}','${NEW_PROFILE_ID}');
DELETE FROM "User" WHERE id IN ('${OLD_USER_ID}','${MIDDLE_USER_ID}','${NEW_USER_ID}');
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
  ('${OLD_USER_ID}', 'old-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE', '2023-06-01T00:00:00.000Z', NOW()),
  ('${MIDDLE_USER_ID}', 'middle-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE', '2023-12-15T18:30:00.000Z', NOW()),
  ('${NEW_USER_ID}', 'new-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE', '2024-01-20T12:00:00.000Z', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, "createdAt", "updatedAt") VALUES
  ('${OLD_PROFILE_ID}', '${OLD_USER_ID}', 'Old Store', 'Old profile', NOW(), NOW()),
  ('${MIDDLE_PROFILE_ID}', '${MIDDLE_USER_ID}', 'Middle Store', 'Middle profile', NOW(), NOW()),
  ('${NEW_PROFILE_ID}', '${NEW_USER_ID}', 'New Store', 'New profile', NOW(), NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "$BASE_URL/admin/sellers" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e --arg new_id "$NEW_PROFILE_ID" --arg middle_id "$MIDDLE_PROFILE_ID" --arg old_id "$OLD_PROFILE_ID" '
  type == "array" and
  .[0].id == $new_id and
  .[1].id == $middle_id and
  .[2].id == $old_id
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:get_sellers_orders_by_created_at_descending"

# Cleanup
# Executed by trap.
