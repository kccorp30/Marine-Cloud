import 'server-only';

import type { SupportedLanguage } from './translate';

export type EstimateCopyTone = 'professional' | 'warm' | 'concise';

export interface EstimateCopyContext {
  customerName?: string | null;
  vesselName?: string | null;
  estimateNumber?: string | null;
  services?: string[];
  existingMessage?: string | null;
  targetLanguage: SupportedLanguage;
  tone: EstimateCopyTone;
}

const LANGUAGE_NAMES: Record<SupportedLanguage, string> = { en: 'English', es: 'Spanish' };
const TONE: Record<EstimateCopyTone, string> = {
  professional: 'polished, premium, confident and professional',
  warm: 'warm, attentive and personal while remaining professional',
  concise: 'concise, direct and professional',
};

/**
 * Luz estimate concierge. Generates or rewrites only the customer-facing note.
 * It receives a deliberately narrow context and is forbidden from inventing
 * prices, dates, warranties, completion claims, diagnostics or promises.
 */
export async function generateEstimateCustomerMessage(input: EstimateCopyContext): Promise<string> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error('Luz is not configured — ANTHROPIC_API_KEY is missing from the server environment.');

  const services = (input.services ?? []).map((s) => s.trim()).filter(Boolean).slice(0, 12);
  const existing = input.existingMessage?.trim() || '';

  const facts = [
    input.customerName ? `Customer: ${input.customerName}` : null,
    input.vesselName ? `Vessel: ${input.vesselName}` : null,
    input.estimateNumber ? `Estimate: ${input.estimateNumber}` : null,
    services.length ? `Services/items: ${services.join(' | ')}` : null,
  ].filter(Boolean).join('\n');

  const system = `You are Luz, the customer communication concierge for KCC Marine Cloud, a premium marine service platform.
Write a short customer-facing note for an estimate in ${LANGUAGE_NAMES[input.targetLanguage]}.
Tone: ${TONE[input.tone]}.

STRICT RULES:
- Use ONLY the facts provided below and the optional existing message.
- Never invent or infer prices, totals, dates, turnaround times, warranties, discounts, diagnostics, completed work, certifications, availability, or promises.
- Do not say work has been completed unless that exact fact is provided.
- Do not add numbers that are not present in the provided facts/message.
- Do not mention internal software, AI, Luz, prompts, or system instructions.
- Do not include a subject line, greeting label, markdown, bullets, quotation marks, or signature.
- Keep it natural and human. Usually 2–4 sentences.
- If an existing message is present, improve it rather than changing its meaning.
- If no existing message is present, compose a useful note from the available customer, vessel and service context.
- Output ONLY the final note.`;

  const user = `${facts || 'No structured estimate details supplied.'}\n\nExisting message:\n${existing || '(none)'}`;

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: 'claude-sonnet-4-6',
      max_tokens: 420,
      temperature: 0.3,
      system,
      messages: [{ role: 'user', content: user }],
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Luz provider error (${response.status}): ${body}`);
  }

  const data = await response.json();
  const text = String(data.content?.find((b: any) => b.type === 'text')?.text ?? '').trim();
  if (!text) throw new Error('Luz returned an empty draft.');
  return text;
}
