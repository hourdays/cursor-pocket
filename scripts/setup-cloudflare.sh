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

json_success() {
  python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('success') else 1)"
}

print_json() {
  python3 -c "
import json, sys
raw = sys.stdin.read()
try:
    print(json.dumps(json.loads(raw), indent=4))
except Exception:
    print(raw, end='')
"
}

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

echo "==> Verifying Cloudflare API token…"
verify="$(cf GET "/user/tokens/verify")"
if ! json_success <<<"$verify" 2>/dev/null; then
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
APP_ID="$(DOMAIN="$DOMAIN" python3 -c "
import sys, json, os
domain = os.environ['DOMAIN']
d = json.load(sys.stdin)
for app in d.get('result') or []:
    if app.get('domain') == domain:
        print(app['id'])
        break
" <<<"$apps")"

policy_body="$(EMAIL="$POCKET_ALLOWED_EMAIL" python3 -c "
import json, os
print(json.dumps({
  'name': 'Only allowed email',
  'decision': 'allow',
  'precedence': 1,
  'include': [{'email': {'email': os.environ['EMAIL']}}]
}))
")"

ensure_policy() {
  echo "==> Ensuring only ${POCKET_ALLOWED_EMAIL} can access ${DOMAIN}…"
  local policies policy_id policy_result stale_ids stale_id delete_result
  policies="$(cf GET "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies?per_page=50")"
  if ! json_success <<<"$policies"; then
    echo "ERROR: Failed to list existing Access policies"
    echo "$policies" | print_json
    exit 1
  fi

  policy_id="$(POLICY_NAME="Only allowed email" python3 -c "
import sys, json, os
name = os.environ['POLICY_NAME']
d = json.load(sys.stdin)
for policy in d.get('result') or []:
    if policy.get('name') == name:
        print(policy['id'])
        break
" <<<"$policies")"

  if [[ -n "$policy_id" ]]; then
    policy_result="$(cf PUT "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies/${policy_id}" "$policy_body")"
  else
    policy_result="$(cf POST "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies" "$policy_body")"
  fi

  if ! json_success <<<"$policy_result"; then
    echo "ERROR: Failed to apply email allow policy"
    echo "$policy_result" | print_json
    exit 1
  fi

  if [[ -z "$policy_id" ]]; then
    policy_id="$(python3 -c "import sys,json; print(json.load(sys.stdin)['result']['id'])" <<<"$policy_result")"
  fi

  stale_ids="$(KEEP_POLICY_ID="$policy_id" python3 -c "
import sys, json, os
keep = os.environ['KEEP_POLICY_ID']
d = json.load(sys.stdin)
for policy in d.get('result') or []:
    if policy.get('id') == keep:
        continue
    # Granting policies would continue to admit other users even after adding
    # the one-email policy. Blocking policies do not broaden access.
    if policy.get('decision') != 'block':
        print(policy['id'])
" <<<"$policies")"

  while IFS= read -r stale_id; do
    [[ -z "$stale_id" ]] && continue
    echo "    Removing stale grant policy ${stale_id}"
    delete_result="$(cf DELETE "${ACCOUNT_PATH}/access/apps/${APP_ID}/policies/${stale_id}")"
    if ! json_success <<<"$delete_result"; then
      echo "ERROR: Failed to remove stale grant policy ${stale_id}; Access may still allow unintended users"
      echo "$delete_result" | print_json
      exit 1
    fi
  done <<<"$stale_ids"

  echo "    Email policy enforced"
}

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
  if ! json_success <<<"$created"; then
    echo "ERROR: Failed to create Access app"
    echo "$created" | print_json
    exit 1
  fi
  APP_ID="$(echo "$created" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['id'])")"
  echo "    Created app ${APP_ID}"
else
  echo "    Found app ${APP_ID}"
fi

ensure_policy

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
