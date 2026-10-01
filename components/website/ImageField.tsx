'use client';

import { useRef, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { siteMediaUrl } from '@/lib/website/content-model';

// Sube la foto DIRECTO del navegador al bucket público site-media con
// la sesión del usuario. La policy de storage solo deja escribir a
// KCC Admin, así que no hace falta pasar el archivo por el servidor
// (y no chocamos con el límite de tamaño de las server actions).
//
// El formulario solo guarda la RUTA (hidden input). La validación del
// servidor acepta únicamente rutas con el formato que genera este
// componente: "<carpeta>/<uuid>.<ext>".

const ACCEPTED = ['image/jpeg', 'image/png', 'image/webp', 'image/avif'];
const MAX_BYTES = 10 * 1024 * 1024;
const EXT: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/avif': 'avif' };

export function ImageField({
  name,
  folder,
  initialPath,
  labels,
}: {
  name: string;
  folder: string;
  initialPath: string | null;
  labels: { upload: string; replace: string; remove: string; uploading: string; tooLarge: string; badType: string; failed: string; hint: string };
}) {
  const [path, setPath] = useState<string | null>(initialPath);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
  const preview = siteMediaUrl(supabaseUrl, path);

  async function onFile(file: File) {
    setError(null);
    if (!ACCEPTED.includes(file.type)) return setError(labels.badType);
    if (file.size > MAX_BYTES) return setError(labels.tooLarge);

    setBusy(true);
    try {
      const objectPath = `${folder}/${crypto.randomUUID()}.${EXT[file.type]}`;
      const supabase = createClient();
      const { error: uploadError } = await supabase.storage
        .from('site-media')
        .upload(objectPath, file, { contentType: file.type, cacheControl: '31536000', upsert: false });
      if (uploadError) {
        setError(labels.failed);
        return;
      }
      setPath(objectPath);
    } catch {
      setError(labels.failed);
    } finally {
      setBusy(false);
      if (inputRef.current) inputRef.current.value = '';
    }
  }

  return (
    <div className="space-y-3">
      <input type="hidden" name={name} value={path ?? ''} />
      {preview ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={preview} alt="" className="w-full max-h-56 rounded-lg object-cover border border-white/10" />
      ) : (
        <div className="grid h-32 place-items-center rounded-lg border border-dashed border-white/15 text-xs text-cool-gray">
          {labels.hint}
        </div>
      )}
      <div className="flex flex-wrap gap-2">
        <label className="kcc-action cursor-pointer">
          {busy ? labels.uploading : preview ? labels.replace : labels.upload}
          <input
            ref={inputRef}
            type="file"
            accept={ACCEPTED.join(',')}
            className="sr-only"
            disabled={busy}
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) void onFile(f);
            }}
          />
        </label>
        {preview && !busy && (
          <button type="button" className="kcc-action" onClick={() => setPath(null)}>
            {labels.remove}
          </button>
        )}
      </div>
      {error && (
        <p role="alert" className="text-xs text-red-300">
          {error}
        </p>
      )}
    </div>
  );
}
