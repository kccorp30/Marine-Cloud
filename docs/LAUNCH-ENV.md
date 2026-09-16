# Operational launch configuration

The code ships with the provider integrations disabled until these values are configured in the existing deployment environment:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY
RESEND_API_KEY
RESEND_WEBHOOK_SECRET
RESEND_INBOUND_DOMAIN
LUZ_FOLLOWUPS_ENABLED=true
CRON_SECRET
```

The sender domain must be verified in Resend and in KCC Admin → company → email setup. The inbound domain is used for customer replies such as `reply+<conversation-id>@<inbound-domain>`; the webhook validates that address before recording a reply. Schedule `GET /api/cron/luz-followups` with the `CRON_SECRET` header. The route claims a small batch, sends HTML follow-ups and stops a sequence when the estimate is approved, expired, changed, bounced or answered.

Stripe remains paused. The fixed monthly company charge uses the existing active operational subscription record and is collected manually from KCC Admin until paid plans are resumed.

Do not enable Luz follow-ups before applying the two operational migrations and configuring the Resend webhook. No production migration or provider setting was changed during this review.
