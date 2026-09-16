'use client';

import { useRef, useState, useTransition, type ReactNode } from 'react';

async function compressImage(file: File) {
  if (file.size <= 1400 * 1024 && ['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) return file;
  const url = URL.createObjectURL(file);
  try {
    const img = new Image();
    img.src = url;
    await img.decode();
    const ratio = Math.min(1, 1920 / Math.max(img.width, img.height));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(img.width * ratio));
    canvas.height = Math.max(1, Math.round(img.height * ratio));
    const ctx = canvas.getContext('2d');
    if (!ctx) return file;
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/webp', 0.8));
    return blob ? new File([blob], `${file.name.replace(/\.[^.]+$/, '') || 'photo'}.webp`, { type: 'image/webp' }) : file;
  } catch {
    // HEIC/HEIF is not decodable by every browser. Keep the original;
    // the server/storage validators still enforce the real 12 MB limit.
    return file;
  } finally {
    URL.revokeObjectURL(url);
  }
}

export function MediaActionForm({ action, children, className = '', resetOnSuccess = false }: {
  action: (formData: FormData) => Promise<any>;
  children: ReactNode;
  className?: string;
  resetOnSuccess?: boolean;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  return (
    <form
      ref={formRef}
      className={className}
      onSubmit={(event) => {
        event.preventDefault();
        setError(null);
        const form = event.currentTarget;
        startTransition(async () => {
          try {
            const data = new FormData(form);
            const originals = data.getAll('photos').filter((v): v is File => v instanceof File && v.size > 0).slice(0, 5);
            data.delete('photos');
            for (const file of originals) data.append('photos', await compressImage(file));
            const result = await action(data);
            if (result?.error) setError(String(result.error));
            else if (resetOnSuccess) formRef.current?.reset();
          } catch (e) {
            setError(e instanceof Error ? e.message : 'Could not upload photos.');
          }
        });
      }}
    >
      {children}
      {pending && <p className="text-xs text-cyan-200 mt-2">Preparing secure upload…</p>}
      {error && <p className="text-xs text-red-300 mt-2">{error}</p>}
    </form>
  );
}
