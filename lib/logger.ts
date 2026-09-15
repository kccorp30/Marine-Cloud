import 'server-only';

// Logger base — Phase 0. Estructurado para que, cuando se agregue un
// proveedor real (Sentry, Axiom, etc.), sea un cambio en un solo
// archivo, igual que el patrón de lib/notifications del sitio web.

type LogLevel = 'info' | 'warn' | 'error';

function log(level: LogLevel, message: string, context?: Record<string, unknown>) {
  const entry = { level, message, context, timestamp: new Date().toISOString() };
  if (level === 'error') {
    console.error(JSON.stringify(entry));
  } else if (level === 'warn') {
    console.warn(JSON.stringify(entry));
  } else {
    console.log(JSON.stringify(entry));
  }
}

export const logger = {
  info: (message: string, context?: Record<string, unknown>) => log('info', message, context),
  warn: (message: string, context?: Record<string, unknown>) => log('warn', message, context),
  error: (message: string, context?: Record<string, unknown>) => log('error', message, context),
};

// Helper para API routes / server actions: nunca devolver el mensaje
// interno de un error al cliente — loguearlo completo server-side,
// devolver algo genérico.
export function safeErrorResponse(error: unknown, userMessage = 'Something went wrong.') {
  logger.error(userMessage, { error: error instanceof Error ? error.message : String(error) });
  return { error: userMessage };
}
