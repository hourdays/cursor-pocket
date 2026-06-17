#!/usr/bin/env bash
# Provision Cloudflare Access for Cursor Pocket (API-driven).
# Run locally with your Cloudflare API token — not from CI without secrets.
#
# Usage:
#   export CLOUDFLARE_API_TOKEN="..."
#   export POCKET_ALLOWED_EMAIL="you@example.com"   # required
#   export CLOUDFLARE_ACCOUNT_ID="..."              # required if token sees multiple accounts
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
  python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('success') else 1)" 2>/dev/null
}

pretty_json() {
  python3 -m json.tool 2>/dev/null || cat
}

verify_email_only_policy() {
  local policies="$1"
  if ! echo "$policies" | EMAIL="$POCKET_ALLOWED_EMAIL" python3 -c "
import json
import os
import sys

allowed = os.environ['EMAIL'].strip().lower()
data = json.load(sys.stdin)
if not data.get('success'):
    print('Cloudflare returned an unsuccessful policy response', file=sys.stderr)
    raise SystemExit(1)

policies = data.get('result') or []

def email_from_rule(rule):
    email = rule.get('email')
    if isinstance(email, dict):
        return email.get('email')
    if isinstance(email, str):
        return email
    return None

def is_allowed_email_rule(rule):
    email = email_from_rule(rule)
    return isinstance(email, str) and email.strip().lower() == allowed

matching_policy = False
unsafe = []
for policy in policies:
    decision = policy.get('decision')
    name = policy.get('name') or policy.get('id') or '<unnamed>'
    includes = policy.get('include') or []
    if decision == 'bypass':
        unsafe.append(f'{name}: bypass policies skip Access login')
        continue
    if decision != 'allow':
        continue
    if any(is_allowed_email_rule(rule) for rule in includes):
        matching_policy = True
    for rule in includes:
        if not is_allowed_email_rule(rule):
            unsafe.append(f'{name}: allows rule {json.dumps(rule, sort_keys=True)}')

if not matching_policy:
    print(f'No Allow policy includes {allowed}', file=sys.stderr)
    raise SystemExit(1)
if unsafe:
    print(f'Found policies that grant access beyond {allowed}:', file=sys.stderr)
    for item in unsafe:
        print(f'  - {item}', file=sys.stderr)
    raise SystemExit(1)
"
  then
    echo "ERROR: Access policies do not enforce ${POCKET_ALLOWED_EMAIL} only"
    echo "$policies" | pretty_json
    exit 1
  fi
}

echo "==> Verifying Cloudflare API token…"
verify="$(cf GET "/user/tokens/verify")"
if ! echo "$verify" | json_success; then
  echo "ERROR: Invalid CLOUDFLARE_API_TOKEN"
  echo "$verify"
  exit 1
fi
echo "    Token OK"

if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  echo "==> Detecting account ID…"
  accounts="$(cf GET "/accounts?per_page=6")"
  if ! CLOUDFLARE_ACCOUNT_ID="$(echo "$accounts" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if not d.get('success'):
    raise SystemExit('failed to list accounts')
items = d.get('result') or []
if not items:
    raise SystemExit('no accounts')
if len(items) > 1:
    print('ERROR: Multiple Cloudflare accounts found. Set CLOUDFLARE_ACCOUNT_ID explicitly.', file=sys.stderr)
    for item in items:
        print(f\"  {item.get('id')}  {item.get('name', '')}\", file=sys.stderr)
    raise SystemExit(1)
print(items[0]['id'])
")"; then
    echo "ERROR: Could not auto-detect a single Cloudflare account"
    echo "$accounts" | pretty_json
    exit 1
  fi
  echo "    Account: ${CLOUDFLARE_ACCOUNT_ID}"
fi

ACCOUNT_PATH="/accounts/${CLOUDFLARE_ACCOUNT_ID}"

echo "==> Looking for existing Access app on ${DOMAIN}…"
apps="$(cf GET "${ACCOUNT_PATH}/access/apps?per_page=50")"
if ! APP_ID="$(echo "$apps" | DOMAIN="$DOMAIN" python3 -c "
import sys, json, os
domain = os.environ['DOMAIN']
d = json.load(sys.stdin)
if not d.get('success'):
    raise SystemExit('failed to list Access applications')
for app in d.get('result') or []:
    if app.get('domain') == domain:
        print(app['id'])
        break
")"; then
  echo "ERROR: Failed to list Access applications"
  echo "$apps" | pretty_json
  exit 1
fi

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
  if ! echo "$created" | json_success; then
    echo "ERROR: Failed to create Access app"
    echo "$created" | pretty_json
    exit 1
  fi
  APP_ID="$(echo "$created" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['id'])")"
  echo "    Created app ${APP_ID}"
else
  echo "    Found app ${APP_ID}"
  echo "==> Ensuring allow policy for ${POCKET_ALLOWED_EMAIL}…"
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
  if ! echo "$policy_result" | json_success; then
    echo "WARN: Policy create failed; verifying whether a safe policy already exists."
    echo "$policy_result" | pretty_json
  else
    echo "    Policy added"
  fi
fi

echo "==> Verifying Access policies…"
policies="$(cf GET "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies?per_page=50")"
verify_email_only_policy "$policies"
echo "    Email-only policy verified"

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
