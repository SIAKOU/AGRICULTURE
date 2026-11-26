'use client';

import { useState, useEffect, useRef } from 'react';
import {
  Bell, Search, Menu, LogOut, User, Settings, ChevronDown, Languages, Sun, Moon,
} from 'lucide-react';
import Link from 'next/link';
import { useAuthStore } from '@/stores/auth-store';
import { useUIStore } from '@/stores/ui-store';
import { useAuth } from '@/hooks/use-auth';
import { useCommandPalette } from '@/hooks/use-command-palette';
import { UserAvatar } from '@/components/shared/avatar';
import { cn } from '@/lib/utils';

interface HeaderProps {
  className?: string;
}

/**
 * Barre supérieure du dashboard : recherche (palette de commandes), langue,
 * thème, notifications non lues, menu de compte.
 */
export function Header({ className }: HeaderProps) {
  const { user } = useAuthStore();
  const { setSidebarMobileOpen, unreadNotifications } = useUIStore();
  const { logout } = useAuth();
  const { open: openCommandPalette } = useCommandPalette();
  const [userMenuOpen, setUserMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  // Fermeture du menu au clavier (Échap) et au clic extérieur.
  useEffect(() => {
    if (!userMenuOpen) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setUserMenuOpen(false);
    };
    const onClick = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setUserMenuOpen(false);
      }
    };
    document.addEventListener('keydown', onKey);
    document.addEventListener('mousedown', onClick);
    return () => {
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('mousedown', onClick);
    };
  }, [userMenuOpen]);

  return (
    <header
      className={cn(
        'fixed left-0 right-0 top-0 z-header flex h-header items-center gap-3 border-b border-border bg-background/85 px-3 backdrop-blur-md sm:px-4',
        'lg:left-[var(--sidebar-offset,var(--sidebar-width))]',
        className
      )}
      role="banner"
    >
      <button
        type="button"
        className="flex h-9 w-9 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground lg:hidden"
        onClick={() => setSidebarMobileOpen(true)}
        aria-label="Ouvrir le menu"
      >
        <Menu className="h-5 w-5" />
      </button>

      {/* Recherche → palette de commandes */}
      <button
        type="button"
        onClick={openCommandPalette}
        className="flex h-9 w-full max-w-md items-center gap-2.5 rounded-lg border border-border bg-card px-3 text-sm text-muted-foreground transition-colors hover:border-secondary/40 hover:text-foreground"
        aria-label="Rechercher dans l'application"
      >
        <Search className="h-4 w-4 shrink-0" />
        <span className="truncate">Rechercher une page, un acteur, un marché…</span>
        <kbd className="ml-auto hidden shrink-0 rounded border border-border bg-muted px-1.5 py-0.5 font-mono text-[10px] text-muted-foreground sm:block">
          Ctrl K
        </kbd>
      </button>

      <div className="ml-auto flex items-center gap-1.5">
        <LanguageSwitcherInHeader />
        <ThemeToggleButton />

        <Link
          href="/notifications"
          className="relative flex h-9 w-9 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          aria-label={
            unreadNotifications > 0
              ? `${unreadNotifications} notifications non lues`
              : 'Notifications'
          }
        >
          <Bell className="h-5 w-5" />
          {unreadNotifications > 0 && (
            <span className="absolute right-1 top-1 flex h-4 min-w-[16px] items-center justify-center rounded-full bg-secondary px-0.5 text-[10px] font-bold tabular-nums text-secondary-foreground">
              {unreadNotifications > 9 ? '9+' : unreadNotifications}
            </span>
          )}
        </Link>

        {user && (
          <div className="relative" ref={menuRef}>
            <button
              type="button"
              onClick={() => setUserMenuOpen((open) => !open)}
              className={cn(
                'flex h-9 items-center gap-2 rounded-lg border px-2 text-sm font-medium transition-colors',
                userMenuOpen
                  ? 'border-border bg-card text-foreground'
                  : 'border-transparent text-foreground hover:bg-muted'
              )}
              aria-haspopup="menu"
              aria-expanded={userMenuOpen}
            >
              <UserAvatar name={user.name} email={user.email} avatar={user.avatar} size="xs" />
              <span className="hidden max-w-[120px] truncate text-[13px] md:block">
                {user.name || user.email?.split('@')[0]}
              </span>
              <ChevronDown
                className={cn(
                  'hidden h-3.5 w-3.5 text-muted-foreground transition-transform md:block',
                  userMenuOpen && 'rotate-180'
                )}
              />
            </button>

            {userMenuOpen && (
              <div
                role="menu"
                className="absolute right-0 top-full z-popover mt-1.5 w-56 overflow-hidden rounded-lg border border-border bg-popover py-1.5 shadow-lg animate-in"
              >
                <div className="border-b border-border px-3 py-2.5">
                  <p className="truncate text-sm font-semibold text-foreground">{user.name}</p>
                  <p className="mt-0.5 truncate text-xs text-muted-foreground">{user.email}</p>
                </div>
                <MenuLink href="/settings/profile" icon={User} label="Mon profil" onSelect={() => setUserMenuOpen(false)} />
                <MenuLink href="/settings/preferences" icon={Settings} label="Préférences" onSelect={() => setUserMenuOpen(false)} />
                <div className="mx-3 my-1 border-t border-border" />
                <button
                  type="button"
                  role="menuitem"
                  onClick={() => {
                    setUserMenuOpen(false);
                    logout();
                  }}
                  className="flex w-full items-center gap-2.5 px-3 py-2 text-sm text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive"
                >
                  <LogOut className="h-4 w-4" />
                  Déconnexion
                </button>
              </div>
            )}
          </div>
        )}
      </div>
    </header>
  );
}

