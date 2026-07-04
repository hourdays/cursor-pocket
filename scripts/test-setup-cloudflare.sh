#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
MOCK_DIR="${TMP_DIR}/bin"
LOG="${TMP_DIR}/curl.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$MOCK_DIR"

cat >"${MOCK_DIR}/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

method=""
url=""
data=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -X)
      method="$2"
      shift 2
      ;;
    -d)
      data="$2"
      shift 2
      ;;
    -H)
      shift 2
      ;;
    -sS|-s|-S)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

prefix="https://api.cloudflare.com/client/v4"
path="${url#${prefix}}"
printf '%s\t%s\t%s\n' "$method" "$path" "$data" >>"$MOCK_CF_LOG"

case "$path" in
  "/user/tokens/verify")
    printf '{"success":true,"result":{"status":"active"}}\n'
    ;;
  "/accounts?per_page=5")
    printf '{"success":true,"result":[{"id":"acct"}]}\n'
    ;;
  "/accounts/acct/access/apps?per_page=50")
    case "$MOCK_CF_SCENARIO" in
      new-app)
        printf '{"success":true,"result":[]}\n'
        ;;
      existing-update|existing-duplicate|existing-no-policy)
        printf '{"success":true,"result":[{"id":"app-1","domain":"cursor-pocket.pages.dev"}]}\n'
        ;;
      *)
        printf '{"success":false,"errors":[{"message":"unknown scenario"}]}\n'
        ;;
    esac
    ;;
  "/accounts/acct/access/apps")
    printf '{"success":true,"result":{"id":"app-new"}}\n'
    ;;
  "/accounts/acct/access/apps/app-1/policies?per_page=50")
    case "$MOCK_CF_SCENARIO" in
      existing-update)
        printf '{"success":true,"result":[{"id":"pol-1","name":"Only allowed email"}]}\n'
        ;;
      existing-duplicate)
        printf '{"success":true,"result":[{"id":"pol-old-1","name":"Only allowed email"},{"id":"pol-old-2","name":"Only allowed email"}]}\n'
        ;;
      existing-no-policy)
        printf '{"success":true,"result":[{"id":"other","name":"Team policy"}]}\n'
        ;;
      *)
        printf '{"success":false,"errors":[{"message":"unexpected policies request"}]}\n'
        ;;
    esac
    ;;
  "/accounts/acct/access/apps/app-1/policies")
    printf '{"success":true,"result":{"id":"pol-new"}}\n'
    ;;
  "/accounts/acct/access/apps/app-1/policies/pol-1"|\
  "/accounts/acct/access/apps/app-1/policies/pol-old-1"|\
  "/accounts/acct/access/apps/app-1/policies/pol-old-2")
    printf '{"success":true,"result":{"id":"updated"}}\n'
    ;;
  *)
    printf '{"success":false,"errors":[{"message":"unexpected path %s"}]}\n' "$path"
    ;;
esac
MOCK
chmod +x "${MOCK_DIR}/curl"

run_setup() {
  local scenario="$1"
  local email="$2"
  local output="${TMP_DIR}/${scenario}.out"
  : >"$LOG"

  if ! env -u CLOUDFLARE_ACCOUNT_ID \
    MOCK_CF_SCENARIO="$scenario" \
    MOCK_CF_LOG="$LOG" \
    PATH="${MOCK_DIR}:${PATH}" \
    CLOUDFLARE_API_TOKEN="token" \
    POCKET_ALLOWED_EMAIL="$email" \
    POCKET_DOMAIN="cursor-pocket.pages.dev" \
    "${ROOT_DIR}/scripts/setup-cloudflare.sh" >"$output" 2>&1; then
    printf 'setup-cloudflare.sh failed in scenario %s\n' "$scenario"
    printf '--- output ---\n'
    python3 - "$output" <<'PY'
import sys
print(open(sys.argv[1]).read())
PY
    return 1
  fi
}

assert_created_app() {
  local email="$1"
  python3 - "$LOG" "$email" <<'PY'
import json
import sys

log_path, email = sys.argv[1:3]
entries = [line.rstrip("\n").split("\t", 2) for line in open(log_path)]
creates = [entry for entry in entries if entry[0] == "POST" and entry[1] == "/accounts/acct/access/apps"]
assert len(creates) == 1, entries
body = json.loads(creates[0][2])
assert body["domain"] == "cursor-pocket.pages.dev", body
assert body["policies"][0]["name"] == "Only allowed email", body
assert body["policies"][0]["include"][0]["email"]["email"] == email, body
PY
}

assert_posted_policy() {
  local email="$1"
  python3 - "$LOG" "$email" <<'PY'
import json
import sys

log_path, email = sys.argv[1:3]
entries = [line.rstrip("\n").split("\t", 2) for line in open(log_path)]
posts = [entry for entry in entries if entry[0] == "POST" and entry[1] == "/accounts/acct/access/apps/app-1/policies"]
puts = [entry for entry in entries if entry[0] == "PUT" and "/policies/" in entry[1]]
assert len(posts) == 1, entries
assert puts == [], entries
body = json.loads(posts[0][2])
assert body["include"][0]["email"]["email"] == email, body
PY
}

assert_updated_policies() {
  local email="$1"
  shift
  python3 - "$LOG" "$email" "$@" <<'PY'
import json
import sys

log_path = sys.argv[1]
email = sys.argv[2]
expected_ids = sys.argv[3:]
entries = [line.rstrip("\n").split("\t", 2) for line in open(log_path)]
posts = [entry for entry in entries if entry[0] == "POST" and entry[1] == "/accounts/acct/access/apps/app-1/policies"]
puts = [entry for entry in entries if entry[0] == "PUT" and "/policies/" in entry[1]]
put_ids = [entry[1].rsplit("/", 1)[1] for entry in puts]
assert posts == [], entries
assert put_ids == expected_ids, entries
for entry in puts:
    body = json.loads(entry[2])
    assert body["name"] == "Only allowed email", body
    assert body["include"][0]["email"]["email"] == email, body
PY
}

run_setup "new-app" "new@example.com"
assert_created_app "new@example.com"

run_setup "existing-no-policy" "new@example.com"
assert_posted_policy "new@example.com"

run_setup "existing-update" "new@example.com"
assert_updated_policies "new@example.com" "pol-1"

run_setup "existing-duplicate" "new@example.com"
assert_updated_policies "new@example.com" "pol-old-1" "pol-old-2"

printf 'setup-cloudflare.sh mock tests passed\n'
