#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="hash.test.${CASE_SUFFIX}@test.com"
PASSWORD="PlainPassword123!"
RESPONSE_FILE="/tmp/password_is_hashed_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/password_is_hashed_${CASE_SUFFIX}.status"
HASH_FILE="/tmp/password_is_hashed_${CASE_SUFFIX}.txt"
COMPARE_FILE="/tmp/password_is_hashed_${CASE_SUFFIX}.compare"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$HASH_FILE" "$COMPARE_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EMAIL}'); DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null

# When
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\"}")"
printf '%s' "$HTTP_STATUS" > "$STATUS_FILE"
psql "$DATABASE_URL" -At -c "SELECT password_hash FROM users WHERE email = '${EMAIL}';" > "$HASH_FILE"
HASH_VALUE="$(tr -d '\n' < "$HASH_FILE")"
node -e 'const bcrypt=require("bcryptjs"); const plain=process.argv[1]; const hash=process.argv[2]; bcrypt.compare(plain, hash).then(v=>{process.stdout.write(v ? "true" : "false")}).catch(()=>process.exit(1));' "$PASSWORD" "$HASH_VALUE" > "$COMPARE_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
[ -n "$HASH_VALUE" ]
[ "$HASH_VALUE" != "$PASSWORD" ]
printf '%s' "$HASH_VALUE" | grep -E '^\$2[aby]\$' >/dev/null
[ "$(cat "$COMPARE_FILE")" = "true" ]
echo "CODEVALID_TEST_ASSERTION_OK:password_is_hashed"

# Cleanup
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EMAIL}'); DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null
