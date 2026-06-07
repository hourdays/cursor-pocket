#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_CURL="${TMP_DIR}/curl"
CURL_LOG="${TMP_DIR}/curl.log"
STATE="${TMP_DIR}/state.json"
export CURL_LOG
export FAKE_STATE="${STATE}"

python3 - "$STATE" <<'PY'
import json
import sys

state_path = sys.argv[1]
state = {
    "policies": [
        {
            "id": "bypass-all",
            "name": "Unsafe bypass",
            "decision": "bypass",
            "precedence": 1,
            "include": [{"everyone": {}}],
        },
        {
            "id": "team-domain",
            "name": "Whole domain",
            "decision": "allow",
            "precedence": 2,
            "include": [{"email_domain": {"domain": "example.com"}}],
        },
    ]
}
with open(state_path, "w", encoding="utf-8") as f:
    json.dump(state, f)
PY

cat > "$FAKE_CURL" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys
from urllib.parse import urlsplit


def load_state():
    with open(os.environ["FAKE_STATE"], encoding="utf-8") as f:
        return json.load(f)


def save_state(state):
    with open(os.environ["FAKE_STATE"], "w", encoding="utf-8") as f:
        json.dump(state, f)


def emit(payload):
    print(json.dumps(payload))


args = sys.argv[1:]
method = "GET"
data = None
url = None
i = 0
while i < len(args):
    arg = args[i]
    if arg == "-X":
        method = args[i + 1]
        i += 2
    elif arg == "-d":
        data = args[i + 1]
        i += 2
    elif arg.startswith("http"):
        url = arg
        i += 1
    else:
        i += 1

if not url:
    emit({"success": False, "errors": [{"message": "missing url"}]})
    sys.exit(0)

parsed = urlsplit(url)
path = parsed.path.split("/client/v4", 1)[1]
if parsed.query:
    path = f"{path}?{parsed.query}"

with open(os.environ["CURL_LOG"], "a", encoding="utf-8") as f:
    f.write(json.dumps({
        "method": method,
        "path": path,
        "data": json.loads(data) if data else None,
    }) + "\n")

if method == "GET" and path == "/user/tokens/verify":
    emit({"success": True, "result": {"status": "active"}})
elif method == "GET" and path == "/accounts/acct/access/apps?per_page=50":
    emit({
        "success": True,
        "result": [{"id": "app-1", "domain": "cursor-pocket.pages.dev"}],
        "result_info": {"total_pages": 1, "total_count": 1},
    })
elif method == "GET" and path == "/accounts/acct/access/apps/app-1/policies?per_page=50&page=1":
    state = load_state()
    emit({
        "success": True,
        "result": state["policies"],
        "result_info": {
            "page": 1,
            "per_page": 50,
            "total_pages": 1,
            "total_count": len(state["policies"]),
        },
    })
elif method == "DELETE" and path.startswith("/accounts/acct/access/apps/app-1/policies/"):
    policy_id = path.rsplit("/", 1)[1]
    state = load_state()
    state["policies"] = [p for p in state["policies"] if p.get("id") != policy_id]
    save_state(state)
    emit({"success": True, "result": {"id": policy_id}})
elif method == "POST" and path == "/accounts/acct/access/apps/app-1/policies":
    state = load_state()
    policy = json.loads(data)
    policy["id"] = "email-only"
    state["policies"].append(policy)
    save_state(state)
    emit({"success": True, "result": policy})
else:
    emit({"success": False, "errors": [{"message": f"unexpected {method} {path}"}]})
PY
chmod +x "$FAKE_CURL"

OUTPUT="${TMP_DIR}/output.txt"
PATH="${TMP_DIR}:${PATH}" \
  CLOUDFLARE_API_TOKEN="test-token" \
  CLOUDFLARE_ACCOUNT_ID="acct" \
  POCKET_ALLOWED_EMAIL="owner@example.com" \
  bash "${ROOT}/scripts/setup-cloudflare.sh" > "$OUTPUT"

python3 - "$STATE" "$CURL_LOG" "$OUTPUT" <<'PY'
import json
import sys

state_path, log_path, output_path = sys.argv[1:4]
with open(state_path, encoding="utf-8") as f:
    state = json.load(f)
with open(log_path, encoding="utf-8") as f:
    calls = [json.loads(line) for line in f]
with open(output_path, encoding="utf-8") as f:
    output = f.read()

expected_policy = {
    "name": "Only allowed email",
    "decision": "allow",
    "precedence": 1,
    "include": [{"email": {"email": "owner@example.com"}}],
    "id": "email-only",
}

if state["policies"] != [expected_policy]:
    raise SystemExit(f"unexpected final policies: {json.dumps(state['policies'], indent=2)}")

delete_paths = {call["path"] for call in calls if call["method"] == "DELETE"}
expected_deletes = {
    "/accounts/acct/access/apps/app-1/policies/bypass-all",
    "/accounts/acct/access/apps/app-1/policies/team-domain",
}
if delete_paths != expected_deletes:
    raise SystemExit(f"unexpected delete calls: {sorted(delete_paths)}")

post_calls = [
    call for call in calls
    if call["method"] == "POST" and call["path"] == "/accounts/acct/access/apps/app-1/policies"
]
if len(post_calls) != 1 or post_calls[0]["data"] != {
    "name": "Only allowed email",
    "decision": "allow",
    "precedence": 1,
    "include": [{"email": {"email": "owner@example.com"}}],
}:
    raise SystemExit(f"unexpected policy create call: {post_calls}")

if "Policies replaced" not in output or "Cloudflare Access configured" not in output:
    raise SystemExit(output)
PY

echo "setup-cloudflare existing-app policy replacement test passed"