function MenuLink({
  href,
  icon: Icon,
  label,
  onSelect,
}: {
  href: string;
  icon: React.ElementType;
  label: string;
  onSelect: () => void;
}) {
  return (
    <Link
      href={href}
      role="menuitem"
      onClick={onSelect}
      className="flex items-center gap-2.5 px-3 py-2 text-sm text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
    >
      <Icon className="h-4 w-4" />
      {label}
    </Link>
  );
}

function LanguageSwitcherInHeader() {
  const [current, setCurrent] = useState<'fr' | 'en'>('fr');
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    if (typeof window !== 'undefined') {
      const stored = localStorage.getItem('agriintel-locale');
      if (stored === 'en' || stored === 'fr') setCurrent(stored);
    }
    setMounted(true);
  }, []);

  const toggle = () => {
    const next = current === 'fr' ? 'en' : 'fr';
    setCurrent(next);
    localStorage.setItem('agriintel-locale', next);
    document.documentElement.lang = next;
    document.cookie = `AGRI_LANG=${next}; path=/; max-age=${365 * 86400}; SameSite=Lax`;
    window.dispatchEvent(new CustomEvent('locale-changed', { detail: next }));
  };

  if (!mounted) return null;

  return (
    <button
      type="button"
      onClick={toggle}
      className="flex h-9 items-center gap-1 rounded-lg px-2 text-xs font-bold uppercase text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
      aria-label={`Changer de langue (actuelle : ${current === 'fr' ? 'français' : 'anglais'})`}
    >
      <Languages className="h-3.5 w-3.5" />
      <span>{current === 'fr' ? 'EN' : 'FR'}</span>
    </button>
  );
}

function ThemeToggleButton() {
  const { theme, toggleTheme } = useUIStore();
  const [isDark, setIsDark] = useState(false);

  useEffect(() => {
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const resolve = () => setIsDark(theme === 'dark' || (theme === 'system' && media.matches));
    resolve();
    media.addEventListener('change', resolve);
    return () => media.removeEventListener('change', resolve);
  }, [theme]);

  return (
    <button
      type="button"
      onClick={toggleTheme}
      className="flex h-9 w-9 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
      aria-label={isDark ? 'Activer le mode clair' : 'Activer le mode sombre'}
    >
      {isDark ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
    </button>
  );
}
