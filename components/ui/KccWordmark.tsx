export function KccWordmark({ size = 'md', className = '' }: { size?: 'sm' | 'md' | 'lg'; className?: string }) {
  const sizes = {
    sm: { k: 'text-2xl', cc: 'text-2xl', sub: 'text-[7px]' },
    md: { k: 'text-4xl', cc: 'text-4xl', sub: 'text-[9px]' },
    lg: { k: 'text-6xl', cc: 'text-6xl', sub: 'text-[11px]' },
  }[size];

  return (
    <div className={`inline-flex flex-col items-center ${className}`}>
      <div className="flex items-baseline font-display font-bold tracking-tight">
        <span className={`${sizes.k} text-gold-sheen`}>K</span>
        <span className={`${sizes.cc} bg-gradient-to-b from-silver to-cool-gray bg-clip-text text-transparent`}>CC</span>
      </div>
      <div className={`${sizes.sub} font-mono uppercase tracking-[0.35em] text-gold-dim mt-1`}>Marine Solutions</div>
    </div>
  );
}
