#!/usr/bin/env bash
# End-to-end check against a LOCAL Supabase stack (supabase start), through the same HTTP API the
# Android app will use: sign-up, email confirmation gate, sign-in, RPC into schema api, and the
# things that must be refused. Uses throwaway example.test addresses. Never run against production.
set -uo pipefail

eval "$(supabase status -o env 2>/dev/null)"
API="${API_URL:?supabase status did not report API_URL}"
KEY="${PUBLISHABLE_KEY:-${ANON_KEY:-}}"
[ -n "$KEY" ] || { echo "no publishable/anon key from supabase status"; exit 1; }
export PGHOST=127.0.0.1 PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres

fails=0
check() {  # check <name> <condition-exit-code>
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; else echo "FAIL  $1"; fails=$((fails + 1)); fi
}
post() {   # post <path> <json> [bearer] [profile]  -> writes body to /tmp/body, prints status
    local auth=() prof=()
    [ -n "${3:-}" ] && auth=(-H "Authorization: Bearer $3")
    [ -n "${4:-}" ] && prof=(-H "Content-Profile: $4" -H "Accept-Profile: $4")
    curl -s -o /tmp/body -w '%{http_code}' -X POST "$API$1" -H "apikey: $KEY" \
         -H 'Content-Type: application/json' "${auth[@]}" "${prof[@]}" -d "$2"
}

email="e2e-$(date +%s)-$RANDOM@example.test"
pw='Correct-Horse-Battery-9'

code=$(post /auth/v1/signup "{\"email\":\"$email\",\"password\":\"short\"}")
[ "$code" != 200 ]; check "short passwords are refused (got $code)" $?

code=$(post /auth/v1/signup "{\"email\":\"$email\",\"password\":\"$pw\"}")
[ "$code" = 200 ]; check "sign-up accepted (got $code)" $?

verified=$(psql -d postgres -tAc "select email_verified from app.accounts where lower(email) = lower('$email')")
[ "$verified" = f ]; check "account created by trigger, not yet verified (got '$verified')" $?

code=$(post '/auth/v1/token?grant_type=password' "{\"email\":\"$email\",\"password\":\"$pw\"}")
[ "$code" != 200 ]; check "sign-in refused before email confirmation (got $code)" $?

psql -d postgres -q -c "update auth.users set email_confirmed_at = now() where lower(email) = lower('$email')"
code=$(post '/auth/v1/token?grant_type=password' "{\"email\":\"$email\",\"password\":\"$pw\"}")
token=$(jq -r '.access_token // empty' /tmp/body)
[ "$code" = 200 ] && [ -n "$token" ]; check "sign-in after confirmation (got $code)" $?

code=$(post /rest/v1/rpc/my_status '{}' "$token" api)
ok=$(jq -r '.[0].email_verified // empty' /tmp/body 2>/dev/null)
[ "$code" = 200 ] && [ "$ok" = true ]; check "RPC api.my_status works with the user's JWT (got $code, verified=$ok)" $?

code=$(post /rest/v1/rpc/my_status '{}' "" api)
[ "$code" != 200 ]; check "RPC without a user JWT is refused (got $code)" $?

code=$(post /rest/v1/rpc/directory_search '{"p_query":"ab"}' "$token" api)
[ "$code" != 200 ]; check "directory refused for a non-member (got $code)" $?

code=$(post /rest/v1/rpc/grant_role "{\"p_account\":\"00000000-0000-0000-0000-000000000000\",\"p_role\":\"global_admin\",\"p_chapter\":null}" "$token" api)
[ "$code" != 200 ]; check "ordinary user cannot grant roles (got $code)" $?

code=$(curl -s -o /tmp/body -w '%{http_code}' "$API/rest/v1/accounts" -H "apikey: $KEY" \
       -H "Authorization: Bearer $token" -H 'Accept-Profile: app')
[ "$code" != 200 ]; check "internal schema app is not exposed over HTTP (got $code)" $?

code=$(curl -s -o /tmp/body -w '%{http_code}' -X POST \
       "$API/storage/v1/object/event-photos/events/00000000-0000-0000-0000-000000000001/x.webp" \
       -H "apikey: $KEY" -H "Authorization: Bearer $token" -H 'Content-Type: image/webp' --data-binary 'RIFF0000WEBP')
[ "$code" != 200 ]; check "ordinary user cannot upload event photos (got $code)" $?

psql -d postgres -q -c "delete from auth.users where lower(email) = lower('$email')" >/dev/null
echo "$fails failure(s)"
[ "$fails" -eq 0 ]
