import 'server-only';

// =========================================================
// lib/email/resend.ts — Marine Cloud Phase 8 hardening
// =========================================================
// Implementación REAL del proveedor (Resend) — nunca lógica de SDK/
// fetch dentro de SQL. Reemplazable: cualquier otro proveedor
// implementaría la misma interfaz EmailProvider.
//
// LIMITACIÓN HONESTA: este sandbox no tiene RESEND_API_KEY
// configurada — no pude verificar un envío real en vivo. La forma de
// la llamada (endpoint, headers, body) es la real y correcta de la
// API de Resend. Documentado también en las limitaciones finales,
// mismo patrón que Stripe/Anthropic.
// =========================================================

export interface SendEmailInput {
  to: string;
  from: string;
  replyTo?: string;
  idempotencyKey?: string;
  subject: string;
  text: string;
  html: string;
}

export interface SendEmailResult {
  success: boolean;
  providerMessageId?: string;
  error?: string;
}

export interface EmailProvider {
  sendEmail(input: SendEmailInput): Promise<SendEmailResult>;
}

class ResendProvider implements EmailProvider {
  async sendEmail(input: SendEmailInput): Promise<SendEmailResult> {
    const apiKey = process.env.RESEND_API_KEY;
    if (!apiKey) {
      return { success: false, error: 'Email sending is not configured — RESEND_API_KEY is missing from the server environment.' };
    }

    try {
      const response = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
          ...(input.idempotencyKey ? {'Idempotency-Key': input.idempotencyKey} : {}),
        },
        body: JSON.stringify({
          from: input.from,
          to: [input.to],
          reply_to: input.replyTo,
          subject: input.subject,
          text: input.text,
          html: input.html,
        }),
      });

      if (!response.ok) {
        const errorBody = await response.text();
        return { success: false, error: `Resend error (${response.status}): ${errorBody}` };
      }

      const data = await response.json();
      return { success: true, providerMessageId: data.id };
    } catch (err) {
      return { success: false, error: err instanceof Error ? err.message : 'Unknown provider error' };
    }
  }
}

/**
 * Mock usable SOLO en tests — nunca se usa automáticamente en
 * runtime real. Antes getEmailProvider() caía a este mock cuando
 * faltaba RESEND_API_KEY, lo que podía dejar Marine Cloud marcando
 * mensajes 'sent' sin que ningún email real hubiera salido —
 * corregido: en runtime real, sin la key configurada, el envío falla
 * de forma segura (nunca 'sent'). Los tests que necesiten este mock
 * lo instancian directamente (`new MockEmailProvider()`), nunca a
 * través de getEmailProvider().
 */
/**
 * Mock usable SOLO en runtime de test (NODE_ENV=test) o instanciado
 * directo en un test unitario. getEmailProvider() nunca lo elige
 * fuera de test — ver esa función para el gate real.
 */
export class MockEmailProvider implements EmailProvider {
  async sendEmail(input: SendEmailInput): Promise<SendEmailResult> {
    if (!input.to || !input.to.includes('@')) {
      return { success: false, error: 'Invalid recipient address (mock provider)' };
    }
    return { success: true, providerMessageId: `mock_${crypto.randomUUID()}` };
  }
}

export function getEmailProvider(): EmailProvider {
  if (process.env.RESEND_API_KEY) {
    return new ResendProvider();
  }

  // MockEmailProvider SOLO en runtime de test real (Vitest ya setea
  // NODE_ENV=test automáticamente — no hay otra convención de test
  // flag en este repo, así que se reusa esa señal estándar en vez de
  // inventar una nueva). Fuera de test, sin RESEND_API_KEY, el
  // proveedor falla cerrado explícito — nunca cae en silencio a un
  // envío simulado que dejaría un mensaje marcado 'sent' sin que
  // ningún proveedor real lo haya aceptado.
  if (process.env.NODE_ENV === 'test') {
    return new MockEmailProvider();
  }

  throw new Error('Email provider is not configured — RESEND_API_KEY is missing from the server environment. The message will not be sent.');
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

/** Texto plano -> HTML seguro (escapa todo input no confiable antes de insertarlo). */
export function renderEmailHtml(body: string, signature?: string | null): string {
  const escapedBody = escapeHtml(body).replace(/\n/g, '<br>');
  const escapedSignature = signature ? escapeHtml(signature).replace(/\n/g, '<br>') : '';
  return `<div style="font-family: sans-serif; font-size: 14px; color: #1a1a1a; line-height: 1.6;">
${escapedBody}
${escapedSignature ? `<hr style="border: none; border-top: 1px solid #e5e5e5; margin: 16px 0;"><div style="color: #666;">${escapedSignature}</div>` : ''}
</div>`;
}
