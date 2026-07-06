#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="user_approve_${CASE_SUFFIX}"
SELLER_ID="seller_approve_${CASE_SUFFIX}"
PRODUCT_ID="product_approve_${CASE_SUFFIX}"
ADMIN_EMAIL="admin_approve_${CASE_SUFFIX}@example.com"
SELLER_EMAIL="seller_approve_${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/approve_new_seller_success_${CASE_SUFFIX}.json"
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
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'Pending Shop ${CASE_SUFFIX}', 'Pending seller bio ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Pending Product ${CASE_SUFFIX}', 'Product before approval', 'general'
