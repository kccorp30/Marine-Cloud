// Sin 'use server' — este archivo solo exporta constantes, así que
// tanto lib/technician/actions.ts (servidor) como componentes cliente
// pueden importarlo. Un archivo 'use server' solo puede exportar
// funciones async, por eso estas constantes viven separadas.

export const ALLOWED_MEDIA_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic'];
export const MAX_MEDIA_SIZE_BYTES = 25 * 1024 * 1024; // 25MB
export const ALLOWED_MEDIA_CATEGORIES = [
  'before', 'diagnosis', 'progress', 'after', 'part', 'damage', 'measurement', 'receipt', 'qc', 'voice_note',
];
