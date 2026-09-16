# KCC Marine Cloud — V9 Auth & First-Run UX

## Scope

This release fixes the invitation/password regression and makes email + password the durable sign-in method for every operational role after first activation:

- KCC admin
- company owner
- company admin
- manager
- technician
- customer

An invitation is now only a one-time identity/bootstrap mechanism. It is not the permanent sign-in method.

## Root causes fixed

1. **Company creation created a DB invitation but did not deliver it.** `createOrganizationAction()` completed the SQL transaction, but the owner invitation created by `invite_team_member()` never entered the Resend delivery pipeline.
2. **Password setup was inferred from `email_confirmed_at`.** A Supabase user can be confirmed without ever establishing a password, especially after a previous invite/magic-link path. V9 records durable password state in `profiles.password_set_at` instead.
3. **Public passwordless login remained available.** The public magic-link endpoint is now disabled. Regular access is email + password.
4. **Customer invitation was inconsistent with DB role validation.** `organization_invitations` and `invite_team_member()` now explicitly support `customer`.
5. **Invitation delivery paths were duplicated.** Company-owner creation, team invite, resend, estimate/customer activation, and direct customer portal activation now use one centralized secure link + Resend pipeline.
6. **Email provider configuration failures could throw outside the intended failure path.** Invitation/recovery delivery now fails gracefully and leaves the pending invite usable for resend.
7. **First-run routing was inconsistent.** Role routing is centralized and the first-run flow is now Invitation → Password → Profile → correct workspace.

## Final authentication flow

### New company owner / manager / technician / customer

1. Authorized operator creates or invites the user.
2. Marine Cloud creates or refreshes one pending invitation.
3. Server generates a Supabase one-time identity link.
4. Resend delivers the branded activation email.
5. User opens the secure link.
6. `/auth/confirm` verifies the Supabase token and establishes the session.
7. `/accept-invite` binds the invitation to the authenticated email and activates the membership.
8. If no durable password state exists, the user is forced through **Create password**.
9. The user completes the visual first-run profile step.
10. Marine Cloud opens the correct workspace:
   - KCC admin → `/dashboard`
   - company owner/admin/manager → `/company`
   - technician → `/today`
   - customer → `/customer`
11. Every later sign-in is email + password from `/login`.

### Existing account invited to another organization

The existing identity is reused. No duplicate `auth.users` record is created. The invitation is accepted for the new organization and the existing email + password remains the durable credential.

### Existing pre-V9 account

V9 intentionally does **not** guess whether a confirmed account has a password. If an existing user successfully signs in with a password, `password_set_at` is recorded automatically. If an already-authenticated legacy session has no durable password record, it is asked to set one once before entering an operational panel.

## Customer access

Company staff can now enable portal access directly from the customer detail page. The customer receives the same secure first-run experience and then uses email + password for future visits. This no longer depends on an estimate being sent first.

## Invitation delivery guarantees

- External Resend calls remain outside SQL transactions.
- If company creation succeeds but email delivery fails, the company stays created.
- The pending invitation stays valid and can be resent.
- Resending refreshes the pending invitation instead of creating duplicate pending invitations.
- UI never claims “sent” unless the email provider accepts the message.
- An emergency manual link, when shown after delivery failure, is the complete secure confirmation URL — never a bare invitation token.

## Database migration

Apply the timestamped production migration:

`supabase/migrations/20260915174500_auth_credentials_and_invites.sql`

A mirrored legacy migration is also included:

`migrations/273_password_credentials_and_customer_invites.sql`

The migration:

- adds `profiles.password_set_at timestamptz`
- allows `customer` invitations
- revokes duplicate pending invitation rows before enforcement
- adds a partial unique index for one pending `(organization, email, role)` invitation
- replaces `invite_team_member()` with an idempotent/reissue-aware implementation

Do not apply both migration tracks to the same database if your deployment process already uses only one migration directory.

## UX / visual changes

The access experience was redesigned to match the KCC premium marine direction:

- cinematic dark marine first-run shell
- layered glass surfaces and restrained glow
- Invitation → Password → Profile visual progress
- password strength feedback
- premium animated primary actions
- refined focus/hover/press microinteractions
- animated status and success states
- reduced-motion accessibility fallback
- upgraded global `.kcc-action` buttons with light sweep, depth, focus ring, and tactile press state
- more explicit invitation delivery/resend feedback
- direct customer portal activation UI

