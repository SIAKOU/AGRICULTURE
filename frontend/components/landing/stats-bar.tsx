'use client';

import { useRef, useEffect } from 'react';
import { motion, useInView, useMotionValue, useSpring, animate } from '@/lib/motion';

/**
 * Bandeau de résultats — trois chiffres mesurés, séparés par des filets.
 * Toutes les couleurs viennent des jetons : le bandeau fonctionne en clair comme
 * en sombre (l'ancienne version était figée en sombre et illisible en clair).
 */

function AnimatedStat({ value, label, desc }: { value: string; label: string; desc: string }) {
  const ref = useRef<HTMLSpanElement>(null);
  const inView = useInView(ref as React.RefObject<Element>, { once: true, margin: '-100px' });
  const numericValue = parseInt(value.replace(/[^0-9]/g, ''), 10);
  const mv = useMotionValue(0);
  const sv = useSpring(mv, { duration: 2500 });
  const reduced = useRef(false);

  useEffect(() => {
    reduced.current =
      typeof window !== 'undefined' &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  }, []);

  useEffect(() => {
    if (!inView) return;
    if (reduced.current || isNaN(numericValue)) {
      if (ref.current) ref.current.textContent = value;
      return;
    }
    animate(mv, numericValue, { duration: 2.5 });
  }, [inView, mv, numericValue, value]);

  useEffect(() => {
    return sv.on('change', (latest) => {
      if (!ref.current) return;
      const prefix = value.match(/^[^0-9+]*/)?.[0] || '';
      const postfix = value.match(/[^0-9]*$/)?.[0] || '';
      ref.current.textContent = `${prefix}${Math.round(latest).toLocaleString('fr-FR')}${postfix}`;
    });
  }, [sv, value]);

  return (
    <motion.div
      className="px-6 py-2 text-center sm:px-10"
      initial={{ opacity: 0, y: 16 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true }}
      transition={{ duration: 0.55, ease: [0.23, 1, 0.32, 1] }}
    >
      <p className="mb-3 font-display text-[clamp(2.5rem,6vw,3.25rem)] font-bold leading-none tracking-[-0.04em] text-foreground tabular">
        <span ref={ref}>{value}</span>
        <span className="text-secondary">{label}</span>
      </p>
      <p className="mx-auto max-w-[24ch] text-sm leading-relaxed text-muted-foreground">{desc}</p>
    </motion.div>
  );
}

const STATS_DATA = [
  { value: '82', label: '%', desc: 'de réduction du risque climato-agricole grâce aux alertes préventives' },
  { value: '+34', label: '%', desc: "d'amélioration du rendement moyen chez les utilisateurs actifs" },
  { value: '12', label: '+', desc: "pays d'Afrique subsaharienne couverts par notre réseau de données" },
];

export function AnimatedStatsBar() {
  return (
    <section
      aria-label="Résultats mesurés sur le terrain"
      className="border-y border-border bg-surface-2 py-16 sm:py-20"
    >
      <div className="mx-auto max-w-content px-4 sm:px-6">
        <motion.div
          className="mb-12 text-center"
          initial={{ opacity: 0, y: 10 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
        >
          <p className="landing-eyebrow mb-3">Résultats mesurés sur le terrain</p>
          <h2 className="font-display text-[clamp(1.75rem,3.5vw,2.625rem)] font-bold tracking-[-0.025em] text-foreground">
            Des données qui améliorent
            <br />
            chaque saison agricole.
          </h2>
        </motion.div>

        <div className="grid grid-cols-1 gap-8 sm:grid-cols-3 sm:gap-0 sm:divide-x sm:divide-border">
          {STATS_DATA.map((stat) => (
            <AnimatedStat key={stat.value} {...stat} />
          ))}
        </div>
      </div>
    </section>
  );
}
