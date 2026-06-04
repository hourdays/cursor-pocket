# Cursor Pocket

Unofficial SwiftUI iOS client for [Cursor Cloud Agents API v1](https://cursor.com/docs/cloud-agent/api/endpoints) — ChatGPT-style chat UI with streaming replies, powered by your Cursor API key and subscription.

**Not affiliated with Cursor or Anysphere.**

## Features

- Chat with Cloud Agents from iPhone or iPad
- Streaming assistant replies (SSE)
- API key stored in the iOS Keychain
- **Chat-only mode** — Q&A without attaching a GitHub repo
- Optional GitHub repo URL + branch for coding agents
- Open the agent in Safari (`cursor.com/agents/...`)

## Requirements

- iOS 17+
- Xcode 15+ (on Mac)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- A [Cursor API key](https://cursor.com/dashboard) (user-scoped)

## Setup

```bash
git clone https://github.com/hourdays/cursor-pocket.git
cd cursor-pocket
brew install xcodegen
xcodegen generate
open CursorPocket.xcodeproj
```

In Xcode, select your Apple Developer team, then run on a simulator or device.

## First run

1. Paste your Cursor API key when prompted.
2. In **Settings**, choose **Chat-only mode** (default) or enter a GitHub repo URL + branch.
3. Tap **New chat** and send a message.

## Project layout

```
cursor-pocket/
├── CursorPocket/          # SwiftUI app source
├── project.yml            # XcodeGen spec
├── README.md
├── LICENSE
├── PUBLISH.md             # App Store notes (optional)
└── ROADMAP.md
```

## API reference

- [Cloud Agents API endpoints](https://cursor.com/docs/cloud-agent/api/endpoints)
- [Web agents](https://cursor.com/agents) (official, works in Safari today)

## Roadmap

See [ROADMAP.md](ROADMAP.md).

## License

MIT — see [LICENSE](LICENSE).
