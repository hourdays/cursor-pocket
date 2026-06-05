# Test Cursor Pocket on your phone

## Recommended: Cloudflare Pages + Access

**Private URL, email login at the edge, install like an app.**

1. Follow **[docs/CLOUDFLARE_ACCESS.md](CLOUDFLARE_ACCESS.md)** (deploy + Access policy for your email)
2. Open your Pages URL in **Safari** (e.g. `https://cursor-pocket.pages.dev`)
3. Complete **Cloudflare Access** login (email PIN)
4. **Share → Add to Home Screen** → “Pocket”
5. Paste your [Cursor API key](https://cursor.com/dashboard) → chat

Billing stays on your Cursor subscription.

---

## Alternative: GitHub Pages (no edge login)

Simpler hosting; security is **app allowlist only** (weaker than Access).

### Setup

1. GitHub secret `POCKET_ALLOWED_EMAIL` = your Cursor email  
   [Settings → Secrets](https://github.com/hourdays/cursor-pocket/settings/secrets/actions)
2. **Settings → Pages → Source:** GitHub Actions  
3. Run [Deploy web to GitHub Pages](https://github.com/hourdays/cursor-pocket/actions/workflows/pages.yml)

**URL:** https://hourdays.github.io/cursor-pocket/

### iPhone

Safari → URL → Add to Home Screen → API key.

---

## Security comparison

| Method | Reachable on phone | Email-locked |
|--------|-------------------|--------------|
| **Cloudflare Access** | Yes | Yes — login before app loads |
| GitHub Pages + allowlist | Yes | Partial — API key must match email |
| Local `npm run dev` | Same Wi‑Fi only | Optional `.env.local` |

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| 404 | Enable hosting (Pages or Cloudflare workflow) |
| Access login loop | Clear cookies; check Access app domain matches URL |
| “This Pocket site is private” | API key must match `POCKET_ALLOWED_EMAIL` |
| Can’t Add to Home Screen | Use Safari on the final HTTPS URL |
