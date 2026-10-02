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
POLICY_NAME="Only allowed email"

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

policy_body() {
  EMAIL="$POCKET_ALLOWED_EMAIL" POLICY_NAME="$POLICY_NAME" python3 -c "
import json, os
print(json.dumps({
  'name': os.environ['POLICY_NAME'],
  'decision': 'allow',
  'precedence': 1,
  'include': [{'email': {'email': os.environ['EMAIL']}}],
}))
"
}

managed_policy_id() {
  POLICY_NAME="$POLICY_NAME" python3 -c "
import json, sys, os
d = json.load(sys.stdin)
if not d.get('success', False):
    raise SystemExit('Cloudflare returned an error while listing Access policies')
items = d.get('result') or []
managed = [p for p in items if p.get('name') == os.environ['POLICY_NAME']]
unmanaged = [p for p in items if p.get('name') != os.environ['POLICY_NAME']]
if unmanaged:
    names = ', '.join(p.get('name') or p.get('id') or '<unnamed>' for p in unmanaged)
    raise SystemExit(
        'Existing Access app has unmanaged policies: '
        + names
        + '. Review/remove them before running this script so the app is not left broadly accessible.'
    )
if len(managed) > 1:
    raise SystemExit('Existing Access app has multiple managed policies; review/remove duplicates before running this script.')
if managed:
    print(managed[0]['id'])
"
}

validate_managed_policy() {
  EMAIL="$POCKET_ALLOWED_EMAIL" POLICY_NAME="$POLICY_NAME" python3 -c "
import json, sys, os
d = json.load(sys.stdin)
if not d.get('success', False):
    raise SystemExit('Cloudflare returned an error while validating Access policies')
items = d.get('result') or []
if len(items) != 1:
    raise SystemExit(f'Expected exactly one Access policy, found {len(items)}')
policy = items[0]
if policy.get('name') != os.environ['POLICY_NAME']:
    raise SystemExit('Access policy name does not match the managed policy')
if policy.get('decision') != 'allow':
    raise SystemExit('Managed Access policy is not an allow policy')
include = policy.get('include') or []
emails = [
    rule.get('email', {}).get('email')
    for rule in include
    if isinstance(rule, dict) and isinstance(rule.get('email'), dict)
]
if emails != [os.environ['EMAIL']]:
    raise SystemExit('Managed Access policy does not allow exactly the configured email')
"
}

echo "==> Verifying Cloudflare API token…"
verify="$(cf GET "/user/tokens/verify")"
if ! echo "$verify" | json_success 2>/dev/null; then
  echo "ERROR: Invalid CLOUDFLARE_API_TOKEN"
  echo "$verify"
  exit 1
fi
echo "    Token OK"

if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  echo "==> Detecting account ID…"
  accounts="$(cf GET "/accounts?per_page=5")"
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
APP_ID="$(echo "$apps" | DOMAIN="$DOMAIN" python3 -c "
import sys, json, os
domain = os.environ['DOMAIN']
d = json.load(sys.stdin)
if not d.get('success', False):
    raise SystemExit('Cloudflare returned an error while listing Access applications')
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
  if ! echo "$created" | json_success; then
    echo "ERROR: Failed to create Access app"
    echo "$created" | python3 -m json.tool 2>/dev/null || echo "$created"
    exit 1
  fi
  APP_ID="$(echo "$created" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['id'])")"
  echo "    Created app ${APP_ID}"
else
  echo "    Found app ${APP_ID}"
  echo "==> Inspecting existing Access policies…"
  policies="$(cf GET "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies?per_page=50")"
  POLICY_ID="$(echo "$policies" | managed_policy_id)"

  echo "==> Ensuring allow policy for ${POCKET_ALLOWED_EMAIL}…"
  body="$(policy_body)"
  if [[ -n "${POLICY_ID}" ]]; then
    policy_result="$(cf PUT "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies/${POLICY_ID}" "$body")"
    policy_action="update"
  else
    policy_result="$(cf POST "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies" "$body")"
    policy_action="create"
  fi
  if ! echo "$policy_result" | json_success; then
    echo "ERROR: Failed to ${policy_action} Access policy"
    echo "$policy_result" | python3 -m json.tool 2>/dev/null || echo "$policy_result"
    exit 1
  fi
  echo "    Policy ${policy_action}d"
fi

echo "==> Validating Access policy…"
policies="$(cf GET "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies?per_page=50")"
echo "$policies" | validate_managed_policy
echo "    Access policy OK"

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
