export default function Loading() {
  return (
    <div className="command-stack" role="status" aria-label="Loading">
      <div className="command-loading" style={{ height: 240 }} />
      <div className="launch-grid">
        {[1, 2, 3, 4].map((i) => (
          <div key={i} className="command-loading" />
        ))}
      </div>
      <div className="command-loading" style={{ height: 320 }} />
    </div>
  );
}
