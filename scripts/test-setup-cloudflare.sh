#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/scripts/setup-cloudflare.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    echo "ASSERTION FAILED: expected output to contain: ${needle}" >&2
    echo "${haystack}" >&2
    exit 1
  fi
}

assert_call() {
  local calls_file="$1"
  local expected="$2"
  local call
  while IFS= read -r call; do
    [[ "${call}" == "${expected}" ]] && return
  done <"${calls_file}"

  echo "ASSERTION FAILED: expected API call: ${expected}" >&2
  printf 'Calls:\n' >&2
  while IFS= read -r call; do
    printf '  %s\n' "${call}" >&2
  done <"${calls_file}"
  exit 1
}

payload_path() {
  local payload_dir="$1"
  local method="$2"
  local path="$3"
  local slug
  slug="$(printf '%s_%s' "${method}" "${path}" | tr -c 'A-Za-z0-9' '_')"
  printf '%s/%s.json' "${payload_dir}" "${slug}"
}

install_mock_curl() {
  local bin_dir="$1"
  cat >"${bin_dir}/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
url=""
data=""

while (($#)); do
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
    *)
      url="$1"
      shift
      ;;
  esac
done

path="${url#https://api.cloudflare.com/client/v4}"
printf '%s %s\n' "${method}" "${path}" >>"${MOCK_CF_CALLS}"

if [[ -n "${data}" ]]; then
  slug="$(printf '%s_%s' "${method}" "${path}" | tr -c 'A-Za-z0-9' '_')"
  printf '%s' "${data}" >"${MOCK_CF_PAYLOAD_DIR}/${slug}.json"
fi

case "${method} ${path}" in
  "GET /user/tokens/verify")
    printf '{"success":true,"result":{"status":"active"}}'
    ;;
  "GET /accounts?per_page=5")
    printf '{"success":true,"result":[{"id":"acc123"}]}'
    ;;
  "GET /accounts/acc123/access/apps?per_page=50")
    if [[ "${MOCK_CF_SCENARIO}" == "create" ]]; then
      printf '{"success":true,"result":[]}'
    else
      printf '{"success":true,"result":[{"id":"app123","domain":"cursor-pocket.pages.dev"}]}'
    fi
    ;;
  "POST /accounts/acc123/access/apps")
    printf '{"success":true,"result":{"id":"new-app"}}'
    ;;
  "GET /accounts/acc123/access/apps/app123/policies?per_page=50")
    if [[ "${MOCK_CF_SCENARIO}" == "existing_create_policy" ]]; then
      printf '{"success":true,"result":[{"id":"broad-policy","name":"Allow everyone","decision":"bypass"}]}'
    else
      printf '{"success":true,"result":[{"id":"email-policy","name":"Only allowed email","decision":"allow"},{"id":"broad-policy","name":"Allow everyone","decision":"bypass"}]}'
    fi
    ;;
  "PUT /accounts/acc123/access/apps/app123/policies/email-policy")
    printf '{"success":true,"result":{"id":"email-policy"}}'
    ;;
  "POST /accounts/acc123/access/apps/app123/policies")
    printf '{"success":true,"result":{"id":"email-policy"}}'
    ;;
  "DELETE /accounts/acc123/access/apps/app123/policies/broad-policy")
    printf '{"success":true,"result":{"id":"broad-policy"}}'
    ;;
  *)
    printf '{"success":false,"errors":[{"message":"unexpected mock request: %s %s"}]}' "${method}" "${path}"
    ;;
esac
MOCK_CURL
  chmod +x "${bin_dir}/curl"
}

run_script() {
  local scenario="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  mkdir -p "${tmp_dir}/bin" "${tmp_dir}/payloads"
  install_mock_curl "${tmp_dir}/bin"

  local output
  output="$(
    PATH="${tmp_dir}/bin:${PATH}" \
    MOCK_CF_SCENARIO="${scenario}" \
    MOCK_CF_CALLS="${tmp_dir}/calls.log" \
    MOCK_CF_PAYLOAD_DIR="${tmp_dir}/payloads" \
    CLOUDFLARE_API_TOKEN="token" \
    POCKET_ALLOWED_EMAIL="allowed@example.com" \
    bash "${SCRIPT}"
  )"

  printf '%s\n' "${tmp_dir}"
  printf '%s\n' "---OUTPUT---"
  printf '%s\n' "${output}"
}

check_email_policy_payload() {
  local payload_file="$1"
  python3 - "${payload_file}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

policy = payload["policies"][0] if "policies" in payload else payload
assert policy["name"] == "Only allowed email", policy
assert policy["decision"] == "allow", policy
assert policy["precedence"] == 1, policy
assert policy["include"] == [{"email": {"email": "allowed@example.com"}}], policy
PY
}

create_result="$(run_script create)"
create_tmp="${create_result%%$'\n'---OUTPUT---*}"
create_output="${create_result#*---OUTPUT---$'\n'}"
assert_contains "${create_output}" "Created app new-app"
assert_call "${create_tmp}/calls.log" "POST /accounts/acc123/access/apps"
check_email_policy_payload "$(payload_path "${create_tmp}/payloads" "POST" "/accounts/acc123/access/apps")"

update_result="$(run_script existing_update_policy)"
update_tmp="${update_result%%$'\n'---OUTPUT---*}"
update_output="${update_result#*---OUTPUT---$'\n'}"
assert_contains "${update_output}" "Policy updated"
assert_contains "${update_output}" "Removed policy broad-policy"
assert_call "${update_tmp}/calls.log" "PUT /accounts/acc123/access/apps/app123/policies/email-policy"
assert_call "${update_tmp}/calls.log" "DELETE /accounts/acc123/access/apps/app123/policies/broad-policy"
check_email_policy_payload "$(payload_path "${update_tmp}/payloads" "PUT" "/accounts/acc123/access/apps/app123/policies/email-policy")"

create_policy_result="$(run_script existing_create_policy)"
create_policy_tmp="${create_policy_result%%$'\n'---OUTPUT---*}"
create_policy_output="${create_policy_result#*---OUTPUT---$'\n'}"
assert_contains "${create_policy_output}" "Policy added"
assert_contains "${create_policy_output}" "Removed policy broad-policy"
assert_call "${create_policy_tmp}/calls.log" "POST /accounts/acc123/access/apps/app123/policies"
assert_call "${create_policy_tmp}/calls.log" "DELETE /accounts/acc123/access/apps/app123/policies/broad-policy"
check_email_policy_payload "$(payload_path "${create_policy_tmp}/payloads" "POST" "/accounts/acc123/access/apps/app123/policies")"

echo "setup-cloudflare regression tests passed"
