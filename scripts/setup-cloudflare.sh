#!/usr/bin/env bash
# Provision Cloudflare Access for Cursor Pocket (API-driven).
# Run locally with your Cloudflare API token — not from CI without secrets.
#
# Usage:
#   export CLOUDFLARE_API_TOKEN="..."
#   export POCKET_ALLOWED_EMAIL="you@example.com"   # required
#   export CLOUDFLARE_ACCOUNT_ID="..."              # optional (auto-detected)
#   export POCKET_DOMAIN="cursor-pocket.pages.dev"  # optional
#   ./scripts/setup-cloudflare.sh
set -euo pipefail

API="https://api.cloudflare.com/client/v4"
DOMAIN="${POCKET_DOMAIN:-cursor-pocket.pages.dev}"
APP_NAME="${POCKET_APP_NAME:-Cursor Pocket}"
REPO="${GITHUB_REPO:-hourdays/cursor-pocket}"

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  echo "ERROR: Set CLOUDFLARE_API_TOKEN (Account → Cloudflare Pages → Edit + Zero Trust → Edit)"
  exit 1
fi

if [[ -z "${POCKET_ALLOWED_EMAIL:-}" ]]; then
  echo "ERROR: Set POCKET_ALLOWED_EMAIL to your Cursor account email"
  exit 1
fi

cf() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -sS -X "$method" "${API}${path}" \
      -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$data"
  else
    curl -sS -X "$method" "${API}${path}" \
      -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
      -H "Content-Type: application/json"
  fi
}

json_success() {
  python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('success') else 1)"
}

require_success() {
  local response="$1"
  local message="$2"
  if ! printf '%s' "$response" | json_success; then
    echo "ERROR: ${message}"
    printf '%s\n' "$response" | python3 -m json.tool 2>/dev/null || printf '%s\n' "$response"
    exit 1
  fi
}

access_policy_body() {
  python3 -c "
import json, sys
email = sys.argv[1]
print(json.dumps({
  'name': 'Only allowed email',
  'decision': 'allow',
  'precedence': 1,
  'include': [{'email': {'email': email}}],
}))
" "$POCKET_ALLOWED_EMAIL"
}

policy_ids_from_response() {
  python3 -c "
import json, sys
d = json.load(sys.stdin)
for policy in d.get('result') or []:
    policy_id = policy.get('id')
    if policy_id:
        print(policy_id)
"
}

total_pages_from_response() {
  python3 -c "
import json, sys
d = json.load(sys.stdin)
info = d.get('result_info') or {}
print(info.get('total_pages') or 1)
"
}

verify_single_email_policy() {
  python3 -c "
import json, sys
email = sys.argv[1]
d = json.load(sys.stdin)
policies = d.get('result') or []
info = d.get('result_info') or {}
expected_include = [{'email': {'email': email}}]
ok = (
    len(policies) == 1 and
    info.get('total_count', 1) == 1 and
    policies[0].get('decision') == 'allow' and
    policies[0].get('include') == expected_include and
    not policies[0].get('exclude') and
    not policies[0].get('require')
)
if not ok:
    raise SystemExit(1)
" "$@"
}

replace_access_policies() {
  local app_id="$1"
  local policy_ids=""
  local page=1
  local total_pages=1

  echo "==> Replacing Access policies with single email allow rule…"
  while (( page <= total_pages )); do
    policies="$(cf GET "${ACCOUNT_PATH}/access/apps/${app_id}/policies?per_page=50&page=${page}")"
    require_success "$policies" "Failed to list Access policies"
    total_pages="$(printf '%s' "$policies" | total_pages_from_response)"
    policy_ids+="${policy_ids:+$'\n'}$(printf '%s' "$policies" | policy_ids_from_response)"
    page=$((page + 1))
  done

  while IFS= read -r policy_id; do
    [[ -z "$policy_id" ]] && continue
    delete_result="$(cf DELETE "${ACCOUNT_PATH}/access/apps/${app_id}/policies/${policy_id}")"
    require_success "$delete_result" "Failed to delete existing Access policy ${policy_id}; check the Zero Trust dashboard before trusting this app"
  done <<< "$policy_ids"

  policy_result="$(cf POST "${ACCOUNT_PATH}/access/apps/${app_id}/policies" "$(access_policy_body)")"
  require_success "$policy_result" "Failed to create email-only Access policy"

  policies="$(cf GET "${ACCOUNT_PATH}/access/apps/${app_id}/policies?per_page=50&page=1")"
  require_success "$policies" "Failed to verify Access policies"
  if ! printf '%s' "$policies" | verify_single_email_policy "$POCKET_ALLOWED_EMAIL"; then
    echo "ERROR: Access app still has policies other than the single allowed email policy."
    printf '%s\n' "$policies" | python3 -m json.tool 2>/dev/null || printf '%s\n' "$policies"
    exit 1
  fi
  echo "    Policies replaced"
}

