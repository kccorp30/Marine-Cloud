# Marine Cloud auth production fix

This patch fixes the two pilot blockers observed on 2026-09-13:

1. Invitation/auth links could resolve to `localhost:3000`.
2. Passwordless login and invite delivery depended on Supabase's mailer/SMTP path and could show `Error sending confirmation email`.

## Production environment

Vercel must contain:

```text
NEXT_PUBLIC_SITE_URL=https://marine-cloud.vercel.app
AUTH_FROM_EMAIL=KCC Marine Cloud <notifications@kccorptecnology.com>
RESEND_API_KEY=<server-only Resend API key>
```

`AUTH_FROM_EMAIL` must use a sender under the verified Resend domain.

## Supabase URL configuration

In Supabase Dashboard → Authentication → URL Configuration:

- Site URL: `https://marine-cloud.vercel.app`
- Redirect URL: `https://marine-cloud.vercel.app/**`

Keep localhost redirects only for local development if needed.

## New auth flow

- Team invite: application creates the organization invitation token.
- Server uses `auth.admin.generateLink()` to create the Supabase Auth invite/magic token without asking Supabase to send email.
- Marine Cloud sends the branded HTML email through Resend API.
- Email points to `/auth/confirm` on the production domain.
- `/auth/confirm` exchanges `token_hash` through `verifyOtp()` and writes the Supabase session cookie.
- `/accept-invite` consumes the organization invitation token and activates the membership.
- New users are sent to create a password before entering their role dashboard.
- Existing users go directly to their authorized dashboard.

The public “Send sign-in link” and password recovery flows also generate links server-side and use Resend directly. They do not auto-create arbitrary accounts from the login screen.
