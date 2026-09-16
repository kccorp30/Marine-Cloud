'use client';
import { useMemo, useState } from 'react';

export function MultiImagePicker({ name = 'photos', max = 5, label = 'Add photos', hint = 'JPG, PNG, WebP or HEIC · up to 12 MB each' }: { name?: string; max?: number; label?: string; hint?: string }) {
  const [files, setFiles] = useState<File[]>([]);
  const previews = useMemo(() => files.map((file) => ({ file, url: URL.createObjectURL(file) })), [files]);
  return (
    <div className="media-picker">
      <label className="media-dropzone">
        <input
          type="file"
          name={name}
          accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
          multiple
          className="sr-only"
          onChange={(event) => setFiles(Array.from(event.target.files || []).slice(0, max))}
        />
        <span className="media-drop-icon">＋</span>
        <span><strong>{label}</strong><small>{hint}</small></span>
      </label>
      {previews.length > 0 && (
        <div className="media-preview-row">
          {previews.map(({ file, url }) => <div key={`${file.name}-${file.lastModified}`} className="media-preview"><img src={url} alt=""/><span>{file.name}</span></div>)}
        </div>
      )}
    </div>
  );
}
