import { cn } from '@/lib/utils';
import { Breadcrumb } from './breadcrumb';
import { LoadingScreen } from '@/components/shared/loading-screen';
import { ErrorState } from '@/components/shared/error-state';
import { EmptyState, type EmptyStateProps } from '@/components/shared/empty-state';

interface PageShellProps {
  title?: React.ReactNode;
  description?: string;
  actions?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
  noPadding?: boolean;

  /** État de chargement */
  loading?: boolean;
  loadingMessage?: string;

  /** État d'erreur */
  error?: string | null;
  onRetry?: () => void;

  /** État vide */
  empty?: {
    icon?: EmptyStateProps['icon'];
    title: string;
    description?: string;
    action?: EmptyStateProps['action'];
  } | null;
}

/**
 * Gabarit d'écran du dashboard : fil d'Ariane, titre, actions, puis contenu.
 *
 * Règles de rythme :
 *  - largeur maximale `--content-width`, gouttière unique (3 → 6 sur grand écran) ;
 *  - le bloc de titre reste hors du défilement perçu (marge constante) ;
 *  - les états loading / error / empty remplacent le contenu, jamais le titre.
 */
export function PageShell({
  title,
  description,
  actions,
  children,
  className,
  noPadding,
  loading,
  loadingMessage,
  error,
  onRetry,
  empty,
}: PageShellProps) {
  return (
    <div className={cn('mx-auto min-h-full w-full max-w-content', !noPadding && 'px-4 py-5 sm:px-6 sm:py-6', className)}>
      <Breadcrumb className="mb-3" />

      {(title || actions) && (
        <div className="mb-5 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div className="min-w-0">
            {title && (
              <h1 className="truncate text-[1.5rem] font-bold leading-tight tracking-[-0.01em] text-foreground">
                {title}
              </h1>
            )}
            {description && (
              <p className="mt-1 max-w-reading text-sm text-muted-foreground">{description}</p>
            )}
          </div>
          {actions && <div className="flex shrink-0 items-center gap-2">{actions}</div>}
        </div>
      )}

      {loading ? (
        <LoadingScreen message={loadingMessage} />
      ) : error ? (
        <ErrorState message={error} onRetry={onRetry} />
      ) : empty ? (
        <EmptyState
          icon={empty.icon}
          title={empty.title}
          description={empty.description}
          action={empty.action}
        />
      ) : (
        children
      )}
    </div>
  );
}
