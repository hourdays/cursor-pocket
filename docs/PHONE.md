# Test Cursor Pocket on your phone

## What you get

A **personal web app** at a public URL, locked to **your Cursor account email** (via API key + allowlist). Install to Home Screen on iPhone — works like an app.

## One-time setup (repo admin)

### 1. Lock to your email

In GitHub: **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Value |
|--------|--------|
| `POCKET_ALLOWED_EMAIL` | Your Cursor account email (same as [dashboard](https://cursor.com/dashboard) / `GET /v1/me`) |

Only that email’s API key can connect on the deployed site. Local `npm run dev` has no lock unless you set `VITE_ALLOWED_EMAIL` in `web/.env.local`.

### 2. Enable GitHub Pages

**Settings → Pages → Build and deployment → Source:** `GitHub Actions`

Then run **Actions → Deploy web to GitHub Pages** (or push to `main`).

### 3. URL

https://hourdays.github.io/cursor-pocket/

## On your iPhone

1. Open the URL in **Safari** (not Chrome — Add to Home Screen works best in Safari).
2. **Share → Add to Home Screen** → name it “Pocket”.
3. Open Pocket from your home screen.
4. Paste your [Cursor API key](https://cursor.com/dashboard).
5. Chat — billed to your Cursor subscription.

## Security notes

- API key stays in **this browser only** (localStorage).
- Email allowlist is enforced after `GET /v1/me` on connect and on every reload.
- The deployed site is HTTPS. Do not share your API key.
- For stronger isolation later: Cloudflare Access or a private repo + VPN.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| 404 on URL | Enable Pages (step 2) and wait for deploy workflow to finish |
| “This Pocket site is private” | Use the API key for the email in `POCKET_ALLOWED_EMAIL` |
| Can’t install to Home Screen | Use Safari; open the GitHub Pages URL directly |
