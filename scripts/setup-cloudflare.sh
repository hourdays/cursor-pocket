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
POLICY_NAME="Only allowed email"
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

require_success() {
  local response="$1"
  local message="$2"
  if ! echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('success') else 1)" 2>/dev/null; then
    echo "ERROR: ${message}"
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    exit 1
  fi
}

build_policy_body() {
  POLICY_NAME="$POLICY_NAME" EMAIL="$POCKET_ALLOWED_EMAIL" python3 -c "
import json, os
print(json.dumps({
  'name': os.environ['POLICY_NAME'],
  'decision': 'allow',
  'precedence': 1,
  'include': [{'email': {'email': os.environ['EMAIL']}}],
}))
"
}

echo "==> Verifying Cloudflare API token…"
verify="$(cf GET "/user/tokens/verify")"
if ! echo "$verify" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('success') else 1)" 2>/dev/null; then
  echo "ERROR: Invalid CLOUDFLARE_API_TOKEN"
  echo "$verify"
  exit 1
fi
echo "    Token OK"

if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  echo "==> Detecting account ID…"
  accounts="$(cf GET "/accounts?per_page=5")"
  require_success "$accounts" "Failed to list Cloudflare accounts"
  CLOUDFLARE_ACCOUNT_ID="$(echo "$accounts" | python3 -c "
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
require_success "$apps" "Failed to list Access apps"
APP_ID="$(echo "$apps" | DOMAIN="$DOMAIN" python3 -c "
import sys, json, os
domain = os.environ['DOMAIN']
d = json.load(sys.stdin)
for app in d.get('result') or []:
    if app.get('domain') == domain:
        print(app['id'])
        break
")"

if [[ -z "${APP_ID}" ]]; then
  echo "==> Creating Access application…"
  create_body="$(APP_NAME="$APP_NAME" DOMAIN="$DOMAIN" POLICY_NAME="$POLICY_NAME" EMAIL="$POCKET_ALLOWED_EMAIL" python3 -c "
import json, os
print(json.dumps({
  'name': os.environ['APP_NAME'],
  'domain': os.environ['DOMAIN'],
  'type': 'self_hosted',
  'session_duration': '24h',
  'auto_redirect_to_identity': True,
  'policies': [{
    'name': os.environ['POLICY_NAME'],
    'decision': 'allow',
    'precedence': 1,
    'include': [{'email': {'email': os.environ['EMAIL']}}]
  }]
}))
")"
  created="$(cf POST "${ACCOUNT_PATH}/access/apps" "$create_body")"
  require_success "$created" "Failed to create Access app"
  APP_ID="$(echo "$created" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['id'])")"
  echo "    Created app ${APP_ID}"
else
  echo "    Found app ${APP_ID}"
  echo "==> Ensuring allow policy for ${POCKET_ALLOWED_EMAIL}…"
  policy_body="$(build_policy_body)"
  policies="$(cf GET "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies?per_page=50")"
  require_success "$policies" "Failed to list Access policies"
  mapfile -t POLICY_IDS < <(echo "$policies" | POLICY_NAME="$POLICY_NAME" python3 -c "
import json, os, sys
policy_name = os.environ['POLICY_NAME']
d = json.load(sys.stdin)
for policy in d.get('result') or []:
    if policy.get('name') == policy_name:
        print(policy['id'])
")

  if [[ "${#POLICY_IDS[@]}" -gt 0 ]]; then
    policy_result="$(cf PUT "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies/${POLICY_IDS[0]}" "$policy_body")"
    require_success "$policy_result" "Failed to update Access policy"
    echo "    Policy updated"

    for stale_policy_id in "${POLICY_IDS[@]:1}"; do
      delete_result="$(cf DELETE "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies/${stale_policy_id}")"
      require_success "$delete_result" "Failed to remove stale duplicate Access policy"
      echo "    Removed stale duplicate policy ${stale_policy_id}"
    done
  else
    policy_result="$(cf POST "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies" "$policy_body")"
    require_success "$policy_result" "Failed to create Access policy"
    echo "    Policy added"
  fi
fi

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
