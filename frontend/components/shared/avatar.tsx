'use client';

import { cn } from '@/lib/utils';

const SIZES = {
  xs: 'h-6 w-6 text-[10px]',
  sm: 'h-7 w-7 text-xs',
  md: 'h-9 w-9 text-sm',
  lg: 'h-11 w-11 text-base',
} as const;

export interface UserAvatarProps {
  name?: string | null;
  email?: string | null;
  avatar?: string | null;
  size?: keyof typeof SIZES;
  className?: string;
}

/**
 * Avatar utilisateur : photo si disponible, sinon initiale sur fond or.
 * Remplace les trois implémentations dupliquées (header, sidebar, profil).
 */
export function UserAvatar({ name, email, avatar, size = 'md', className }: UserAvatarProps) {
  const label = (name || email || 'U').trim();
  const initial = label.charAt(0).toUpperCase();

  return (
    <span
      className={cn(
        'relative inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full font-bold select-none',
        SIZES[size],
        !avatar && 'bg-secondary text-secondary-foreground',
        avatar && 'bg-muted',
        className
      )}
      aria-hidden={Boolean(avatar)}
    >
      {avatar ? (
        /* eslint-disable-next-line @next/next/no-img-element */
        <img src={avatar} alt={label} className="h-full w-full object-cover" loading="lazy" />
      ) : (
        initial
      )}
    </span>
  );
}
