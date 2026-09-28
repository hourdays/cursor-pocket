#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
CALL_LOG="${TMP_DIR}/calls.log"
STATE_DIR="${TMP_DIR}/state"

mkdir -p "${STATE_DIR}"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
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
printf '%s\t%s\t%s\n' "${method}" "${path}" "${data}" >> "${MOCK_LOG}"

policy_json() {
  POLICY_ID="${1:-policy-managed}" python3 - <<'PY'
import json, os
print(json.dumps({
    "id": os.environ["POLICY_ID"],
    "name": "Only allowed email",
    "decision": "allow",
    "precedence": 1,
    "include": [{"email": {"email": os.environ["POCKET_ALLOWED_EMAIL"]}}],
}))
PY
}

policy_payload="$(policy_json policy-managed)"

case "${method} ${path}" in
  "GET /user/tokens/verify")
    echo '{"success":true,"result":{"status":"active"}}'
    ;;
  "GET /accounts?per_page=5")
    echo '{"success":true,"result":[{"id":"acct"}]}'
    ;;
  "GET /accounts/acct/access/apps?per_page=50")
    if [[ "${SCENARIO}" == "new_app" ]]; then
      echo '{"success":true,"result":[]}'
    else
      python3 - <<'PY'
import json, os
print(json.dumps({
    "success": True,
    "result": [{"id": "app-existing", "domain": os.environ.get("POCKET_DOMAIN", "cursor-pocket.pages.dev")}],
}))
PY
    fi
    ;;
  "POST /accounts/acct/access/apps")
    echo '{"success":true,"result":{"id":"app-new"}}'
    ;;
  "GET /accounts/acct/access/apps/app-new/policies?per_page=50")
    printf '{"success":true,"result":[%s]}\n' "${policy_payload}"
    ;;
  "GET /accounts/acct/access/apps/app-existing/policies?per_page=50")
    case "${SCENARIO}" in
      existing_create)
        if [[ -f "${MOCK_STATE}/policy-created" ]]; then
          printf '{"success":true,"result":[%s]}\n' "${policy_payload}"
        else
          echo '{"success":true,"result":[]}'
        fi
        ;;
      existing_update)
        printf '{"success":true,"result":[%s]}\n' "${policy_payload}"
        ;;
      unmanaged_policy)
        echo '{"success":true,"result":[{"id":"broad","name":"Everyone","decision":"allow","include":[{"everyone":{}}]}]}'
        ;;
      duplicate_managed)
        printf '{"success":true,"result":[%s,%s]}\n' "${policy_payload}" "${policy_payload}"
        ;;
      *)
        echo "unknown scenario ${SCENARIO}" >&2
        exit 99
        ;;
    esac
    ;;
  "POST /accounts/acct/access/apps/app-existing/policies")
    touch "${MOCK_STATE}/policy-created"
    echo '{"success":true,"result":{"id":"policy-managed"}}'
    ;;
  "PUT /accounts/acct/access/apps/app-existing/policies/policy-managed")
    touch "${MOCK_STATE}/policy-updated"
    echo '{"success":true,"result":{"id":"policy-managed"}}'
    ;;
  *)
    echo "unexpected request: ${method} ${path}" >&2
    exit 98
    ;;
esac
MOCK

chmod +x "${TMP_DIR}/curl"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run_script() {
  local scenario="$1"
  : > "${CALL_LOG}"
  rm -f "${STATE_DIR}/policy-created" "${STATE_DIR}/policy-updated"
  PATH="${TMP_DIR}:${PATH}" \
    MOCK_LOG="${CALL_LOG}" \
    MOCK_STATE="${STATE_DIR}" \
    SCENARIO="${scenario}" \
    CLOUDFLARE_API_TOKEN="token" \
    POCKET_ALLOWED_EMAIL="allowed@example.com" \
    bash "${ROOT}/scripts/setup-cloudflare.sh"
}

assert_calls_contain() {
  local needle="$1"
  local calls
  calls="$(<"${CALL_LOG}")"
  [[ "${calls}" == *"${needle}"* ]] || fail "expected call log to contain ${needle}; got: ${calls}"
}

assert_calls_not_contain() {
  local needle="$1"
  local calls
  calls="$(<"${CALL_LOG}")"
  [[ "${calls}" != *"${needle}"* ]] || fail "did not expect call log to contain ${needle}; got: ${calls}"
}

output="$(run_script new_app 2>&1)" || fail "new app path failed: ${output}"
[[ "${output}" == *"Access policy OK"* ]] || fail "new app path did not validate policy"
assert_calls_contain $'POST\t/accounts/acct/access/apps\t'

output="$(run_script existing_create 2>&1)" || fail "existing app create-policy path failed: ${output}"
[[ "${output}" == *"Policy created"* ]] || fail "existing app path did not create policy"
assert_calls_contain $'POST\t/accounts/acct/access/apps/app-existing/policies\t'

output="$(run_script existing_update 2>&1)" || fail "existing app update-policy path failed: ${output}"
[[ "${output}" == *"Policy updated"* ]] || fail "existing app path did not update policy"
assert_calls_contain $'PUT\t/accounts/acct/access/apps/app-existing/policies/policy-managed\t'

if output="$(run_script unmanaged_policy 2>&1)"; then
  fail "unmanaged policy path should have failed: ${output}"
fi
[[ "${output}" == *"unmanaged policies"* ]] || fail "unmanaged policy failure did not explain risk: ${output}"
assert_calls_not_contain $'POST\t/accounts/acct/access/apps/app-existing/policies\t'
assert_calls_not_contain $'PUT\t/accounts/acct/access/apps/app-existing/policies/policy-managed\t'

if output="$(run_script duplicate_managed 2>&1)"; then
  fail "duplicate managed policy path should have failed: ${output}"
fi
[[ "${output}" == *"multiple managed policies"* ]] || fail "duplicate managed policy failure did not explain risk: ${output}"

echo "setup-cloudflare tests passed"
