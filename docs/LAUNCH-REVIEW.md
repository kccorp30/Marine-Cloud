# KCC Marine Cloud — operational launch review

Status: NOT PRODUCTION READY pending deployment verification. This is a reviewable implementation on the existing repository, not a new application.

## Implemented

- Shared cinematic hero, clean original marine background, reusable metrics, measured motion, semantic timeline, skeleton and error surfaces.
- Rebuilt KCC admin, company, technician and customer landing pages using existing operational queries. Removed arbitrary metric progress and fake online labels from these pages.
- English/Spanish dictionaries for the four home screens and navigation; shared translations for selected technician, customer tracking, company setup and estimate controls. Some older secondary screens and dynamic messages still require translation.
- Real work-order title search under the logged-in user's RLS; company filter for non-admins.
- Profile setup with name, phone, language and optional photo. Resized WebP avatar saved through the existing profile row. Active organization is checked server-side before saving the selected workspace.
- Invitation retains password-setup information across login. Welcome preserves the invited company context. No role selector.
- Company logo upload, validated and resized server-side, via a narrowly authorized RPC. Payment preferences reuse existing company settings.
- Operational access without subscription billing: dedicated private plan with explicit module entitlements, complimentary status, no trial expiry or manufactured payment. Only KCC admin can grant it, and suspended companies are not reactivated. New company creation uses the same configuration while billing is paused.
- Technician agenda uses company timezone and distinguishes today's appointments from active assignments.
- Luz day briefing and in-order checklist guidance. Buttons open evidence and notes, point to actual pending checklist items, and use the existing assistance request flow. These are deterministic operational tools; a general autonomous AI agent has not been implemented.
- Notification rules for assignment and rescheduling reuse the existing notification engine and acknowledgement support.
- Customer tracking displays recorded status changes and the actual current state. No inferred completion percentage. Existing tracking/location tools remain on work-order detail.
- Branded HTML operational emails with an authenticated customer portal link and escaped content. Existing send workflow remains; sending an estimate and emailing it are still separate actions. First-time customer invitation is not automatically sent by this change.
- Estimate delivery now has a server-backed preview, one action to publish and send, visible send readiness, reply-to routing and idempotent provider delivery. Customer detail shows estimates, work-order progress, invoices and a conversation entry point together.
- Customer and technician records use photo-led operational cards. Assistance requests are expandable and expose the available call and WhatsApp actions. The service tracking panel embeds an OpenStreetMap view when coordinates exist and keeps recorded timestamps visible.
- Technician access is gated by a persisted workday clock. A company owner/admin can configure pay type, rate, currency and pay cycle; closed shifts retain the rate snapshot used to calculate gross pay. A finance view reports collections, refunds, expenses and technician payroll by currency, with a clear cash-summary disclaimer.
- KCC Admin can set a fixed monthly launch charge against the existing operational subscription record and record a manual payment while Stripe plans remain paused.
- Luz now has an operational follow-up queue for unapproved estimates. Follow-ups can be scheduled or stopped; the service claim function stops on approval, expiry, estimate changes, bounce or customer reply. The cron route sends only when the provider and inbound reply domain are configured.
- PWA install support, offline fallback and a visible add-to-home action are included in the shared shell.
- Customer-linking RPC derives identity from auth.uid() and the verified email. Requires an active customer membership and exactly one matching customer record in the company. Ambiguous matches remain pending for staff resolution.

## Database verification performed

Read-only checks against the repository's actual Supabase project:
- One existing account has both kcc_admin and technician memberships. Its global access is expected and cannot be used as a test of technician-only permissions.
- Separate technician, company_admin and customer identities each returned is_kcc_admin=false, one visible company, zero foreign companies under authenticated RLS.
- These checks cover company visibility only, not every operational mutation.
- No production memberships, subscriptions or company status were changed. The new migration has not been deployed.

## Deployment steps

1. Merge the source changes into the existing application repository.
2. Apply `supabase/migrations/20260914221041_command_center_branding.sql`, `supabase/migrations/20260915115136_operational_journeys.sql` and `supabase/migrations/20260915120005_luz_followups_and_manual_billing.sql` after the existing migrations. Do not replay the entire legacy migrations directory on an existing database.
3. Keep `NEXT_PUBLIC_PLATFORM_BILLING_ENABLED` unset (or not equal to `true`) for the operational launch. This UI switch does not bypass database authorization.
4. Configure the Resend sender/domain, inbound reply domain, webhook secret, `LUZ_FOLLOWUPS_ENABLED`, `CRON_SECRET` and the existing Supabase environment. Run `npm ci`, `npm run typecheck`, `npm test`, `npm run build`.
5. From KCC admin → Companies, choose the intended company and enable operational access without subscription. Existing subscriptions are not altered automatically.
6. Verify with separate real accounts: invitation → password → profile → company/technician/customer; create and assign an order; notification acknowledgement; evidence; approval; QC; invoice and manual payment.

## Remaining P0/P1

- P0: Deploy and validate the three new migrations and the notification rules; complete an end-to-end run with real role-specific accounts before the waiting company starts work.
- P1: Full visual comparison at every required viewport is not certified yet; browser QA results are recorded separately if available.
- P1: Finish translations and visual consistency in legacy secondary pages, modal text, validation errors and dynamic notification content.
- P1: Combine estimate delivery with first-time customer activation; the current delivery adds a portal CTA but does not automatically create/invite a customer account.
- P1: Complete company onboarding as a saved multi-step flow and vessel-photo management. Current company setup reuses the settings page, not a required wizard.
- P1: Luz's follow-up automation is deterministic and guarded by provider configuration. A general contextual AI conversation, autonomous tools and out-of-app push delivery require further implementation and verification.

No claim is made that Stripe, paid memberships, AI autonomy, GPS routes or ETA have been newly enabled.
