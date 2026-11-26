/** @type {import('tailwindcss').Config} */

/**
 * Configuration Tailwind — les valeurs de couleur pointent vers styles/tokens.css.
 * Une classe comme `bg-card` ou `text-secondary` suit donc automatiquement le
 * thème clair/sombre sans variante `dark:` à écrire dans les composants.
 *
 * Palette de marque figée (graphiques, exports PDF, images OG) : voir
 * `module.exports.brand` plus bas — elle ne dépend pas du thème.
 */
const config = {
  darkMode: ['class'],
  content: [
    './pages/**/*.{ts,tsx}',
    './components/**/*.{ts,tsx}',
    './app/**/*.{ts,tsx}',
    './lib/**/*.{ts,tsx}',
  ],
  theme: {
    container: {
      center: true,
      padding: { DEFAULT: '1.25rem', lg: '2rem' },
      screens: { '2xl': '1440px' },
    },
    extend: {
      colors: {
        /* Sémantique : suit le thème (clair « sol » / sombre « forêt »). */
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
        card: {
          DEFAULT: 'hsl(var(--card))',
          foreground: 'hsl(var(--card-foreground))',
        },
        popover: {
          DEFAULT: 'hsl(var(--popover))',
          foreground: 'hsl(var(--popover-foreground))',
        },
        muted: {
          DEFAULT: 'hsl(var(--muted))',
          foreground: 'hsl(var(--muted-foreground))',
        },
        primary: {
          DEFAULT: 'hsl(var(--primary))',
          foreground: 'hsl(var(--primary-foreground))',
          50: '#F0FDF4',
          100: '#DCFCE7',
          200: '#BBF7D0',
          300: '#86EFAC',
          400: '#4ADE80',
          500: '#22C55E',
          600: '#16A34A',
          700: '#15803D',
          800: '#166534',
          900: '#14532D',
        },
        secondary: {
          DEFAULT: 'hsl(var(--secondary))',
          foreground: 'hsl(var(--secondary-foreground))',
        },
        accent: {
          DEFAULT: 'hsl(var(--accent))',
          foreground: 'hsl(var(--accent-foreground))',
        },
        destructive: {
          DEFAULT: 'hsl(var(--destructive))',
          foreground: 'hsl(var(--destructive-foreground))',
        },
        success: {
          DEFAULT: 'hsl(var(--success))',
          foreground: 'hsl(var(--success-foreground))',
        },
        warning: {
          DEFAULT: 'hsl(var(--warning))',
          foreground: 'hsl(var(--warning-foreground))',
        },
        /* Alias historiques conservés pour ne rien casser dans les anciens écrans. */
        danger: {
          DEFAULT: 'hsl(var(--destructive))',
          foreground: 'hsl(var(--destructive-foreground))',
        },
        border: 'hsl(var(--border))',
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',
        surface: {
          1: 'hsl(var(--surface-1))',
          2: 'hsl(var(--surface-2))',
        },
        /* Palette nommée de la marque (utile pour les graphiques). */
        sol: {
          50: 'hsl(var(--c-sol-50))',
          100: 'hsl(var(--c-sol-100))',
          200: 'hsl(var(--c-sol-200))',
          300: 'hsl(var(--c-sol-300))',
        },
        foret: {
          600: 'hsl(var(--c-foret-600))',
          700: 'hsl(var(--c-foret-700))',
          800: 'hsl(var(--c-foret-800))',
          900: 'hsl(var(--c-foret-900))',
          950: 'hsl(var(--c-foret-950))',
        },
        or: {
          400: 'hsl(var(--c-or-400))',
          500: 'hsl(var(--c-or-500))',
          600: 'hsl(var(--c-or-600))',
          700: 'hsl(var(--c-or-700))',
        },
        laterite: {
          500: 'hsl(var(--c-laterite-500))',
          600: 'hsl(var(--c-laterite-600))',
        },
        lagune: {
          500: 'hsl(var(--c-lagune-500))',
          600: 'hsl(var(--c-lagune-600))',
        },
        sauge: {
          300: 'hsl(var(--c-sauge-300))',
          500: 'hsl(var(--c-sauge-500))',
          700: 'hsl(var(--c-sauge-700))',
        },
        /* Sous-secteurs agricoles. */
        vegetal: 'hsl(var(--sector-vegetal))',
        animal: 'hsl(var(--sector-animal))',
        halieutique: 'hsl(var(--sector-halieutique))',
        forestier: 'hsl(var(--sector-forestier))',
      },
      fontFamily: {
        sans: ['var(--font-inter)', 'Inter', 'system-ui', 'sans-serif'],
        mono: ['var(--font-jetbrains-mono)', 'JetBrains Mono', 'monospace'],
        display: ['var(--font-display)', 'Playfair Display', 'Georgia', 'serif'],
        heading: ['var(--font-inter)', 'Inter', 'system-ui', 'sans-serif'],
      },
      borderRadius: {
        sm: 'var(--radius-sm)',
        DEFAULT: 'var(--radius)',
        md: 'var(--radius)',
        lg: 'var(--radius)',
        xl: 'var(--radius-lg)',
        '2xl': 'calc(var(--radius-lg) + 0.5rem)',
        card: 'var(--radius)',
        button: 'var(--radius-sm)',
        input: 'var(--radius-sm)',
      },
      boxShadow: {
        xs: 'var(--shadow-xs)',
        sm: 'var(--shadow-sm)',
        DEFAULT: 'var(--shadow-sm)',
        md: 'var(--shadow-md)',
        lg: 'var(--shadow-lg)',
        modal: 'var(--shadow-lg)',
        'glow-green': '0 0 24px hsl(var(--success) / 0.35)',
        'glow-gold': '0 0 24px hsl(var(--secondary) / 0.35)',
        card: 'var(--shadow-xs)',
        'card-hover': 'var(--shadow-md)',
      },
      transitionTimingFunction: {
        DEFAULT: 'var(--ease-in-out-soft)',
        expo: 'var(--ease-out-expo)',
      },
      transitionDuration: {
        DEFAULT: 'var(--dur-base)',
        fast: 'var(--dur-fast)',
        slow: 'var(--dur-slow)',
      },
      zIndex: {
        sticky: 'var(--z-sticky)',
        drawer: 'var(--z-drawer)',
        header: 'var(--z-header)',
        overlay: 'var(--z-overlay)',
        popover: 'var(--z-popover)',
        toast: 'var(--z-toast)',
      },
      spacing: {
        header: 'var(--header-height)',
        sidebar: 'var(--sidebar-width)',
        gutter: '1.25rem',
      },
      maxWidth: {
        content: 'var(--content-width)',
        reading: 'var(--reading-width)',
      },
      screens: {
        xs: '480px',
        '3xl': '1920px',
      },
      animation: {
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'fade-in': 'fadeIn var(--dur-base) var(--ease-out-expo)',
        'slide-up': 'slideUp var(--dur-base) var(--ease-out-expo)',
        'slide-in-right': 'slideInRight var(--dur-base) var(--ease-out-expo)',
        'accordion-down': 'accordion-down 0.2s ease-out',
        'accordion-up': 'accordion-up 0.2s ease-out',
      },
      keyframes: {
        fadeIn: { '0%': { opacity: '0' }, '100%': { opacity: '1' } },
        slideUp: {
          '0%': { transform: 'translateY(10px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        slideInRight: {
          '0%': { transform: 'translateX(100%)', opacity: '0' },
          '100%': { transform: 'translateX(0)', opacity: '1' },
        },
        'accordion-down': {
          from: { height: '0' },
          to: { height: 'var(--radix-accordion-content-height)' },
        },
        'accordion-up': {
          from: { height: 'var(--radix-accordion-content-height)' },
          to: { height: '0' },
        },
      },
    },
  },
  plugins: [require('tailwindcss-animate')],
};

/**
 * Palette figée pour les rendus non CSS (Recharts, PDF, images Open Graph).
 * Identique dans les deux thèmes : c'est la marque, pas une surface d'interface.
 */
const brand = {
  foret: '#0C1810',
  foretClair: '#152219',
  sol: '#FBF8F1',
  creme: '#E4DBC8',
  or: '#C4923A',
  orClair: '#DDA85A',
  laterite: '#B4552D',
  lagune: '#0E7490',
  vegetal: '#4D7C0F',
  animal: '#B4552D',
  halieutique: '#0E7490',
  forestier: '#7C4A22',
  sauge: '#5E7A68',
  vert: '#15803D',
  alerte: '#DC2626',
  info: '#3B82F6',
};

module.exports = config;
module.exports.brand = brand;
