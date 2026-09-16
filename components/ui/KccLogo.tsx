import Image from 'next/image';

const SIZES = {
  sm: { w: 120, h: 120 },
  md: { w: 180, h: 180 },
  lg: { w: 260, h: 260 },
} as const;

/**
 * Logo real de KCC Marine Solutions (public/brand/kcc-marine-solutions.png).
 * next/image optimiza el archivo automáticamente (resize/format) — nunca
 * se sirve el PNG de 1.7MB sin procesar. KccWordmark (tratamiento
 * tipográfico) queda como fallback disponible para contextos donde el
 * archivo de imagen no aplica (ej. loading states muy livianos), pero
 * este es el componente primario en login/sidebar.
 */
export function KccLogo({ size = 'md', className = '' }: { size?: keyof typeof SIZES; className?: string }) {
  const { w, h } = SIZES[size];
  return (
    <Image
      src="/brand/kcc-marine-solutions.png"
      alt="KCC Marine Solutions"
      width={w}
      height={h}
      priority={size !== 'sm'}
      className={`object-contain ${className}`}
    />
  );
}