echo "==> Verifying Cloudflare API token…"
verify="$(cf GET "/user/tokens/verify")"
require_success "$verify" "Invalid CLOUDFLARE_API_TOKEN"
echo "    Token OK"

if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  echo "==> Detecting account ID…"
  accounts="$(cf GET "/accounts?per_page=5")"
  require_success "$accounts" "Failed to list Cloudflare accounts"
  CLOUDFLARE_ACCOUNT_ID="$(printf '%s' "$accounts" | python3 -c "
import sys, json
d = json.load(sys.stdin)
items = d.get('result') or []
if not items:
    raise SystemExit('no accounts')
print(items[0]['id'])
")"
  echo "    Account: ${CLOUDFLARE_ACCOUNT_ID}"
fi

ACCOUNT_PATH="/accounts/${CLOUDFLARE_ACCOUNT_ID}"

echo "==> Looking for existing Access app on ${DOMAIN}…"
apps="$(cf GET "${ACCOUNT_PATH}/access/apps?per_page=50")"
require_success "$apps" "Failed to list Access applications"
APP_ID="$(printf '%s' "$apps" | python3 -c "
import sys, json
domain = sys.argv[1]
d = json.load(sys.stdin)
for app in d.get('result') or []:
    if app.get('domain') == domain:
        print(app['id'])
        break
" "$DOMAIN")"

if [[ -z "${APP_ID}" ]]; then
  echo "==> Creating Access application…"
  create_body="$(python3 -c "
import json, sys
app_name, domain = sys.argv[1:3]
print(json.dumps({
  'name': app_name,
  'domain': domain,
  'type': 'self_hosted',
  'session_duration': '24h',
  'auto_redirect_to_identity': True,
}))
" "$APP_NAME" "$DOMAIN")"
  created="$(cf POST "${ACCOUNT_PATH}/access/apps" "$create_body")"
  require_success "$created" "Failed to create Access app"
  APP_ID="$(printf '%s' "$created" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['id'])")"
  echo "    Created app ${APP_ID}"
else
  echo "    Found app ${APP_ID}"
fi

replace_access_policies "$APP_ID"

echo ""
echo "=============================================="
echo " Cloudflare Access configured"
echo " Domain:  https://${DOMAIN}"
echo " Email:   ${POCKET_ALLOWED_EMAIL}"
echo " Account: ${CLOUDFLARE_ACCOUNT_ID}"
echo "=============================================="
echo ""
echo "Next — store GitHub secrets (run on your machine with gh auth):"
echo ""
echo "  gh secret set CLOUDFLARE_API_TOKEN --repo ${REPO}"
echo "  gh secret set CLOUDFLARE_ACCOUNT_ID --repo ${REPO} --body \"${CLOUDFLARE_ACCOUNT_ID}\""
echo "  gh secret set POCKET_ALLOWED_EMAIL --repo ${REPO} --body \"${POCKET_ALLOWED_EMAIL}\""
echo ""
echo "Then deploy Pages:"
echo ""
echo "  gh workflow run cloudflare-pages.yml --repo ${REPO}"
echo ""
echo "Enable email OTP login: Zero Trust → Settings → Authentication → One-time PIN"
echo "iPhone: Safari → https://${DOMAIN} → Access login → Add to Home Screen"
echo ""
