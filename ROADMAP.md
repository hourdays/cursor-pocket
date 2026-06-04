# Cursor Pocket — roadmap

## Shipped in v0.1

- [x] SwiftUI shell + XcodeGen project
- [x] Cloud Agents API v1 client (`/v1/agents`, runs, SSE stream)
- [x] API key in Keychain
- [x] Agent list + new chat + follow-up messages
- [x] Chat-only mode (no repo) vs optional GitHub repo URL + branch

## Next

1. **Repo onboarding UX** — GitHub connection flow, pick repo from list (API/repos endpoint when available)
2. **Remember last repo** — default repo in Settings
3. **Sandbox repo template** — optional empty repo for coding tasks
4. **Images in prompts** — `prompt.images` upload
5. **Push notifications** — run finished (webhooks v1 when available)
6. **Polish** — markdown rendering, tool-call cards in stream, dark mode tuning

## Product principles

- Repo required only when the agent must **modify code** in Git
- **Chat without repo** should feel first-class, not like a broken state
- Billing stays on the user’s **Cursor subscription** (API key), not IAP in this app

## Links

- Repo: https://github.com/hourdays/cursor-pocket
- API: https://cursor.com/docs/cloud-agent/api/endpoints
- Handoff: Slack `#cursor-pocket`
