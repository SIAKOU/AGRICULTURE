'use client';

import Link from 'next/link';
import Image from 'next/image';
import { usePathname } from 'next/navigation';
import { motion, AnimatePresence } from '@/lib/motion';
import {
  LayoutDashboard, Sprout, Beef, Fish, TreePine, Users,
  BarChart3, Brain, CloudSun, TrendingUp, Bell, Bot, MessageSquare,
  Map, FolderOpen, Settings, Shield, ChevronLeft, ChevronRight,
  LogOut, Wallet, CalendarDays, FileText, ArrowLeftRight, Coins,
} from 'lucide-react';
import { useUIStore } from '@/stores/ui-store';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { useAuthStore } from '@/stores/auth-store';
import { useAuth } from '@/hooks/use-auth';
import { useUnreadMessageCount } from '@/hooks/use-messaging';
import { UserAvatar } from '@/components/shared/avatar';
import { SectionLabel } from '@/components/ui/surface';
import { cn } from '@/lib/utils';

type NavItem = {
  href?: string;
  icon?: React.ElementType;
  label?: string;
  exact?: boolean;
  badgeKey?: 'alerts' | 'messages';
};

type NavGroup = { label: string; items: NavItem[] };

/**
 * Navigation du produit — une entrée pour chaque écran existant de `app/`.
 * Toute nouvelle page doit être ajoutée ici, sinon elle est inaccessible : les
 * routes ne sont pas déduites du système de fichiers (export statique).
 */
const NAV_GROUPS: NavGroup[] = [
  {
    label: 'Vue d’ensemble',
    items: [{ href: '/dashboard', icon: LayoutDashboard, label: 'Tableau de bord', exact: true }],
  },
  {
    label: 'Production',
    items: [
      { href: '/production', icon: Sprout, label: 'Végétal' },
      { href: '/animal', icon: Beef, label: 'Animal' },
      { href: '/halieutique', icon: Fish, label: 'Halieutique' },
      { href: '/forestier', icon: TreePine, label: 'Forestier' },
    ],
  },
  {
    label: 'Marchés & analyse',
    items: [
      { href: '/markets', icon: TrendingUp, label: 'Marchés' },
      { href: '/markets/compare', icon: ArrowLeftRight, label: 'Comparer' },
      { href: '/economics', icon: Coins, label: 'Économie' },
      { href: '/indicators', icon: BarChart3, label: 'Indicateurs' },
      { href: '/analytics', icon: TrendingUp, label: 'Analytics' },
      { href: '/predictions', icon: Brain, label: 'Prédictions IA' },
      { href: '/reports', icon: FileText, label: 'Rapports' },
    ],
  },
  {
    label: 'Terrain',
    items: [
      { href: '/weather', icon: CloudSun, label: 'Météo' },
      { href: '/alerts', icon: Bell, label: 'Alertes', badgeKey: 'alerts' },
      { href: '/map', icon: Map, label: 'Carte' },
      { href: '/calendar', icon: CalendarDays, label: 'Calendrier' },
    ],
  },
  {
    label: 'Collaboration',
    items: [
      { href: '/actors', icon: Users, label: 'Acteurs' },
      { href: '/chatbot', icon: Bot, label: 'AgriBot IA' },
      { href: '/messages', icon: MessageSquare, label: 'Messages', badgeKey: 'messages' },
      { href: '/community', icon: Users, label: 'Communauté' },
      { href: '/files', icon: FolderOpen, label: 'Fichiers' },
    ],
  },
  {
    label: 'Compte',
    items: [
      { href: '/payments', icon: Wallet, label: 'Abonnement' },
      { href: '/notifications', icon: Bell, label: 'Notifications' },
      { href: '/settings', icon: Settings, label: 'Paramètres' },
    ],
  },
];

const ADMIN_ITEMS: NavItem[] = [{ href: '/admin', icon: Shield, label: 'Administration' }];

