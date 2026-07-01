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
POLICY_NAME="${POCKET_POLICY_NAME:-Only allowed email}"

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
  local label="$1"
  local response="$2"
  if ! printf '%s' "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('success') else 1)" 2>/dev/null; then
    echo "ERROR: ${label}"
    printf '%s' "$response" | python3 -m json.tool 2>/dev/null || printf '%s\n' "$response"
    exit 1
  fi
}

policy_body() {
  POLICY_NAME="$POLICY_NAME" EMAIL="$POCKET_ALLOWED_EMAIL" python3 -c "
import json, os
print(json.dumps({
  'name': os.environ['POLICY_NAME'],
  'decision': 'allow',
  'precedence': 1,
  'include': [{'email': {'email': os.environ['EMAIL']}}]
}))
"
}

echo "==> Verifying Cloudflare API token…"
verify="$(cf GET "/user/tokens/verify")"
require_success "Invalid CLOUDFLARE_API_TOKEN" "$verify"
echo "    Token OK"

if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  echo "==> Detecting account ID…"
  accounts="$(cf GET "/accounts?per_page=5")"
  require_success "Failed to list Cloudflare accounts" "$accounts"
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
require_success "Failed to list Access applications" "$apps"
APP_ID="$(printf '%s' "$apps" | DOMAIN="$DOMAIN" python3 -c "
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
  create_body="$(APP_NAME="$APP_NAME" DOMAIN="$DOMAIN" EMAIL="$POCKET_ALLOWED_EMAIL" POLICY_NAME="$POLICY_NAME" python3 -c "
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
  require_success "Failed to create Access app" "$created"
  APP_ID="$(printf '%s' "$created" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['id'])")"
  echo "    Created app ${APP_ID}"
else
  echo "    Found app ${APP_ID}"
  echo "==> Replacing Access policies with allow policy for ${POCKET_ALLOWED_EMAIL}…"
  policies="$(cf GET "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies?per_page=50")"
  require_success "Failed to list Access policies" "$policies"
  MANAGED_POLICY_ID="$(printf '%s' "$policies" | POLICY_NAME="$POLICY_NAME" python3 -c "
import sys, json, os
name = os.environ['POLICY_NAME']
d = json.load(sys.stdin)
for policy in d.get('result') or []:
    if policy.get('name') == name:
        print(policy['id'])
        break
")"
  policy_json="$(policy_body)"
  if [[ -n "${MANAGED_POLICY_ID}" ]]; then
    policy_result="$(cf PUT "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies/${MANAGED_POLICY_ID}" "$policy_json")"
    require_success "Failed to update Access policy" "$policy_result"
    echo "    Policy updated"
  else
    policy_result="$(cf POST "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies" "$policy_json")"
    require_success "Failed to create Access policy" "$policy_result"
    MANAGED_POLICY_ID="$(printf '%s' "$policy_result" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['id'])")"
    echo "    Policy added"
  fi

  stale_policy_ids="$(printf '%s' "$policies" | MANAGED_POLICY_ID="$MANAGED_POLICY_ID" python3 -c "
import sys, json, os
managed = os.environ['MANAGED_POLICY_ID']
d = json.load(sys.stdin)
for policy in d.get('result') or []:
    policy_id = policy.get('id')
    if policy_id and policy_id != managed:
        print(policy_id)
")"
  if [[ -n "${stale_policy_ids}" ]]; then
    echo "==> Removing stale Access policies…"
    while IFS= read -r policy_id; do
      [[ -z "${policy_id}" ]] && continue
      delete_result="$(cf DELETE "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies/${policy_id}")"
      require_success "Failed to delete stale Access policy ${policy_id}" "$delete_result"
      echo "    Removed policy ${policy_id}"
    done <<< "${stale_policy_ids}"
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
