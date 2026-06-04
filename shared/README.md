# Shared API layer

TypeScript reference implementation of the **Cursor Cloud Agents API v1** client used by the web app.

The iOS app (`CursorPocket/`) mirrors the same behavior in Swift. When changing API usage, update **both**:

| Concern | Web | iOS |
|---------|-----|-----|
| Types | `shared/api/types.ts` | `CursorPocket/Models/` |
| HTTP + SSE | `shared/api/cloudAgentsClient.ts` | `CursorPocket/Services/CloudAgentsClient.swift` |
| Settings defaults | `DEFAULT_SETTINGS` | `AppSettings.default` |

Future: generate Swift from OpenAPI when Cursor publishes a stable schema.
