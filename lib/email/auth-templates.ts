const LOGO_URL = 'https://marine-cloud.vercel.app/brand/kcc-marine-solutions.png';

/**
 * Shell base compartido por los 4 templates — nunca duplicar el
 * armazón HTML/table en cada uno. Table-based para compatibilidad
 * real con Outlook/Gmail, todo inline (sin <style> externo, sin JS).
 * El contenido crítico es HTML texto real, nunca una imagen única —
 * si el logo no carga, el email sigue siendo perfectamente legible y
 * usable (alt text real, la marca en texto queda de todas formas en
 * el header y footer).
 */
function emailShell(opts: { preheader: string; headline: string; bodyHtml: string; ctaLabel: string; ctaUrl: string; securityNote?: string }): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>KCC Marine Cloud</title>
</head>
<body style="margin:0;padding:0;background-color:#080C15;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <!-- Preheader oculto — texto de preview en la bandeja de entrada, nunca visible en el cuerpo -->
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;">${opts.preheader}</div>

  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#080C15;padding:32px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;">
          <!-- Logo -->
          <tr>
            <td align="center" style="padding-bottom:28px;">
              <img src="${LOGO_URL}" width="120" alt="KCC Marine Solutions" style="display:block;border:0;max-width:120px;height:auto;" />
            </td>
          </tr>

          <!-- Card -->
          <tr>
            <td style="background-color:#0D1220;border:1px solid rgba(201,162,75,0.18);border-radius:14px;padding:40px 36px;">
              <h1 style="margin:0 0 16px 0;font-size:22px;line-height:1.3;color:#F5F3EE;font-weight:600;">${opts.headline}</h1>
              <div style="font-size:14px;line-height:1.7;color:#9FB0C4;">
                ${opts.bodyHtml}
              </div>

              <table role="presentation" cellpadding="0" cellspacing="0" style="margin:28px 0 8px 0;">
                <tr>
                  <td align="center" bgcolor="#C9A24B" style="border-radius:8px;">
                    <a href="${opts.ctaUrl}" target="_blank" style="display:inline-block;padding:15px 32px;font-size:13px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:#0D1220;text-decoration:none;border-radius:8px;">
                      ${opts.ctaLabel}
                    </a>
                  </td>
                </tr>
              </table>

              ${
                opts.securityNote
                  ? `<p style="margin:20px 0 0 0;font-size:12px;line-height:1.6;color:#6B7A8F;">${opts.securityNote}</p>`
                  : ''
              }
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td align="center" style="padding-top:28px;">
              <p style="margin:0;font-size:12px;color:#F5F3EE;font-weight:600;letter-spacing:0.02em;">KCC Marine Cloud</p>
              <p style="margin:4px 0 0 0;font-size:10px;letter-spacing:0.15em;text-transform:uppercase;color:#8A7239;">Marine Solutions &bull; Technology &bull; Excellence</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

// ---------------------------------------------------------
// INVITE USER — Supabase Dashboard: Authentication → Email Templates → Invite user
// Variable de confirmación: {{ .ConfirmationURL }}
// Personalización opcional y segura vía {{ .Data.organization_name }} /
// {{ .Data.role }} — SOLO si esos metadata keys fueron pasados al
// llamar auth.admin.inviteUserByEmail({ data: {...} }). Si no existen,
// Go templates los renderiza vacíos — por eso el copy usa {{ if }}
// para caer al texto genérico en vez de mostrar un hueco vacío.
export const SUPABASE_INVITE_SUBJECT = "You're invited to KCC Marine Cloud";
export const SUPABASE_INVITE_TEMPLATE = emailShell({
  preheader: 'Your secure company workspace is ready.',
  headline: 'Welcome to KCC Marine Cloud',
  bodyHtml: `<p style="margin:0 0 14px 0;">{{ if .Data.organization_name }}You've been invited to join <strong style="color:#F5F3EE;">{{ .Data.organization_name }}</strong> on KCC Marine Cloud.{{ else }}You've been invited to join a company workspace in KCC Marine Cloud.{{ end }}</p>
    <p style="margin:0;">Your secure workspace is ready. Activate your account to access your {{ if eq .Data.role "technician" }}assigned work orders, job details, checklists, and field tools{{ else }}company dashboard, assigned tools, and operations{{ end }}.</p>`,
  ctaLabel: 'Activate my account',
  ctaUrl: '{{ .ConfirmationURL }}',
  securityNote: 'This invitation is unique to you. For security, do not forward this email.',
});

// ---------------------------------------------------------
// RECOVERY — Supabase Dashboard: Authentication → Email Templates → Reset password
export const SUPABASE_RECOVERY_SUBJECT = 'Reset your KCC Marine Cloud password';
export const SUPABASE_RECOVERY_TEMPLATE = emailShell({
  preheader: 'Use the secure link to choose a new password.',
  headline: 'Reset your password',
  bodyHtml: `<p style="margin:0 0 14px 0;">We received a request to reset your KCC Marine Cloud password.</p>
    <p style="margin:0;">Use the secure link below to choose a new password.</p>`,
  ctaLabel: 'Reset password',
  ctaUrl: '{{ .ConfirmationURL }}',
  securityNote: "If you didn't request this, you can safely ignore this email — your password will not change.",
});

