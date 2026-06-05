# Cursor Pocket — roadmap

## Shipped

### v0.1 — iOS

- [x] SwiftUI shell + XcodeGen project
- [x] Cloud Agents API v1 client (`/v1/agents`, runs, SSE stream)
- [x] API key in Keychain
- [x] Agent list + new chat + follow-up messages
- [x] Chat-only mode (no repo) vs optional GitHub repo URL + branch

### v0.2 — Web-first loop

- [x] `shared/api/` TypeScript client + types (parity contract with Swift)
- [x] `web/` PWA: connect → idea → stream → chat
- [x] CI: `npm run build` on PR/push
- [x] GitHub Pages deploy workflow (live after merge to `main`)
- [x] Agent history (load runs when reopening sidebar chat)
- [x] Markdown rendering in assistant bubbles
- [ ] Show PR/branch from run `git` payload in UI

### v0.3 — Chat MVP (next)

- [ ] Loop B: PR links + “attach repo” UX
- [ ] iOS parity pass for history + markdown

## Next (both surfaces)

1. **Frictionless account** — OAuth if Cursor adds it; until then, polished API-key onboarding
2. **Repo onboarding UX** — GitHub connection flow, pick repo from list
3. **Remember last repo** — default repo in Settings
4. **Images in prompts** — `prompt.images` upload
5. **Push notifications** — run finished (webhooks when available)
6. **Polish** — markdown rendering, tool-call cards in stream, dark mode

## Product principles

- **Web-first development** — ship and test in the browser; port behavior to iOS on Mac
- Repo required only when the agent must **modify code** in Git
- **Chat without repo** should feel first-class, not like a broken state
- Billing stays on the user’s **Cursor subscription** (API key), not IAP in this app

## Links

- Repo: https://github.com/hourdays/cursor-pocket
- Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- API: https://cursor.com/docs/cloud-agent/api/endpoints
- Handoff: Slack `#cursor-pocket`
