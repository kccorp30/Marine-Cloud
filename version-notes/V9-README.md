# KCC Marine Cloud V9 — Auth + First-Run UX

This package is the supplied V8 project with the invitation/password regression fixed and the first-run experience redesigned.

## Before running

1. Install dependencies: `npm install`
2. Apply **one** migration track used by your deployment:
   - production Supabase CLI: `supabase/migrations/20260915174500_auth_credentials_and_invites.sql`
   - legacy/manual sequence: `migrations/273_password_credentials_and_customer_invites.sql`
3. Confirm these environment variables are configured:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `RESEND_API_KEY`
   - `AUTH_FROM_EMAIL`
   - `NEXT_PUBLIC_SITE_URL`
4. Run `npm run typecheck`, `npm test`, and `npm run build` in your normal development environment.
5. Follow `docs/V9_AUTH_UX_RELEASE_NOTES.md` for the staging smoke-test sequence.

## Durable access rule

Invitation = one-time activation.

Future access for company users, technicians, customers, and KCC admins = **email + password**.

Public magic-link sign-in is disabled.
