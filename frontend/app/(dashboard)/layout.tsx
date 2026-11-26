'use client';

import { useEffect } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { Sidebar } from '@/components/layout/sidebar';
import { Header } from '@/components/layout/header';
import { MobileNav } from '@/components/layout/mobile-nav';
import { NotificationsProvider } from '@/components/dashboard/notifications-provider';
import { useUIStore } from '@/stores/ui-store';
import { useAuthStore } from '@/stores/auth-store';

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const { sidebarCollapsed } = useUIStore();
  const { isAuthenticated, isLoading } = useAuthStore();
  // `hydrationState` évite de rediriger avant que zustand/persist ait relu le
  // stockage : sans ce garde, un utilisateur connecté atterrissait sur /login
  // lors d'un rechargement (la garde s'exécutait avant la réhydratation).
  const hydrationState = useAuthStore((state) => state.hydrationState);
  const router = useRouter();
  const pathname = usePathname();

  const ready = hydrationState === 'complete' || hydrationState === 'error';

  // Garde de route côté client : l'export statique ne peut pas le faire au serveur.
  useEffect(() => {
    if (ready && !isAuthenticated) {
      const next = encodeURIComponent(pathname ?? '/dashboard');
      router.replace(`/login?next=${next}`);
    }
  }, [ready, isAuthenticated, router, pathname]);

  if (!ready || isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <div className="flex flex-col items-center gap-3" role="status" aria-live="polite">
          <div
            className="h-8 w-8 animate-spin rounded-full border-2 border-primary border-t-transparent"
            aria-hidden="true"
          />
          <p className="text-sm text-muted-foreground">Chargement de votre espace…</p>
        </div>
      </div>
    );
  }

  if (!isAuthenticated) return null;

  return (
    <NotificationsProvider>
      <div
        className="min-h-screen bg-background text-foreground"
        style={
          {
            // Variable locale distincte du jeton global : l'auto-référence
            // `--sidebar-width: var(--sidebar-width)` est un cycle CSS invalide,
            // qui annulait le décalage du contenu et laissait passer la sidebar
            // par-dessus la page.
            '--sidebar-offset': sidebarCollapsed
              ? 'var(--sidebar-width-collapsed)'
              : 'var(--sidebar-width)',
          } as React.CSSProperties
        }
      >
        {/* Accès clavier direct au contenu. */}
        <a
          href="#main-content"
          className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-toast focus:rounded-lg focus:bg-primary focus:px-4 focus:py-2 focus:text-primary-foreground"
        >
          Aller au contenu principal
        </a>

        <div className="hidden lg:block">
          <Sidebar />
        </div>

        <MobileNav />
        <Header />

        <main
          id="main-content"
          tabIndex={-1}
          className="pt-header transition-[padding] duration-200 lg:pl-[var(--sidebar-offset)]"
        >
          {children}
        </main>
      </div>
    </NotificationsProvider>
  );
}
