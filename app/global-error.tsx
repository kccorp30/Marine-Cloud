'use client';

export default function GlobalError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <html lang="en">
      <body style={{ background: '#0D1220', color: '#F5F3EE', minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: 'sans-serif' }}>
        <div style={{ textAlign: 'center' }}>
          <p style={{ marginBottom: 16 }}>Something went wrong.</p>
          <button onClick={reset} style={{ color: '#C9A24B', textTransform: 'uppercase', fontSize: 12, letterSpacing: '0.08em' }}>
            Try again
          </button>
        </div>
      </body>
    </html>
  );
}
