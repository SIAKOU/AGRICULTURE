import { cn } from '@/lib/utils';

/**
 * Surface — la seule façon d'empiler un contenu sur la page.
 *
 * Variantes :
 *  - `flat`       : carte posée, filet discret (défaut, listes et formulaires)
 *  - `elevated`   : carte dominante (KPI, encart principal)
 *  - `glass`      : panneau translucide (palette de commandes, tiroirs)
 *  - `interactive`: carte cliquable, avec affordance de survol
 *
 * Ne jamais réécrire `bg-card rounded-xl border shadow-*` à la main : passer par
 * ce composant pour que l'ombre, le rayon et le filet restent alignés partout.
 */
const VARIANTS = {
  flat: 'card-base',
  elevated: 'card-base card-elevated',
  glass: 'surface-glass',
  interactive: 'card-base card-hover',
} as const;

const PADDING = {
  none: '',
  sm: 'p-3',
  md: 'p-4 sm:p-5',
  lg: 'p-6 sm:p-8',
} as const;

export interface SurfaceProps extends React.HTMLAttributes<HTMLElement> {
  variant?: keyof typeof VARIANTS;
  padding?: keyof typeof PADDING;
  as?: 'div' | 'section' | 'article' | 'li' | 'aside';
}

export function Surface({
  variant = 'flat',
  padding = 'md',
  as = 'div',
  className,
  ...props
}: SurfaceProps) {
  const Tag = as as React.ElementType;
  return <Tag className={cn(VARIANTS[variant], PADDING[padding], className)} {...props} />;
}

/** En-tête interne d'une surface : titre + action alignés sur une seule ligne. */
export function SurfaceHeader({
  title,
  description,
  action,
  className,
}: {
  title: React.ReactNode;
  description?: React.ReactNode;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('flex items-start justify-between gap-3 mb-4', className)}>
      <div className="min-w-0">
        <h3 className="text-[0.9375rem] font-semibold leading-tight text-foreground truncate">
          {title}
        </h3>
        {description && (
          <p className="mt-1 text-xs text-muted-foreground line-clamp-2">{description}</p>
        )}
      </div>
      {action && <div className="shrink-0">{action}</div>}
    </div>
  );
}

/** Étiquette de section : l'œil doit distinguer un groupe sans lire le texte. */
export function SectionLabel({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <p
      className={cn(
        'px-2.5 pt-3 pb-1 text-[0.625rem] font-bold uppercase tracking-[0.14em] text-muted-foreground/80',
        className
      )}
    >
      {children}
    </p>
  );
}
