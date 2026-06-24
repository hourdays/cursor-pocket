#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"${TMP_DIR}/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
url=""
data=""

while (($# > 0)); do
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

printf '%s %s\n' "$method" "$url" >>"${MOCK_CURL_LOG}"
if [[ -n "$data" ]]; then
  printf '%s\0' "$data" >>"${MOCK_CURL_BODIES}"
fi

case "${method} ${url}" in
  "GET https://api.cloudflare.com/client/v4/user/tokens/verify")
    printf '{"success":true,"result":{"id":"token"}}'
    ;;
  "GET https://api.cloudflare.com/client/v4/accounts/account-1/access/apps?per_page=50")
    if [[ "${MOCK_EXISTING_APP}" == "true" ]]; then
      printf '{"success":true,"result":[{"id":"app-existing","domain":"pocket.example.com"}]}'
    else
      printf '{"success":true,"result":[]}'
    fi
    ;;
  "POST https://api.cloudflare.com/client/v4/accounts/account-1/access/apps")
    printf '{"success":true,"result":{"id":"app-created"}}'
    ;;
  "POST https://api.cloudflare.com/client/v4/accounts/account-1/access/apps/app-existing/policies")
    printf '{"success":true,"result":{"id":"policy-created"}}'
    ;;
  *)
    printf '{"success":false,"errors":[{"message":"unexpected mock request"}]}'
    exit 1
    ;;
esac
MOCK_CURL

chmod +x "${TMP_DIR}/curl"

run_setup() {
  local existing_app="$1"
  local output_file="${TMP_DIR}/output-${existing_app}.txt"

  : >"${TMP_DIR}/curl.log"
  : >"${TMP_DIR}/bodies.bin"

  PATH="${TMP_DIR}:${PATH}" \
    MOCK_CURL_LOG="${TMP_DIR}/curl.log" \
    MOCK_CURL_BODIES="${TMP_DIR}/bodies.bin" \
    MOCK_EXISTING_APP="${existing_app}" \
    CLOUDFLARE_API_TOKEN="test-token" \
    CLOUDFLARE_ACCOUNT_ID="account-1" \
    POCKET_ALLOWED_EMAIL="owner@example.com" \
    POCKET_DOMAIN="pocket.example.com" \
    bash "${ROOT}/scripts/setup-cloudflare.sh" >"${output_file}"

  if ! python3 - "${TMP_DIR}/bodies.bin" <<'PY'
import json
import pathlib
import sys

raw = pathlib.Path(sys.argv[1]).read_bytes()
bodies = [json.loads(item) for item in raw.split(b"\0") if item]
if not any(
    body.get("domain") == "pocket.example.com"
    or body.get("include") == [{"email": {"email": "owner@example.com"}}]
    for body in bodies
):
    raise SystemExit("expected request body did not include configured environment")
PY
  then
    echo "ERROR: setup script did not pass configured values into JSON bodies" >&2
    return 1
  fi
}

run_setup false
if ! python3 - "${TMP_DIR}/curl.log" <<'PY'
import pathlib
import sys

log = pathlib.Path(sys.argv[1]).read_text()
if "POST https://api.cloudflare.com/client/v4/accounts/account-1/access/apps\n" not in log:
    raise SystemExit("create-app path was not exercised")
PY
then
  echo "ERROR: setup script did not create a missing Access app" >&2
  exit 1
fi

run_setup true
if ! python3 - "${TMP_DIR}/curl.log" <<'PY'
import pathlib
import sys

log = pathlib.Path(sys.argv[1]).read_text()
expected = "POST https://api.cloudflare.com/client/v4/accounts/account-1/access/apps/app-existing/policies\n"
if expected not in log:
    raise SystemExit("existing-app policy path was not exercised")
PY
then
  echo "ERROR: setup script did not add policy for an existing Access app" >&2
  exit 1
fi

echo "setup-cloudflare mock tests passed"