// ---------------------------------------------------------
// MAGIC LINK — Supabase Dashboard: Authentication → Email Templates → Magic Link
export const SUPABASE_MAGIC_LINK_SUBJECT = 'Your secure KCC Marine Cloud sign-in link';
export const SUPABASE_MAGIC_LINK_TEMPLATE = emailShell({
  preheader: 'Sign in securely — no password needed.',
  headline: 'Secure sign-in',
  bodyHtml: `<p style="margin:0;">Use the button below to securely access KCC Marine Cloud. No password needed.</p>`,
  ctaLabel: 'Sign in securely',
  ctaUrl: '{{ .ConfirmationURL }}',
  securityNote: "If you didn't request this link, you can safely ignore this email.",
});

// ---------------------------------------------------------
// CONFIRM SIGNUP — Supabase Dashboard: Authentication → Email Templates → Confirm signup
export const SUPABASE_CONFIRMATION_SUBJECT = 'Confirm your KCC Marine Cloud email';
export const SUPABASE_CONFIRMATION_TEMPLATE = emailShell({
  preheader: 'One more step to activate your account.',
  headline: 'Confirm your email',
  bodyHtml: `<p style="margin:0;">Please confirm your email address to finish setting up your KCC Marine Cloud account.</p>`,
  ctaLabel: 'Confirm email',
  ctaUrl: '{{ .ConfirmationURL }}',
});

// ---------------------------------------------------------
// Fallback real de Resend — usado por lib/team/actions.ts SOLO cuando
// auth.admin.inviteUserByEmail() falla porque el email ya tiene
// cuenta (nunca un sistema de email paralelo, es la misma marca /
// mismo shell, con una URL real construida por la app en vez de una
// variable de Supabase).
export function renderInviteFallbackEmail(acceptUrl: string, organizationName?: string): string {
  return emailShell({
    preheader: 'Your secure company workspace is ready.',
    headline: 'Welcome to KCC Marine Cloud',
    bodyHtml: `<p style="margin:0 0 14px 0;">${
      organizationName ? `You've been invited to join <strong style="color:#F5F3EE;">${organizationName}</strong> on KCC Marine Cloud.` : "You've been invited to join a company workspace in KCC Marine Cloud."
    }</p>
      <p style="margin:0;">You already have an account — sign in and accept your invitation below.</p>`,
    ctaLabel: 'Accept invitation',
    ctaUrl: acceptUrl,
    securityNote: 'This invitation is unique to you. For security, do not forward this email.',
  });
}


// ---------------------------------------------------------
// DIRECT APP-MANAGED AUTH EMAILS
// These are used when Marine Cloud generates Supabase links server-side
// and delivers them through Resend's API directly. This removes the
// production dependency on Supabase SMTP for critical invitation/sign-in
// delivery while keeping Supabase Auth as the source of identity/session.
export function renderDirectInviteEmail(
  confirmUrl: string,
  organizationName?: string,
  role?: string,
  isNewAccount = true,
): string {
  const accessCopy = role === 'technician'
    ? 'assigned work orders, job details, checklists, tracking, and field tools'
    : role === 'customer'
      ? 'your vessel, active service, estimates, invoices, messages, and service history'
      : 'your company workspace, team tools, work orders, vessels, customers, and authorized operations';

  return emailShell({
    preheader: 'Your secure KCC Marine Cloud access is ready.',
    headline: 'Welcome to KCC Marine Cloud',
    bodyHtml: `<p style="margin:0 0 14px 0;">${
      organizationName
        ? `You've been invited to join <strong style="color:#F5F3EE;">${escapeHtmlForTemplate(organizationName)}</strong> on KCC Marine Cloud.`
        : "You've been invited to join a company workspace in KCC Marine Cloud."
    }</p>
      <p style="margin:0;">${
        isNewAccount
          ? `Activate your secure account to access ${accessCopy}. You'll choose your password immediately after activation.`
          : `Accept the invitation to access ${accessCopy}. After that, continue signing in with your existing email and password.`
      }</p>`,
    ctaLabel: isNewAccount ? 'Activate my account' : 'Accept invitation',
    ctaUrl: confirmUrl,
    securityNote: 'This secure link is unique to you. For security, do not forward this email.',
  });
}

export function renderDirectMagicLinkEmail(confirmUrl: string): string {
  return emailShell({
    preheader: 'Your secure KCC Marine Cloud sign-in link is ready.',
    headline: 'Secure sign-in',
    bodyHtml: '<p style="margin:0;">Use the button below to securely access KCC Marine Cloud. This link is time-limited and can only be used for your account.</p>',
    ctaLabel: 'Sign in securely',
    ctaUrl: confirmUrl,
    securityNote: "If you didn't request this link, you can safely ignore this email.",
  });
}



export function renderDirectRecoveryEmail(confirmUrl: string): string {
  return emailShell({
    preheader: 'Reset your KCC Marine Cloud password securely.',
    headline: 'Reset your password',
    bodyHtml: '<p style="margin:0;">We received a request to reset your KCC Marine Cloud password. Use the secure button below to choose a new password.</p>',
    ctaLabel: 'Reset password',
    ctaUrl: confirmUrl,
    securityNote: "If you didn't request this, you can safely ignore this email — your password will not change.",
  });
}
function escapeHtmlForTemplate(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}
