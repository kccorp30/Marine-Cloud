# Company owner activation hotfix

Fixed a production auth-routing bug where invite confirmation received an absolute `next` URL.
`/auth/confirm` intentionally accepts only internal paths, so it rejected the absolute URL and fell back to `/dashboard`, skipping `/accept-invite` and therefore `accept_invitation()`.

Effects fixed:
- invited owner authenticated but had no active organization membership
- empty sidebar/navigation
- placeholder dashboard instead of company operations
- password login defaulted to `/dashboard` instead of role-aware `/`
- old fallback sender domain updated to `kccorpglobal.com`
- login copy no longer explains internal role-recognition behavior
