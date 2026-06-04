# Publishing notes (Cursor Pocket)

This app is a **community client** for Cursor’s Cloud Agents API. It is **not** an official Cursor product.

## App Store positioning

- **Display name:** Cursor Pocket (or a neutral name without “Cursor” if Apple review requires it — see legal below)
- **Subtitle:** Cloud agents on your phone
- **Category:** Developer Tools or Productivity
- **Description:** Emphasize unofficial status, API key, and billing on the user’s Cursor plan

## Legal / branding

- State clearly: *Not affiliated with Cursor, Inc. / Anysphere.*
- Do not use Cursor logos or trademarks in a way that implies endorsement.
- Link to official docs: https://cursor.com/docs/cloud-agent/api/endpoints

## Technical checklist

- [ ] App icon (1024×1024) — replace placeholder in `CursorPocket/Resources/Assets.xcassets/AppIcon.appiconset`
- [ ] Privacy policy URL (API key in Keychain; network calls to `api.cursor.com`)
- [ ] TestFlight with real API keys on device
- [ ] Account deletion / sign-out (Settings → Sign out clears Keychain)

## Screenshots (suggested)

1. Agent list
2. Streaming chat
3. Settings (chat-only vs repo mode)
4. API key onboarding

## Support

Point users to GitHub Issues on `hourdays/cursor-pocket` and Slack `#cursor-pocket` for team handoff.
