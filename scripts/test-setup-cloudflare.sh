#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

cat >"$TMPDIR/bin/curl" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys
from urllib.parse import urlparse

args = sys.argv[1:]
method = "GET"
data = ""
url = ""
i = 0
while i < len(args):
    arg = args[i]
    if arg == "-X":
        method = args[i + 1]
        i += 2
    elif arg == "-d":
        data = args[i + 1]
        i += 2
    elif arg == "-H":
        i += 2
    elif arg.startswith("-"):
        i += 1
    else:
        url = arg
        i += 1

parsed = urlparse(url)
path = parsed.path
if parsed.query:
    path += "?" + parsed.query

with open(os.environ["MOCK_LOG"], "a", encoding="utf-8") as log:
    log.write(f"{method} {path} {data}\n")

case = os.environ["MOCK_CASE"]

def ok(result):
    print(json.dumps({"success": True, "result": result}))

if path == "/client/v4/user/tokens/verify":
    ok({"status": "active"})
elif path == "/client/v4/accounts?per_page=5":
    ok([{"id": "acct"}])
elif path == "/client/v4/accounts/acct/access/apps?per_page=50":
    if case == "create":
        ok([])
    else:
        ok([{"id": "app-1", "domain": "cursor-pocket.pages.dev"}])
elif method == "POST" and path == "/client/v4/accounts/acct/access/apps":
    body = json.loads(data)
    assert body["domain"] == "cursor-pocket.pages.dev"
    assert body["policies"][0]["include"][0]["email"]["email"] == "person@example.com"
    ok({"id": "app-1"})
elif path == "/client/v4/accounts/acct/access/apps/app-1/policies?per_page=50":
    if case == "existing-broad":
        ok([
            {"id": "old-allow", "name": "Everyone", "decision": "allow"},
            {
                "id": "email-policy",
                "name": "Only allowed email",
                "decision": "allow",
                "include": [{"email": {"email": "old@example.com"}}],
            },
            {"id": "block-1", "name": "Blocked", "decision": "block"},
        ])
    else:
        ok([])
elif method == "PUT" and path == "/client/v4/accounts/acct/access/apps/app-1/policies/email-policy":
    body = json.loads(data)
    assert body["include"][0]["email"]["email"] == "person@example.com"
    ok({"id": "email-policy"})
elif method == "POST" and path == "/client/v4/accounts/acct/access/apps/app-1/policies":
    body = json.loads(data)
    assert body["include"][0]["email"]["email"] == "person@example.com"
    ok({"id": "email-policy"})
elif method == "DELETE" and path == "/client/v4/accounts/acct/access/apps/app-1/policies/old-allow":
    ok({"id": "old-allow"})
else:
    print(json.dumps({"success": False, "errors": [{"message": f"unexpected {method} {path}"}]}))
PY
chmod +x "$TMPDIR/bin/curl"

run_setup() {
  local case="$1"
  local log="$TMPDIR/${case}.log"
  : >"$log"
  PATH="$TMPDIR/bin:$PATH" \
    MOCK_CASE="$case" \
    MOCK_LOG="$log" \
    CLOUDFLARE_API_TOKEN="token" \
    POCKET_ALLOWED_EMAIL="person@example.com" \
    POCKET_DOMAIN="cursor-pocket.pages.dev" \
    "$ROOT_DIR/scripts/setup-cloudflare.sh" >/dev/null
  echo "$log"
}

create_log="$(run_setup create)"
grep -Fq "POST /client/v4/accounts/acct/access/apps " "$create_log"
grep -Fq "POST /client/v4/accounts/acct/access/apps/app-1/policies " "$create_log"

existing_log="$(run_setup existing-broad)"
grep -Fq "PUT /client/v4/accounts/acct/access/apps/app-1/policies/email-policy " "$existing_log"
grep -Fq "DELETE /client/v4/accounts/acct/access/apps/app-1/policies/old-allow " "$existing_log"
if grep -Fq "DELETE /client/v4/accounts/acct/access/apps/app-1/policies/block-1 " "$existing_log"; then
  echo "ERROR: blocking policies should not be deleted" >&2
  exit 1
fi

echo "setup-cloudflare tests passed"