No new animation dependency was added; the motion layer uses CSS so this auth release does not enlarge the runtime bundle or alter the application architecture.

## Important security behavior preserved

- Supabase Auth remains identity/session authority.
- RLS and tenant isolation are unchanged.
- `accept_invitation()` still binds invitation email to `auth.uid()` and rejects the wrong account.
- Service-role access remains server-only.
- Raw passwords are never sent to the credential-state API.
- Raw invitation tokens are not exposed in normal UI/logging.
- Public magic-link sign-in is disabled.
- Existing work-order state machine and operational data flows are untouched.

## Required environment variables

Production must provide:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `RESEND_API_KEY`
- `AUTH_FROM_EMAIL`
- `NEXT_PUBLIC_SITE_URL`

`NEXT_PUBLIC_SITE_URL` must be the real Marine Cloud origin so invitation and recovery links return to the correct application.

## Validation completed in this workspace

Completed:

- TypeScript syntax transpile scan across **245 TS/TSX source files**: passed.
- Static auth-surface check confirms the public login uses `signInWithPassword`.
- Static check confirms no `signInWithOtp` remains in `app`, `components`, or `lib`.
- Static check confirms every `(app)` operational panel is gated by `passwordSetupComplete` in the shared layout.
- Role destination helper checked for company, technician, customer, and KCC admin routes.

Not completed here:

- Full `npm install`, `npm run typecheck`, `npm test`, and `npm run build` could not be run because this execution environment did not have a complete dependency cache/network install available.
- Live Supabase/Resend end-to-end delivery cannot be validated without the production/staging environment variables and database.

Do not treat the static checks above as a substitute for deployment smoke tests.

## Manual smoke-test checklist before production

1. Apply the V9 database migration on staging.
2. Create a company with a brand-new owner email.
3. Confirm the owner email is actually received through Resend.
4. Open invite → accept → create password → complete profile → land on `/company`.
5. Sign out and sign back in manually using owner email + password.
6. Use Forgot password and set a new password.
7. Invite a manager; verify same first-run flow and `/company` destination.
8. Invite a technician; verify password creation and `/today` destination.
9. Enable portal access for a customer; verify password creation and `/customer` destination.
10. Invite an existing Marine Cloud account to a second organization; verify no duplicate auth user.
11. Resend a pending invitation; verify no duplicate pending invitation/member.
12. Temporarily use an invalid/missing Resend configuration on staging; verify company creation remains successful and UI reports delivery failure with resend path.
13. Verify expired/revoked invitation is rejected.
14. Verify a different authenticated email cannot consume somebody else’s invitation.
15. Verify an authenticated invite/recovery session without password state cannot enter any `(app)` operational panel until password setup is complete.
16. Verify mobile first-run screens and reduced-motion mode.

## Key files added

- `lib/auth/invitations.ts`
- `lib/auth/role-home.ts`
- `lib/customers/portal-actions.ts`
- `app/api/auth/credential-state/route.ts`
- `components/auth/AuthExperienceShell.tsx`
- `components/customers/CustomerPortalAccessButton.tsx`
- `components/team/ResendInvitationButton.tsx`
- `tests/auth-flow.test.ts`
- migrations listed above

## Version intent

This is a focused authentication + first-run UX hardening release on top of the supplied V8 project. It does not replace the existing Supabase/RLS architecture and does not fake operational data, GPS, ETA, revenue, vessel health, or other product capabilities.

## V9.1 hotfix — existing-account onboarding regression

A V9 route guard incorrectly treated `profiles.password_set_at IS NULL` as proof that an account had never created a password. Because the column was introduced in V9, every legacy account (including KCC admins) initially had NULL and could be redirected to first-time password setup.

V9.1 changes the invariant:

- First-time setup is **explicit**, via Supabase Auth metadata `password_setup_required=true` written only for newly provisioned invitation identities.
- Existing/legacy accounts are never forced into onboarding merely because a new database marker is NULL.
- Successful password setup/sign-in writes `password_setup_complete=true` and clears `password_setup_required`.
- `profiles.password_set_at` remains a best-effort marker only; its failure cannot invalidate a password Supabase already accepted.
- Login no longer signs a valid user back out if secondary credential-state persistence fails.
- Reset-password no longer reports a false activation failure after Supabase successfully changed the password.
- First-time password screen now provides an explicit "Sign in with email and password" escape path for users who already have an account.
