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

require_success() {
  local action="$1"
  local response="$2"
  if ! echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('success') else 1)" 2>/dev/null; then
    echo "ERROR: Failed to ${action}"
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    exit 1
  fi
}

echo "==> Verifying Cloudflare API token…"
verify="$(cf GET "/user/tokens/verify")"
require_success "verify CLOUDFLARE_API_TOKEN" "$verify"
echo "    Token OK"

if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  echo "==> Detecting account ID…"
  accounts="$(cf GET "/accounts?per_page=5")"
  require_success "list Cloudflare accounts" "$accounts"
  CLOUDFLARE_ACCOUNT_ID="$(echo "$accounts" | python3 -c "
import sys, json
d = json.load(sys.stdin)
items = d.get('result') or []
if not items:
    print('ERROR: No Cloudflare accounts are visible to this token.', file=sys.stderr)
    raise SystemExit(1)
if len(items) > 1:
    print('ERROR: Multiple Cloudflare accounts are visible. Set CLOUDFLARE_ACCOUNT_ID explicitly:', file=sys.stderr)
    for item in items:
        print(f\"  {item.get('id')}  {item.get('name', '')}\", file=sys.stderr)
    raise SystemExit(1)
print(items[0]['id'])
")"
  echo "    Account: ${CLOUDFLARE_ACCOUNT_ID}"
fi

ACCOUNT_PATH="/accounts/${CLOUDFLARE_ACCOUNT_ID}"

echo "==> Looking for existing Access app on ${DOMAIN}…"
apps="$(cf GET "${ACCOUNT_PATH}/access/apps?per_page=50")"
require_success "list Access applications" "$apps"
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
  create_body="$(APP_NAME="$APP_NAME" DOMAIN="$DOMAIN" EMAIL="$POCKET_ALLOWED_EMAIL" python3 -c "
import json, os
print(json.dumps({
  'name': os.environ['APP_NAME'],
  'domain': os.environ['DOMAIN'],
  'type': 'self_hosted',
  'session_duration': '24h',
  'auto_redirect_to_identity': True,
  'policies': [{
    'name': 'Only allowed email',
    'decision': 'allow',
    'precedence': 1,
    'include': [{'email': {'email': os.environ['EMAIL']}}]
  }]
}))
")"
  created="$(cf POST "${ACCOUNT_PATH}/access/apps" "$create_body")"
  require_success "create Access app" "$created"
  APP_ID="$(echo "$created" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['id'])")"
  echo "    Created app ${APP_ID}"
else
  echo "    Found app ${APP_ID}"
  echo "==> Checking existing Access policies…"
  policies="$(cf GET "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies?per_page=50")"
  require_success "list Access policies" "$policies"
  policy_check="$(echo "$policies" | EMAIL="$POCKET_ALLOWED_EMAIL" python3 -c "
import json
import os
import sys

email = os.environ['EMAIL'].strip().lower()
data = json.load(sys.stdin)
policies = data.get('result') or []

def email_values(rule):
    email_rule = rule.get('email')
    if isinstance(email_rule, dict):
        value = email_rule.get('email')
        if isinstance(value, str):
            return [value.strip().lower()]
        if isinstance(value, list):
            return [str(item).strip().lower() for item in value]
    return []

def is_exact_email_allow(policy):
    if policy.get('decision') != 'allow':
        return False
    if policy.get('require') or policy.get('exclude'):
        return False
    include = policy.get('include') or []
    if len(include) != 1:
        return False
    return email_values(include[0]) == [email]

unsafe = [p for p in policies if not is_exact_email_allow(p)]
safe = [p for p in policies if is_exact_email_allow(p)]

if unsafe:
    print('unsafe')
    for policy in unsafe:
        name = policy.get('name') or policy.get('id') or '<unnamed>'
        decision = policy.get('decision') or '<unknown decision>'
        print(f'- {name} ({decision})')
elif safe:
    print('safe')
else:
    print('missing')
")"
  policy_status="${policy_check%%$'\n'*}"
  if [[ "$policy_status" == "unsafe" ]]; then
    echo "ERROR: Existing Access app has policies that may allow more than ${POCKET_ALLOWED_EMAIL}:"
    printf '%s\n' "${policy_check#*$'\n'}"
    echo ""
    echo "Remove or narrow those policies in Cloudflare Zero Trust, then rerun this script."
    exit 1
  elif [[ "$policy_status" == "safe" ]]; then
    echo "    Existing policies only allow ${POCKET_ALLOWED_EMAIL}"
  else
    echo "==> Adding allow policy for ${POCKET_ALLOWED_EMAIL}…"
    policy_body="$(EMAIL="$POCKET_ALLOWED_EMAIL" python3 -c "
import json, os
print(json.dumps({
  'name': 'Only allowed email',
  'decision': 'allow',
  'precedence': 1,
  'include': [{'email': {'email': os.environ['EMAIL']}}]
}))
")"
    policy_result="$(cf POST "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies" "$policy_body")"
    require_success "create Access policy" "$policy_result"
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
