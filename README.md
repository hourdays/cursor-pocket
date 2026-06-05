# Cursor Pocket

Unofficial client for [Cursor Cloud Agents API v1](https://cursor.com/docs/cloud-agent/api/endpoints) — connect your Cursor account, describe an idea, and chat with streaming cloud agents.

**Not affiliated with Cursor or Anysphere.**

## Develop without a Mac (web-first)

The **web PWA** (`web/`) is the primary loop for testing API and UX in any browser. iOS (`CursorPocket/`) stays in parallel against the same API contract in `shared/api/`.

```bash
git clone https://github.com/hourdays/cursor-pocket.git
cd cursor-pocket/web
npm install
npm run dev
```

Open http://localhost:5173, paste your [Cursor API key](https://cursor.com/dashboard), and use **What do you want to build?** to start an agent. Usage is billed to your existing Cursor subscription.

**Live demo (after merge to `main`):** https://hourdays.github.io/cursor-pocket/

**UI demo (no API key):** `npm run dev` then open `http://localhost:5173/?demo=1` — scripted walkthrough for screenshots/video. See [docs/assets/cursor-pocket-demo.mp4](docs/assets/cursor-pocket-demo.mp4).

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full product loop and web ↔ iOS parity.

## Features

- Connect with Cursor API key (validates via `GET /v1/me`)
- Idea → new cloud agent → streamed assistant replies (SSE)
- Agent list, follow-up messages, cancel in-flight run
- **Chat-only mode** (default) — Q&A without a GitHub repo
- Optional GitHub repo URL + branch for coding agents
- Open agent in browser (`cursor.com/agents/...`)

| Surface | Status | How to run |
|---------|--------|------------|
| Web PWA | v0.2 | `cd web && npm run dev` |
| iOS app | v0.1 | Xcode on Mac (below) |

## iOS (Mac + Xcode)

### Requirements

- iOS 17+
- Xcode 15+ (on Mac)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- A [Cursor API key](https://cursor.com/dashboard)

### Setup

```bash
cd cursor-pocket
brew install xcodegen
xcodegen generate
open CursorPocket.xcodeproj
```

Select your Apple Developer team, then run on a simulator or device. API key is stored in the iOS Keychain.

## Project layout

```
cursor-pocket/
├── web/                 # Vite + React PWA (test anywhere)
├── shared/api/          # TypeScript API client + types (parity contract)
├── CursorPocket/        # SwiftUI iOS app
├── docs/ARCHITECTURE.md # Web-first loop, account model, parity
├── project.yml          # XcodeGen spec (iOS)
├── README.md
├── ROADMAP.md
└── LICENSE
```

## API reference

- [Cloud Agents API endpoints](https://cursor.com/docs/cloud-agent/api/endpoints)
- [Web agents](https://cursor.com/agents) (official, works in Safari today)

## Roadmap

See [ROADMAP.md](ROADMAP.md).

## License

MIT — see [LICENSE](LICENSE).
