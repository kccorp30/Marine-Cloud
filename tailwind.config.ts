import type { Config } from 'tailwindcss';

// Tokens de la APP (densa, operativa) — comparten fundamento con el
// sitio (navy casi negro, dorado, JetBrains Mono) pero con más vidrio
// y la variante plata en vez de la cinematográfica. Ver
// shared-visual-tokens.md del proyecto del sitio para la referencia
// completa de qué se comparte y qué difiere a propósito.

const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        navy: '#0D1220',
        'navy-deep': '#080C15',
        panel: '#0B1826',
        'marine-white': '#F5F3EE',
        'cool-gray': '#9FB0C4',
        gold: '#C9A24B',
        'gold-dim': '#8A7239',
        'gold-bright': '#E4C77A',
        silver: '#B9C4D6',
        violet: '#5B5FA6',
      },
      fontFamily: {
        display: ['var(--font-sora)', 'sans-serif'],
        body: ['var(--font-inter)', 'sans-serif'],
        mono: ['var(--font-jetbrains)', 'monospace'],
      },
      borderRadius: {
        sm: '4px',
        md: '8px',
        lg: '14px',
        xl: '20px',
      },
      boxShadow: {
        // Sombra premium profunda para cards/paneles elevados.
        premium: '0 20px 60px -15px rgba(0,0,0,0.55), 0 1px 0 rgba(255,255,255,0.04) inset',
        'glow-gold': '0 0 0 1px rgba(201,162,75,0.25), 0 0 24px -4px rgba(201,162,75,0.35)',
        'glow-violet': '0 0 0 1px rgba(91,95,166,0.25), 0 0 32px -6px rgba(91,95,166,0.4)',
      },
      backgroundImage: {
        // Fondo de fundación — navy profundo con un degradé sutil
        // azul/violeta, nunca plano. Usado en el shell y hero blocks.
        'marine-depth': 'radial-gradient(ellipse 120% 80% at 20% -10%, rgba(91,95,166,0.18) 0%, rgba(13,18,32,0) 55%), radial-gradient(ellipse 100% 60% at 100% 0%, rgba(201,162,75,0.08) 0%, rgba(13,18,32,0) 50%), linear-gradient(180deg, #0D1220 0%, #080C15 100%)',
        'gold-sheen': 'linear-gradient(135deg, #E4C77A 0%, #C9A24B 45%, #8A7239 100%)',
      },
      keyframes: {
        'fade-up': { '0%': { opacity: '0', transform: 'translateY(8px)' }, '100%': { opacity: '1', transform: 'translateY(0)' } },
        'pulse-soft': { '0%,100%': { opacity: '1' }, '50%': { opacity: '0.55' } },
        shimmer: { '0%': { backgroundPosition: '-200% 0' }, '100%': { backgroundPosition: '200% 0' } },
      },
      animation: {
        'fade-up': 'fade-up 0.4s cubic-bezier(0.16,1,0.3,1) both',
        'pulse-soft': 'pulse-soft 2s ease-in-out infinite',
        shimmer: 'shimmer 1.8s linear infinite',
      },
    },
  },
  plugins: [],
};

export default config;
