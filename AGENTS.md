# Cursor Pocket — agent notes

Unofficial SwiftUI iOS client for the [Cursor Cloud Agents API](https://cursor.com/docs/cloud-agent/api/endpoints). There is no backend in this repo; the app talks to `https://api.cursor.com/v1` at runtime.

## Cursor Cloud specific instructions

### Platform limits (read this first)

This is an **iOS-only** Xcode project. Cloud Agent VMs are **Linux** and **cannot** run Xcode, the iOS Simulator, or `xcodebuild`. Treat Linux setup as **source + API validation**; full app run requires a **Mac with Xcode 15+**.

| Task | Linux cloud VM | macOS (local) |
|------|----------------|---------------|
| Edit Swift sources | Yes | Yes |
| `xcodegen generate` | Unreliable (XcodeGen may segfault on Linux Foundation) | `brew install xcodegen && xcodegen generate` |
| Build / run app | No | Open `CursorPocket.xcodeproj`, ⌘R on simulator/device |
| Unit tests | None configured (`testTargets: []` in `project.yml`) | Add test target in Xcode if needed |
| Lint | Not configured (no SwiftLint / CI) | Optional: add SwiftLint locally |

Generated `*.xcodeproj` is gitignored; regenerate on Mac after cloning.

### Services

| Service | Required? | Notes |
|---------|-----------|--------|
| **Cursor Cloud Agents API** (`api.cursor.com`) | Yes (for real chats) | Bearer token = [Cursor API key](https://cursor.com/dashboard) |
| **GitHub repo** | Optional | Only when chat-only mode is off in app settings |
| Local servers / Docker | N/A | Not used |

### Linux VM: quick validation

After the update script runs, verify the tree and API reachability:

```bash
cd /workspace
python3 << 'PY'
import os, yaml
spec = yaml.safe_load(open("project.yml"))
assert os.path.isdir("CursorPocket"), "missing CursorPocket/"
swift = []
for root, _, files in os.walk("CursorPocket"):
    for f in files:
        if f.endswith(".swift"):
            swift.append(os.path.join(root, f))
print(f"OK: {spec['name']}, {len(swift)} Swift files")
PY

# Expect HTTP 401 without a key (proves network + API host)
curl -sS -o /dev/null -w "GET /v1/me -> %{http_code}\n" \
  https://api.cursor.com/v1/me -H "Accept: application/json"
```

### API smoke test (same auth as the app)

The app uses `Authorization: Bearer <api_key>` (see `CloudAgentsClient.swift`). With a key in the environment:

```bash
export CURSOR_API_KEY="key_..."   # user secret — do not commit

curl -sS https://api.cursor.com/v1/me \
  -H "Authorization: Bearer $CURSOR_API_KEY" \
  -H "Accept: application/json" | python3 -m json.tool

curl -sS "https://api.cursor.com/v1/agents?limit=5" \
  -H "Authorization: Bearer $CURSOR_API_KEY" \
  -H "Accept: application/json" | python3 -m json.tool
```

Chat-only agent creation (matches default app settings):

```bash
curl -sS https://api.cursor.com/v1/agents \
  -H "Authorization: Bearer $CURSOR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"prompt":{"text":"Say hello in one sentence."},"env":{"type":"cloud"}}' \
  | python3 -m json.tool
```

### macOS: build and run (authoritative)

From `README.md`:

```bash
brew install xcodegen
xcodegen generate
open CursorPocket.xcodeproj
```

In Xcode: set your Apple Developer team, choose a simulator, Run (⌘R). On first launch, paste your Cursor API key; use **New chat** to exercise the core flow.

### Optional toolchain on Linux

If Swift is installed under `/opt/swift-6.0.3-RELEASE-ubuntu24.04`, ensure `PATH` includes `/opt/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin`. XcodeGen can be built from source on Linux but is **not** required for day-to-day edits and is **not** reliable for `xcodegen generate` on Linux today.

### Secrets

Never commit API keys. Use VM secrets / environment variable `CURSOR_API_KEY` for API smoke tests in cloud sessions.
