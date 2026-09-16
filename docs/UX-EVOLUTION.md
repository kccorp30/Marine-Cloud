# KCC UX evolution — cinematic command center checkpoint

This is a progressive implementation on the existing project. It focuses the shared visual language on the supplied cinematic KCC references while preserving the existing data and authorization architecture. It is not a claim that every reference screen or the full brief is complete.

## Audit findings

- The customer email warning combined recipient, sender and provider failures. It could mention a missing customer email when only the sender was disabled.
- Member deactivation discarded RPC errors; the UI could appear inert.
- Work-order and vessel creation dominated their index screens.
- Estimates used non-responsive amount columns and were vulnerable to browser translation expanding currency text.
- The email preview and delivery used a generic communication template rather than a dedicated estimate document.
- The company-logo RPC exists in the included branding migration. The reported production error indicates that the deployed database does not expose the expected function; no permissions were weakened to work around it.
- Phone images above 2 MB were rejected before resizing. The client now resizes oversized browser-decodable images before invoking the same server validation.

## Implemented in this checkpoint

- Shared native-dialog drawer with modal focus handling, Escape support and restrained motion; profile/portrait/contact primitives, operational surface tokens, transparent command strips and responsive glass surfaces.
- Company summary becomes a shared metric rail; related sections use lighter dividers instead of repeated framed panels.
- Customer detail introduces identity, contact actions, customer-since date and contextual estimate/work-order links.
- Team profile presentation and explicit deactivation confirmation with actual RPC errors.
- Three-step work-order flow: customer/vessel, service/priority, review/create. Vessel choices are filtered by customer. Existing persistence is reused; assignment and scheduling remain in the order detail.
- Vessel creation moves into a drawer; existing vessel records remain visible.
- Assigned technician portraits added to the order detail for authorized viewers.
- Responsive estimate document with company identity, item quantities, totals, validity and protected currency text.
- Dedicated HTML estimate email shared by preview and initial send, with a premium portal summary, escaped service names, real total and a sign-in/create-access CTA. The full line-item estimate is intentionally kept inside the authenticated portal; the template remains email-compatible HTML rather than JavaScript animation.
- Sender/readiness errors now identify the missing dependency instead of a combined generic message.
- Payment-method shortcuts only for configured manual methods, with actual instructions in drawers.
- Notification bell inbox and per-notification detail drawers, confirmed read/acknowledge results and supported record links.
- Customer home exposes location-sharing status; location panels remain based on the existing authorized tracking RPC. No route or ETA is fabricated.
- Luz gets a restrained blue core treatment and a real estimate-copy assistant that uses the existing protected professional translation action; it cannot send or mutate an estimate autonomously.
- The three included production migrations are now applied and verified. Provider calls to customers still require a verified sender domain and configured Resend credentials.

## Routes to review

`/company`, `/customers/[id]`, `/team`, `/team/[profileId]`, `/work-orders`, `/work-orders/[id]`, `/customer`, `/estimates/[id]`, `/notifications`, `/vessels`, `/vessels/[id]`, `/company-settings`, `/welcome`.

## Remaining P0/P1

- P0: Verify email sender/provider configuration and a real preview → send → sign in → estimate approval flow with separate accounts. Code now blocks sending until the provider is actually verified; no real mail delivery or browser-authenticated end-to-end test was executed here.
- P1: Full visual parity with the three supplied references is not certified. Vessel imagery/hotspots, complete mission composition, customer relationship timeline, search/autocomplete and multi-stage assignment/scheduling creation remain incomplete.
- P1: Legacy secondary views and several dynamic/server error messages still require full dictionary coverage. Browser translation should not be used as a replacement for app localization.
- P1: Logo images stored as data URLs cannot be used reliably in email clients. Email logos render only when the configured source is HTTPS; company text branding remains available.
- P1: Browser-decodable image compression is implemented. HEIC conversion, camera compatibility and mobile upload behavior still require device validation.
- P1: No new routing provider, autonomous Luz actions, certification data, loyalty points, health scores or online presence was invented.
