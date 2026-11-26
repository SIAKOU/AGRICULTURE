'use client';

import { useRef, useState, useCallback } from 'react';
import { cn } from '@/lib/utils';

/**
 * Surface3D — carte à relief réel (CSS 3D, aucun WebGL).
 *
 * Le relief suit le pointeur : rotation X/Y de quelques degrés, ombre portée
 * décalée dans le sens de l'inclinaison, reflet discret qui balaie la surface.
 * L'effet est **désactivé** si `prefers-reduced-motion: reduce` ou sur pointeur
 * grossier (tactile), où il n'apporte rien et coûte des re-rendus.
 *
 * Pourquoi CSS et pas une scène WebGL : une carte de contenu n'a pas besoin de
 * 60 fps de rastérisation ; 220 ms de transition GPU coûtent moins de 1 Ko de
 * JavaScript et restent lisibles sur un téléphone d'entrée de gamme.
 */

export interface Surface3DProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Amplitude de l'inclinaison en degrés (4 par défaut). */
  intensity?: number;
  /** Élévation au survol en pixels (6 par défaut). */
  lift?: number;
  /** Reflet lumineux qui suit le pointeur. */
  glare?: boolean;
  children: React.ReactNode;
}

function prefersReducedMotion(): boolean {
  return (
    typeof window !== 'undefined' &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches
  );
}

function isCoarsePointer(): boolean {
  return typeof window !== 'undefined' && window.matchMedia('(pointer: coarse)').matches;
}

export function Surface3D({
  intensity = 4,
  lift = 6,
  glare = true,
  className,
  children,
  ...props
}: Surface3DProps) {
  const ref = useRef<HTMLDivElement>(null);
  const frame = useRef<number | null>(null);
  const [style, setStyle] = useState<React.CSSProperties>({});
  const [glareAt, setGlareAt] = useState<{ x: number; y: number } | null>(null);

  const reset = useCallback(() => {
    if (frame.current) cancelAnimationFrame(frame.current);
    setStyle({
      transform: 'perspective(900px) rotateX(0deg) rotateY(0deg) translateZ(0)',
      boxShadow: 'var(--shadow-sm)',
    });
    setGlareAt(null);
  }, []);

  const onPointerMove = useCallback(
    (event: React.PointerEvent<HTMLDivElement>) => {
      if (prefersReducedMotion() || isCoarsePointer()) return;
      const node = ref.current;
      if (!node) return;
      const rect = node.getBoundingClientRect();
      const px = (event.clientX - rect.left) / rect.width;
      const py = (event.clientY - rect.top) / rect.height;
      const rotateY = (px - 0.5) * intensity * 2;
      const rotateX = (0.5 - py) * intensity * 2;

      // Une seule écriture par image : évite de saturer le thread principal.
      if (frame.current) cancelAnimationFrame(frame.current);
      frame.current = requestAnimationFrame(() => {
        setStyle({
          transform: `perspective(900px) rotateX(${rotateX.toFixed(2)}deg) rotateY(${rotateY.toFixed(
            2
          )}deg) translateZ(${lift}px)`,
          boxShadow: `var(--shadow-md), ${(-rotateY * 0.6).toFixed(1)}px ${(
            rotateX * 0.6
          ).toFixed(1)}px 28px hsl(var(--foreground) / 0.08)`,
          '--glare-x': `${(px * 100).toFixed(1)}%`,
          '--glare-y': `${(py * 100).toFixed(1)}%`,
        } as React.CSSProperties);
        setGlareAt({ x: px, y: py });
      });
    },
    [intensity, lift]
  );

  return (
    <div
      ref={ref}
      onPointerMove={onPointerMove}
      onPointerLeave={reset}
      onBlur={reset}
      className={cn(
        'card-base relative isolate overflow-hidden will-change-transform',
        'transition-[transform,box-shadow] duration-200 [transition-timing-function:var(--ease-out-expo)]',
        'motion-reduce:transform-none motion-reduce:transition-none',
        className
      )}
      style={{ ...style, transformStyle: 'preserve-3d' }}
      {...props}
    >
      {glare && glareAt && (
        <span
          aria-hidden
          className="pointer-events-none absolute inset-0 z-10 opacity-70 transition-opacity duration-200"
          style={{
            background: `radial-gradient(220px circle at var(--glare-x,50%) var(--glare-y,50%), hsl(var(--secondary) / 0.14), transparent 65%)`,
          }}
        />
      )}
      <div style={{ transform: 'translateZ(0)' }}>{children}</div>
    </div>
  );
}

/**
 * Profondeur en couches — trois plans qui réagissent différemment au survol.
 * Utilisé pour le héros de la page publique (arrière-plan, sujet, contenu).
 */
export function DepthLayers({
  background,
  midground,
  content,
  className,
}: {
  background?: React.ReactNode;
  midground?: React.ReactNode;
  content: React.ReactNode;
  className?: string;
}) {
  const [pointer, setPointer] = useState({ x: 0, y: 0 });

  return (
    <div
      className={cn('relative [perspective:1200px] [transform-style:preserve-3d]', className)}
      onPointerMove={(event) => {
        if (prefersReducedMotion() || isCoarsePointer()) return;
        const rect = event.currentTarget.getBoundingClientRect();
        setPointer({
          x: (event.clientX - rect.left) / rect.width - 0.5,
          y: (event.clientY - rect.top) / rect.height - 0.5,
        });
      }}
      onPointerLeave={() => setPointer({ x: 0, y: 0 })}
    >
      {background && (
        <div
          aria-hidden
          className="absolute inset-0 -z-30 transition-transform duration-300 ease-out"
          style={{
            transform: `translate3d(${pointer.x * 10}px, ${pointer.y * 8}px, -140px) scale(1.06)`,
          }}
        >
          {background}
        </div>
      )}
      {midground && (
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 -z-20 transition-transform duration-300 ease-out"
          style={{ transform: `translate3d(${pointer.x * -18}px, ${pointer.y * -12}px, -60px)` }}
        >
          {midground}
        </div>
      )}
      <div
        className="relative transition-transform duration-300 ease-out"
        style={{ transform: `translate3d(${pointer.x * 6}px, ${pointer.y * 4}px, 40px)` }}
      >
        {content}
      </div>
    </div>
  );
}
