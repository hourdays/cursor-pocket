#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

curl() {
  local args="$*"

  case "$args" in
    *"/user/tokens/verify"*)
      printf '{"success":true,"result":{}}'
      ;;
    *"/accounts?per_page=5"*)
      printf '{"success":true,"result":[{"id":"acct_123"}]}'
      ;;
    *"/access/apps?per_page=50"*)
      if [[ "${POCKET_TEST_SCENARIO}" == "existing" ]]; then
        printf '{"success":true,"result":[{"id":"app_existing","domain":"cursor-pocket.pages.dev"}]}'
      else
        printf '{"success":true,"result":[]}'
      fi
      ;;
    *"/access/apps/app_existing/policies"*)
      printf '{"success":true,"result":{"id":"policy_existing"}}'
      ;;
    *"/access/apps"*)
      printf '{"success":true,"result":{"id":"app_created"}}'
      ;;
    *)
      printf '{"success":false,"errors":[{"message":"unexpected mock request"}]}'
      ;;
  esac
}
export -f curl

run_case() {
  local scenario="$1"
  local output

  output="$(
    POCKET_TEST_SCENARIO="$scenario" \
    CLOUDFLARE_API_TOKEN="token" \
    POCKET_ALLOWED_EMAIL="user@example.com" \
    POCKET_DOMAIN="cursor-pocket.pages.dev" \
    bash "$ROOT_DIR/scripts/setup-cloudflare.sh"
  )"

  case "$scenario" in
    create)
      [[ "$output" == *"Created app app_created"* ]] ||
        fail "create path did not create app"
      ;;
    existing)
      [[ "$output" == *"Found app app_existing"* ]] ||
        fail "existing path did not find app"
      [[ "$output" == *"Policy added"* ]] ||
        fail "existing path did not add policy"
      ;;
    *)
      fail "unknown scenario: $scenario"
      ;;
  esac
}

run_case create
run_case existing

echo "setup-cloudflare regression tests passed"