export function Sidebar() {
  const pathname = usePathname();
  const { sidebarCollapsed, toggleSidebar, unreadNotifications } = useUIStore();
  const { user } = useAuthStore();
  const { logout } = useAuth();
  const { data: msgUnreadData } = useUnreadMessageCount();
  const unreadMessages = msgUnreadData?.unread_count ?? 0;

  const isActive = (href: string, exact?: boolean) => {
    if (exact) return pathname === href;
    if (pathname === href) return true;
    if (!pathname.startsWith(`${href}/`)) return false;
    // Une entrée enfant plus précise (ex. /markets/compare) porte seule l'état actif.
    const childOwnsPath = NAV_GROUPS.some((g) =>
      g.items.some((i) => i.href !== href && i.href?.startsWith(`${href}/`) && pathname === i.href)
    );
    return !childOwnsPath;
  };

  const badgeFor = (item: NavItem) => {
    if (item.badgeKey === 'alerts') return unreadNotifications;
    if (item.badgeKey === 'messages') return unreadMessages;
    return 0;
  };

  const renderItem = (item: NavItem, tone: 'default' | 'admin' = 'default') => {
    const Icon = item.icon!;
    const active = isActive(item.href!, item.exact);
    const count = badgeFor(item);
    const showCount = !sidebarCollapsed && count > 0;

    const link = (
      <Link
        href={item.href!}
        aria-current={active ? 'page' : undefined}
        className={cn(
          'group relative flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-[0.8125rem] font-medium transition-colors duration-150',
          tone === 'admin'
            ? active
              ? 'bg-destructive/10 text-destructive'
              : 'text-muted-foreground hover:bg-muted/60 hover:text-destructive'
            : active
              ? 'bg-secondary/12 text-foreground'
              : 'text-muted-foreground hover:bg-muted/60 hover:text-foreground'
        )}
      >
        {/* Rail d'état actif : la position suffit, pas besoin de gras + couleur. */}
        {tone === 'default' && (
          <span
            aria-hidden
            className={cn(
              'absolute left-0 top-1/2 h-4 w-[3px] -translate-y-1/2 rounded-full transition-opacity duration-150',
              active ? 'bg-secondary opacity-100' : 'opacity-0'
            )}
          />
        )}
        <Icon className="h-4 w-4 shrink-0" />
        <AnimatePresence initial={false}>
          {!sidebarCollapsed && (
            <motion.span
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="flex-1 truncate whitespace-nowrap"
            >
              {item.label}
            </motion.span>
          )}
        </AnimatePresence>
        {showCount && (
          <span
            className={cn(
              'shrink-0 rounded-full px-1.5 text-[10px] font-bold leading-4 tabular-nums',
              tone === 'admin'
                ? 'bg-destructive text-destructive-foreground'
                : 'bg-secondary/15 text-secondary'
            )}
          >
            {count > 99 ? '99+' : count}
          </span>
        )}
      </Link>
    );

    if (sidebarCollapsed) {
      return (
        <Tooltip key={item.href}>
          <TooltipTrigger asChild>{link}</TooltipTrigger>
          <TooltipContent side="right">{item.label}</TooltipContent>
        </Tooltip>
      );
    }
    return <div key={item.href}>{link}</div>;
  };

  return (
    <TooltipProvider delayDuration={0}>
      <motion.aside
        animate={{ width: sidebarCollapsed ? 64 : 240 }}
        transition={{ duration: 0.2, ease: 'easeOut' }}
        className="fixed left-0 top-0 z-drawer flex h-full flex-col overflow-hidden border-r border-border bg-background"
        aria-label="Navigation principale"
      >
        {/* Marque */}
        <div className="flex h-header shrink-0 items-center border-b border-border px-3">
          <Link href="/dashboard" className="flex w-full min-w-0 items-center gap-2.5">
            <span className="relative flex h-9 w-9 shrink-0 items-center justify-center overflow-hidden rounded-xl border border-secondary/30 bg-secondary/10">
              <Image src="/logo.png" alt="" fill className="object-contain p-1.5" sizes="36px" />
            </span>
            {!sidebarCollapsed && (
              <span className="min-w-0 overflow-hidden">
                <span className="block whitespace-nowrap text-[0.9375rem] font-black leading-none tracking-tight text-foreground">
                  AgriIntel<span className="text-secondary">360</span>
                </span>
                <span className="mt-0.5 block whitespace-nowrap text-[0.5625rem] font-bold uppercase tracking-[0.16em] text-muted-foreground/70">
                  Intelligence Agricole
                </span>
              </span>
            )}
          </Link>
        </div>

        {/* Navigation */}
        <nav
          className="flex-1 overflow-y-auto px-2 py-2"
          aria-label="Menu principal"
          style={{ scrollbarWidth: 'none' }}
        >
          {NAV_GROUPS.map((group) => (
            <div key={group.label} className="mb-1">
              {!sidebarCollapsed && <SectionLabel>{group.label}</SectionLabel>}
              <div className="space-y-0.5">{group.items.map((item) => renderItem(item))}</div>
            </div>
          ))}

          {user?.role === 'admin' && (
            <div className="mt-2 border-t border-border pt-2">
              {!sidebarCollapsed && <SectionLabel>Administration</SectionLabel>}
              <div className="space-y-0.5">
                {ADMIN_ITEMS.map((item) => renderItem(item, 'admin'))}
              </div>
            </div>
          )}
        </nav>

        {/* Compte */}
        {user && (
          <div className="shrink-0 border-t border-border px-2 py-2">
            {!sidebarCollapsed ? (
              <>
                <Link
                  href="/settings/profile"
                  className="mb-1 flex items-center gap-2.5 rounded-lg px-2 py-2 transition-colors hover:bg-muted/60"
                >
                  <UserAvatar name={user.name} email={user.email} avatar={user.avatar} size="sm" />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-xs font-semibold text-foreground">
                      {user.name || user.email?.split('@')[0] || 'Utilisateur'}
                    </span>
                    <span className="block truncate text-[10px] text-muted-foreground/80">
                      {user.email}
                    </span>
                  </span>
                </Link>
                <div className="flex gap-1">
                  <Link
                    href="/settings/profile"
                    className="flex flex-1 items-center justify-center gap-1.5 rounded-lg py-1.5 text-xs font-medium text-muted-foreground transition-colors hover:bg-muted/60 hover:text-foreground"
                  >
                    <Settings className="h-3 w-3" />
                    Paramètres
                  </Link>
                  <button
                    type="button"
                    onClick={() => logout()}
                    className="flex flex-1 items-center justify-center gap-1.5 rounded-lg py-1.5 text-xs font-medium text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive"
                  >
                    <LogOut className="h-3 w-3" />
                    Quitter
                  </button>
                </div>
              </>
            ) : (
              <Tooltip>
                <TooltipTrigger asChild>
                  <Link
                    href="/settings/profile"
                    className="flex w-full items-center justify-center rounded-lg p-1.5"
                    aria-label="Mon profil"
                  >
                    <UserAvatar name={user.name} email={user.email} avatar={user.avatar} size="sm" />
                  </Link>
                </TooltipTrigger>
                <TooltipContent side="right">{user.name || user.email}</TooltipContent>
              </Tooltip>
            )}
          </div>
        )}

        {/* Repli */}
        <div className="shrink-0 border-t border-border p-2">
          <button
            type="button"
            onClick={toggleSidebar}
            className="flex h-8 w-full items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-muted/60 hover:text-secondary"
            aria-label={sidebarCollapsed ? 'Étendre la navigation' : 'Réduire la navigation'}
            aria-expanded={!sidebarCollapsed}
          >
            {sidebarCollapsed ? <ChevronRight className="h-4 w-4" /> : <ChevronLeft className="h-4 w-4" />}
          </button>
        </div>
      </motion.aside>
    </TooltipProvider>
  );
}
