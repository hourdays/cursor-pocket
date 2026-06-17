#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"
cat >"${TMP_DIR}/bin/curl" <<'FAKE_CURL'
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
    -sS|-s|-S)
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
scenario="${CLOUDFAKE_SCENARIO:?}"

if [[ "$method" == "GET" && "$path" == "/user/tokens/verify" ]]; then
  printf '{"success":true,"result":{"status":"active"}}\n'
  exit 0
fi

if [[ "$method" == "GET" && "$path" == "/accounts?per_page=6" ]]; then
  if [[ "$scenario" == "multiple-accounts" ]]; then
    printf '{"success":true,"result":[{"id":"acct-a","name":"A"},{"id":"acct-b","name":"B"}]}\n'
  else
    printf '{"success":true,"result":[{"id":"acct","name":"Primary"}]}\n'
  fi
  exit 0
fi

if [[ "$method" == "GET" && "$path" == "/accounts/acct/access/apps?per_page=50" ]]; then
  case "$scenario" in
    create-success)
      printf '{"success":true,"result":[]}\n'
      ;;
    unsafe-existing-policy|duplicate-policy-safe)
      printf '{"success":true,"result":[{"id":"app-existing","domain":"cursor-pocket.pages.dev"}]}\n'
      ;;
    *)
      printf '{"success":false,"errors":[{"message":"unexpected scenario"}]}\n'
      ;;
  esac
  exit 0
fi

if [[ "$method" == "POST" && "$path" == "/accounts/acct/access/apps" ]]; then
  printf '{"success":true,"result":{"id":"app-new"}}\n'
  exit 0
fi

if [[ "$method" == "POST" && "$path" == "/accounts/acct/access/apps/app-existing/policies" ]]; then
  if [[ "$scenario" == "duplicate-policy-safe" ]]; then
    printf '{"success":false,"errors":[{"message":"precedence already exists"}]}\n'
  else
    printf '{"success":true,"result":{"id":"policy-new"}}\n'
  fi
  exit 0
fi

if [[ "$method" == "GET" && "$path" == "/accounts/acct/access/apps/app-new/policies?per_page=50" ]]; then
  printf '{"success":true,"result":[{"id":"policy-new","name":"Only allowed email","decision":"allow","include":[{"email":{"email":"user@example.com"}}]}]}\n'
  exit 0
fi

if [[ "$method" == "GET" && "$path" == "/accounts/acct/access/apps/app-existing/policies?per_page=50" ]]; then
  case "$scenario" in
    unsafe-existing-policy)
      printf '{"success":true,"result":[{"id":"policy-public","name":"Everyone","decision":"allow","include":[{"everyone":{}}]},{"id":"policy-email","name":"Only allowed email","decision":"allow","include":[{"email":{"email":"user@example.com"}}]}]}\n'
      ;;
    duplicate-policy-safe)
      printf '{"success":true,"result":[{"id":"policy-email","name":"Only allowed email","decision":"allow","include":[{"email":{"email":"user@example.com"}}]}]}\n'
      ;;
    *)
      printf '{"success":false,"errors":[{"message":"unexpected scenario"}]}\n'
      ;;
  esac
  exit 0
fi

printf '{"success":false,"errors":[{"message":"unhandled fake curl request","method":"%s","path":"%s","scenario":"%s"}]}\n' "$method" "$path" "$scenario"
FAKE_CURL
chmod +x "${TMP_DIR}/bin/curl"

run_setup() {
  local scenario="$1"
  shift
  env \
    PATH="${TMP_DIR}/bin:${PATH}" \
    CLOUDFAKE_SCENARIO="${scenario}" \
    CLOUDFLARE_API_TOKEN="fake-token" \
    POCKET_ALLOWED_EMAIL="user@example.com" \
    "$@" \
    bash "${ROOT_DIR}/scripts/setup-cloudflare.sh"
}

assert_success_contains() {
  local scenario="$1"
  local expected="$2"
  shift 2
  local output
  if ! output="$(run_setup "$scenario" "$@" 2>&1)"; then
    printf 'Expected %s to succeed, but it failed:\n%s\n' "$scenario" "$output" >&2
    return 1
  fi
  if [[ "$output" != *"$expected"* ]]; then
    printf 'Expected %s output to contain %q, got:\n%s\n' "$scenario" "$expected" "$output" >&2
    return 1
  fi
}

assert_failure_contains() {
  local scenario="$1"
  local expected="$2"
  shift 2
  local output
  if output="$(run_setup "$scenario" "$@" 2>&1)"; then
    printf 'Expected %s to fail, but it succeeded:\n%s\n' "$scenario" "$output" >&2
    return 1
  fi
  if [[ "$output" != *"$expected"* ]]; then
    printf 'Expected %s failure to contain %q, got:\n%s\n' "$scenario" "$expected" "$output" >&2
    return 1
  fi
}

assert_success_contains "create-success" "Email-only policy verified"
assert_success_contains "duplicate-policy-safe" "Email-only policy verified" CLOUDFLARE_ACCOUNT_ID="acct"
assert_failure_contains "multiple-accounts" "Set CLOUDFLARE_ACCOUNT_ID explicitly"
assert_failure_contains "unsafe-existing-policy" "grant access beyond user@example.com" CLOUDFLARE_ACCOUNT_ID="acct"

echo "setup-cloudflare tests passed"
