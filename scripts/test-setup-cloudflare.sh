#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/scripts/setup-cloudflare.sh"

failures=0

assert_contains() {
  local output="$1"
  local expected="$2"
  local name="$3"
  if [[ "$output" != *"$expected"* ]]; then
    echo "FAIL: ${name}"
    echo "Expected output to contain: ${expected}"
    echo "--- output ---"
    printf '%s\n' "$output"
    failures=$((failures + 1))
  fi
}

assert_not_contains() {
  local output="$1"
  local unexpected="$2"
  local name="$3"
  if [[ "$output" == *"$unexpected"* ]]; then
    echo "FAIL: ${name}"
    echo "Did not expect output to contain: ${unexpected}"
    echo "--- output ---"
    printf '%s\n' "$output"
    failures=$((failures + 1))
  fi
}

run_case() {
  local scenario="$1"
  local expected_status="$2"
  local expected_text="$3"
  local name="$4"
  local tmpdir output status

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  cat >"${tmpdir}/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
url=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -X)
      method="$2"
      shift 2
      ;;
    -d)
      shift 2
      ;;
    -H)
      shift 2
      ;;
    -sS)
      shift
      ;;
    http*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

path="${url#https://api.cloudflare.com/client/v4}"

case "${method} ${path}" in
  "GET /user/tokens/verify")
    printf '{"success":true,"result":{"status":"active"}}\n'
    ;;
  "GET /accounts?per_page=5")
    if [[ "${SCENARIO}" == "multiple_accounts" ]]; then
      printf '{"success":true,"result":[{"id":"account-1","name":"Personal"},{"id":"account-2","name":"Work"}]}\n'
    else
      printf '{"success":true,"result":[{"id":"account-1","name":"Personal"}]}\n'
    fi
    ;;
  "GET /accounts/account-1/access/apps?per_page=50")
    if [[ "${SCENARIO}" == "create_new_app" ]]; then
      printf '{"success":true,"result":[]}\n'
    else
      printf '{"success":true,"result":[{"id":"app-existing","domain":"cursor-pocket.pages.dev"}]}\n'
    fi
    ;;
  "POST /accounts/account-1/access/apps")
    printf '{"success":true,"result":{"id":"app-new"}}\n'
    ;;
  "GET /accounts/account-1/access/apps/app-existing/policies?per_page=50")
    case "${SCENARIO}" in
      existing_unsafe_policy)
        printf '{"success":true,"result":[{"id":"policy-open","name":"Allow everyone","decision":"allow","include":[{"everyone":{}}]}]}\n'
        ;;
      existing_safe_policy)
        printf '{"success":true,"result":[{"id":"policy-safe","name":"Only allowed email","decision":"allow","include":[{"email":{"email":"you@example.com"}}]}]}\n'
        ;;
      *)
        printf '{"success":true,"result":[]}\n'
        ;;
    esac
    ;;
  "POST /accounts/account-1/access/apps/app-existing/policies")
    if [[ "${SCENARIO}" == "policy_create_failure" ]]; then
      printf '{"success":false,"errors":[{"message":"policy already exists"}]}\n'
    else
      printf '{"success":true,"result":{"id":"policy-new"}}\n'
    fi
    ;;
  *)
    printf '{"success":false,"errors":[{"message":"unexpected request: %s %s"}]}\n' "$method" "$path"
    ;;
esac
FAKE_CURL
  chmod +x "${tmpdir}/curl"

  if output="$(
    PATH="${tmpdir}:$PATH" \
    SCENARIO="$scenario" \
    CLOUDFLARE_API_TOKEN="fake-token" \
    POCKET_ALLOWED_EMAIL="you@example.com" \
    POCKET_DOMAIN="cursor-pocket.pages.dev" \
    bash "$SCRIPT" 2>&1
  )"; then
    status=0
  else
    status=$?
  fi

  rm -rf "$tmpdir"
  trap - RETURN

  if [[ "$status" != "$expected_status" ]]; then
    echo "FAIL: ${name}"
    echo "Expected status ${expected_status}, got ${status}"
    echo "--- output ---"
    printf '%s\n' "$output"
    failures=$((failures + 1))
  fi
  assert_contains "$output" "$expected_text" "$name"
}

run_case "create_new_app" 0 "Created app app-new" "creates a new Access app"
run_case "multiple_accounts" 1 "Multiple Cloudflare accounts are visible" "requires explicit account for multiple accounts"
run_case "existing_unsafe_policy" 1 "Existing Access app has policies" "rejects unsafe existing policies"
run_case "policy_create_failure" 1 "Failed to create Access policy" "fails when policy creation fails"
run_case "existing_safe_policy" 0 "Existing policies only allow you@example.com" "accepts safe existing policies"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

echo "All setup-cloudflare tests passed"
