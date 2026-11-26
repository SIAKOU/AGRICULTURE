'use client';

import Link from 'next/link';
import { formatDistanceToNow, parseISO } from 'date-fns';
import { fr } from 'date-fns/locale';
import { Bell, ArrowRight, Check } from 'lucide-react';
import { SeverityBadge } from '@/components/shared/severity-badge';
import { SectorBadge } from '@/components/shared/sector-badge';
import { useAlerts } from '@/hooks/use-alerts';
import { useMarkAlertRead } from '@/hooks/use-alerts';
import type { Alert, AlertSeverity } from '@/types/alert';
import type { PaginatedResponse } from '@/types/api';

const severityBorderColors: Record<AlertSeverity, string> = {
  info: '#3b82f6',
  warning: '#eab308',
  critical: '#f97316',
  emergency: '#ef4444',
};

function SkeletonItem() {
  return (
    <div
      className="rounded-xl p-3 animate-pulse"
      style={{ background: 'rgba(196,146,58,0.06)', height: '64px' }}
    />
  );
}

export function AlertsTicker() {
  const { data, isLoading } = useAlerts({ is_read: false });
  const markRead = useMarkAlertRead();
  const paginated = data && 'data' in data ? (data as PaginatedResponse<Alert>) : null;
  const alerts = paginated?.data?.slice(0, 5) ?? (Array.isArray(data) ? (data as Alert[]).slice(0, 5) : []);

  if (isLoading) {
    return (
      <div
        className="rounded-xl p-4 space-y-2"
        style={{ background: 'hsl(var(--card))', border: '1px solid rgba(196,146,58,0.14)' }}
      >
        <div className="h-5 w-40 rounded-full mb-3 animate-pulse" style={{ background: 'rgba(196,146,58,0.10)' }} />
        {Array.from({ length: 3 }).map((_, i) => <SkeletonItem key={i} />)}
      </div>
    );
  }

  return (
    <div
      className="rounded-xl flex flex-col"
      style={{ background: 'hsl(var(--card))', border: '1px solid rgba(196,146,58,0.14)' }}
    >
      {/* Header */}
      <div
        className="px-4 py-3 flex items-center justify-between"
        style={{ borderBottom: '1px solid rgba(196,146,58,0.10)' }}
      >
        <div className="flex items-center gap-2">
          <Bell className="h-4 w-4" style={{ color: 'hsl(var(--secondary))' }} />
          <span className="text-sm font-semibold" style={{ color: 'hsl(var(--foreground))' }}>Dernières Alertes</span>
          {paginated?.total ? (
            <span
              className="text-[10px] font-bold px-1.5 py-0.5 rounded-full"
              style={{ background: 'hsl(var(--secondary))', color: 'hsl(var(--surface-2))' }}
            >
              {paginated.total}
            </span>
          ) : null}
        </div>
      </div>

      {/* Content */}
      <div className="p-3 space-y-2 flex-1">
        {alerts.length === 0 ? (
          <p className="text-sm text-center py-4" style={{ color: 'hsl(var(--muted-foreground))' }}>
            Aucune alerte active 🎉
          </p>
        ) : (
          alerts.map((alert) => (
            <div
              key={alert.id}
              className="pl-3 py-2.5 pr-2 rounded-r-xl flex items-start justify-between gap-2"
              style={{
                background: 'rgba(12,24,16,0.60)',
                border: '1px solid rgba(196,146,58,0.08)',
                borderLeft: `3px solid ${severityBorderColors[alert.severity]}`,
                borderRadius: '0 10px 10px 0',
              }}
            >
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap mb-0.5">
                  <SeverityBadge severity={alert.severity} />
                  {alert.sector && <SectorBadge sector={alert.sector} />}
                </div>
                <p className="text-sm font-medium truncate" style={{ color: 'hsl(var(--foreground))' }}>{alert.title}</p>
                <p className="text-xs" style={{ color: 'hsl(var(--muted-foreground))' }}>
                  {formatDistanceToNow(parseISO(alert.created_at), { addSuffix: true, locale: fr })}
                </p>
              </div>
              <div className="flex gap-1 shrink-0">
                <button
                  className="h-7 w-7 flex items-center justify-center rounded-lg transition-all duration-150"
                  style={{ color: 'hsl(var(--muted-foreground))' }}
                  onClick={() => markRead.mutate(alert.id)}
                  aria-label="Marquer comme lu"
                  onMouseEnter={e => {
                    (e.currentTarget as HTMLElement).style.background = 'rgba(196,146,58,0.10)';
                    (e.currentTarget as HTMLElement).style.color = 'hsl(var(--secondary))';
                  }}
                  onMouseLeave={e => {
                    (e.currentTarget as HTMLElement).style.background = 'transparent';
                    (e.currentTarget as HTMLElement).style.color = 'hsl(var(--muted-foreground))';
                  }}
                >
                  <Check className="h-3.5 w-3.5" />
                </button>
                <Link
                  href={`/alerts/${alert.id}`}
                  className="h-7 w-7 flex items-center justify-center rounded-lg transition-all duration-150"
                  style={{ color: 'hsl(var(--muted-foreground))' }}
                  aria-label="Voir le détail"
                  onMouseEnter={e => {
                    (e.currentTarget as HTMLElement).style.background = 'rgba(196,146,58,0.10)';
                    (e.currentTarget as HTMLElement).style.color = 'hsl(var(--secondary))';
                  }}
                  onMouseLeave={e => {
                    (e.currentTarget as HTMLElement).style.background = 'transparent';
                    (e.currentTarget as HTMLElement).style.color = 'hsl(var(--muted-foreground))';
                  }}
                >
                  <ArrowRight className="h-3.5 w-3.5" />
                </Link>
              </div>
            </div>
          ))
        )}

        <Link
          href="/alerts"
          className="w-full flex items-center justify-center gap-1.5 h-8 rounded-xl text-xs font-medium mt-2 transition-all duration-150"
          style={{ color: 'hsl(var(--muted-foreground))' }}
          onMouseEnter={e => {
            (e.currentTarget as HTMLElement).style.background = 'rgba(196,146,58,0.06)';
            (e.currentTarget as HTMLElement).style.color = 'hsl(var(--secondary))';
          }}
          onMouseLeave={e => {
            (e.currentTarget as HTMLElement).style.background = 'transparent';
            (e.currentTarget as HTMLElement).style.color = 'hsl(var(--muted-foreground))';
          }}
        >
          Voir toutes les alertes
          <ArrowRight className="h-3 w-3" />
        </Link>
      </div>
    </div>
  );
}
