#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="user_malformed_${CASE_SUFFIX}"
SELLER_ID="seller_malformed_${CASE_SUFFIX}"
ADMIN_EMAIL="admin_malformed_${CASE_SUFFIX}@example.com"
SELLER_EMAIL="seller_malformed_${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/malformed_request_body_${CASE_SUFFIX}.json"
STATUS_CODE=""
cleanup_files() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given
ADMIN_TOKEN="$(curl -sS -X POST "$BASE_URL/register" \n  -H 'Content-Type: application/json' \n  -d "{"email":"${ADMIN_EMAIL}","password":"Password123!","role":"ADMIN"}" \n  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
[ -n "$ADMIN_TOKEN" ]
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', '${SELLER_EMAIL}', 'seed-hash', 'SELLER', 'PENDING', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'Malformed Shop ${CASE_SUFFIX}', 'Malformed body bio ${CASE_SUFFIX}');
SQL

# When
STATUS_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \n  -X PUT "$BASE_URL/sellers/${SELLER_ID}" \n  -H 'Content-Type: application/json' \n  -H "Authorization: Bearer ${ADMIN_TOKEN}" \n  -d '{"status":["ACTIVE"]}')"

# Then
[ "$STATUS_CODE" = "400" ]
grep -F '"error":' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id = '${SELLER_USER_ID}';")"
[ "$DB_STATUS" = "PENDING" ]
echo "CODEVALID_TEST_ASSERTION_OK:malformed_request_body"

# Cleanup
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM seller_profiles WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}' OR email = '${ADMIN_EMAIL}';
SQL
