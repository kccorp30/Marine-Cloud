import 'server-only';

// =========================================================
// lib/ai/translate.ts — Marine Cloud Phase 8 hardening
// =========================================================
// BUG REAL corregido: la validación anterior solo chequeaba que cada
// número del ORIGINAL apareciera en la salida — un modelo que
// AGREGARA un número nuevo (ej. "$850" -> "$850, $1,500") pasaba sin
// detectarlo. Ahora se compara multiset EXACTO — mismos números,
// misma cantidad de cada uno, en cualquier orden. Cualquier
// diferencia (número perdido, alterado, o agregado) marca la
// traducción como no confiable.
//
// LIMITACIÓN HONESTA: sin ANTHROPIC_API_KEY en este sandbox, no pude
// verificar una llamada real de punta a punta.
// =========================================================

export type TranslationMode = 'translate_only' | 'professional' | 'friendly' | 'concise' | 'sales' | 'technical';
export type SupportedLanguage = 'en' | 'es';

export const SUPPORTED_LANGUAGES: SupportedLanguage[] = ['en', 'es'];
export const SUPPORTED_MODES: TranslationMode[] = ['translate_only', 'professional', 'friendly', 'concise', 'sales', 'technical'];
export const MAX_TRANSLATION_INPUT_LENGTH = 4000;

export interface TranslateRequest {
  sourceText: string;
  sourceLanguage?: SupportedLanguage;
  targetLanguage: SupportedLanguage;
  mode: TranslationMode;
}

export interface TranslateResult {
  translatedText: string;
  detectedSourceLanguage: SupportedLanguage | null;
  targetLanguage: SupportedLanguage;
  tokensPreserved: boolean;
  sourceTokens: string[];
  outputTokens: string[];
  missingTokens: string[];
  addedTokens: string[];
}

const MODE_INSTRUCTIONS: Record<TranslationMode, string> = {
  translate_only: 'Translate the text accurately. Do not change tone or style.',
  professional: 'Translate the text and make the tone professional and polished, suitable for a marine service business communicating with a customer.',
  friendly: 'Translate the text and make the tone warm and friendly, while remaining professional.',
  concise: 'Translate the text and make it more concise, removing unnecessary words while preserving all facts.',
  sales: 'Translate the text and make it persuasive and customer-focused, without exaggerating or inventing claims.',
  technical: 'Translate the text preserving technical/marine terminology precisely.',
};

const LANGUAGE_NAMES: Record<SupportedLanguage, string> = { en: 'English', es: 'Spanish' };

function extractProtectedTokens(text: string): string[] {
  const patterns = [
    /\bEST-\d+\b/g,
    /\bINV-\d+\b/g,
    /\bCO-\d+\b/g,
    /[$]\d[\d,]*(\.\d+)?/g,
    /\d[\d,]*(\.\d+)?%/g,
    /\(\d{3}\)\s?\d{3}-\d{4}/g,
    /\b\d{3}-\d{3}-\d{4}\b/g,
    /\b\d[\d,]*(\.\d+)?\b/g,
  ];
  const found: string[] = [];
  for (const pattern of patterns) {
    const matches = text.match(pattern) ?? [];
    found.push(...matches.map((m) => m.replace(/[.,]+$/, '')));
  }
  return found;
}

function diffMultisets(source: string[], output: string[]): { missing: string[]; added: string[] } {
  const sourceCount = new Map<string, number>();
  for (const t of source) sourceCount.set(t, (sourceCount.get(t) ?? 0) + 1);
  const outputCount = new Map<string, number>();
  for (const t of output) outputCount.set(t, (outputCount.get(t) ?? 0) + 1);

  const missing: string[] = [];
  for (const [token, count] of sourceCount) {
    const have = outputCount.get(token) ?? 0;
    for (let i = have; i < count; i++) missing.push(token);
  }
  const added: string[] = [];
  for (const [token, count] of outputCount) {
    const have = sourceCount.get(token) ?? 0;
    for (let i = have; i < count; i++) added.push(token);
  }
  return { missing, added };
}

export interface TokenPreservationCheck {
  preserved: boolean;
  missingTokens: string[];
  addedTokens: string[];
  unrenderedPlaceholders: string[];
}

/**
 * Detecta placeholders de template ({{algo}}) que quedaron sin
 * resolver en el texto final — nunca debería llegar un {{...}}
 * literal a un mensaje realmente enviado (o vino de un template mal
 * renderizado, o de un texto de traducción que inventó sintaxis de
 * variable). Server-side, autoritativo — la edición manual del
 * textarea en el cliente no puede evitar este chequeo.
 */
function findUnrenderedPlaceholders(text: string): string[] {
  return text.match(/\{\{[^}]*\}\}/g) ?? [];
}

/**
 * Compara los tokens comerciales protegidos entre dos textos —
 * reusada tanto por translateMessage() (preview de traducción) como
 * por la revalidación server-side al momento de enviar (sección 4
 * del hardening final: la UI puede quedar desactualizada si el staff
 * edita el texto a mano después de traducir; el servidor SIEMPRE
 * vuelve a comparar antes de enviar, nunca confía en el estado del
 * cliente).
 */
export function checkTokenPreservation(original: string, candidate: string): TokenPreservationCheck {
  const sourceTokens = extractProtectedTokens(original);
  const outputTokens = extractProtectedTokens(candidate);
  const { missing, added } = diffMultisets(sourceTokens, outputTokens);
  const unrenderedPlaceholders = findUnrenderedPlaceholders(candidate);
  return {
    preserved: missing.length === 0 && added.length === 0 && unrenderedPlaceholders.length === 0,
    missingTokens: missing,
    addedTokens: added,
    unrenderedPlaceholders,
  };
}

export async function translateMessage(req: TranslateRequest): Promise<TranslateResult> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new Error('Translation is not configured — ANTHROPIC_API_KEY is missing from the server environment.');
  }

  if (!SUPPORTED_LANGUAGES.includes(req.targetLanguage)) {
    throw new Error(`Unsupported target language: ${req.targetLanguage}`);
  }
  if (!SUPPORTED_MODES.includes(req.mode)) {
    throw new Error(`Unsupported translation mode: ${req.mode}`);
  }
  if (!req.sourceText || req.sourceText.trim().length === 0) {
    throw new Error('Source text is empty');
  }
  if (req.sourceText.length > MAX_TRANSLATION_INPUT_LENGTH) {
    throw new Error(`Source text exceeds the maximum length of ${MAX_TRANSLATION_INPUT_LENGTH} characters`);
  }

  const systemPrompt = `You are a professional translation assistant for a marine services company. ${MODE_INSTRUCTIONS[req.mode]}

CRITICAL RULES — never violate these:
- Translate into ${LANGUAGE_NAMES[req.targetLanguage]}.
- Preserve every number, price, date, and quantity EXACTLY as written in the source. Do not round, convert, or alter them in any way.
- Do NOT invent prices, warranties, dates, completed work, services, certifications, or promises that are not in the source text.
- Do NOT add any number, price, or identifier that is not in the source.
- Respond with ONLY the translated/rewritten text — no preamble, no explanation, no quotation marks around it.`;

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: 'claude-sonnet-4-6',
      max_tokens: 1024,
      system: systemPrompt,
      messages: [{ role: 'user', content: req.sourceText }],
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`Translation provider error (${response.status}): ${errorBody}`);
  }

  const data = await response.json();
  const translatedText: string = data.content?.find((b: any) => b.type === 'text')?.text ?? '';

  const check = checkTokenPreservation(req.sourceText, translatedText);

  return {
    translatedText,
    detectedSourceLanguage: req.sourceLanguage ?? null,
    targetLanguage: req.targetLanguage,
    tokensPreserved: check.preserved,
    sourceTokens: extractProtectedTokens(req.sourceText),
    outputTokens: extractProtectedTokens(translatedText),
    missingTokens: check.missingTokens,
    addedTokens: check.addedTokens,
  };
}
