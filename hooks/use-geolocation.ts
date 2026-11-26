'use client';

import { useQuery } from '@tanstack/react-query';
import { apiClient } from '@/lib/api-client';
import { SEVERITY_COLORS, SECTOR_CHART_COLORS } from '@/lib/palette';

export interface MapMarker {
  id: string;
  label: string;
  lng: number;
  lat: number;
  type: 'actor' | 'alert' | 'weather' | 'market' | 'prediction';
  color: string;
  sector?: string;
  description?: string;
}

export function useMapMarkers() {
  return useQuery({
    queryKey: ['map', 'markers'],
    queryFn: async (): Promise<MapMarker[]> => {
      const markers: MapMarker[] = [];

      try {
        const actorsRes = await apiClient.get<{ data?: Array<{ id: string; name: string; latitude?: number; longitude?: number; sector?: string; city?: string }> }>('/actors/', {
          params: { per_page: 100 },
        });
        const actors = Array.isArray(actorsRes) ? actorsRes : actorsRes.data || [];
        const sectorColors: Record<string, string> = SECTOR_CHART_COLORS;
        for (const a of actors) {
          if (a.latitude != null && a.longitude != null) {
            markers.push({
              id: `actor-${a.id}`,
              label: a.name,
              lng: a.longitude,
              lat: a.latitude,
              type: 'actor',
              color: sectorColors[a.sector || 'vegetal'] || SECTOR_CHART_COLORS.vegetal,
              sector: a.sector,
              description: a.city,
            });
          }
        }
      } catch {
        // Aucun repli inventé : une carte vide est honnête, trois faux acteurs
        // à Dakar, Lomé et Accra ne le sont pas. L'écran affiche son état vide.
      }

      try {
        const alertsRes = await apiClient.get<unknown>('/alerts', {
          params: { limit: 50 },
        });
        const alerts = Array.isArray(alertsRes)
          ? alertsRes
          : (alertsRes as { data?: Array<{ id: string; title: string; coordinates?: [number, number]; city?: string }> })?.data || [];
        for (const al of alerts) {
          const coords = (al as { coordinates?: [number, number] }).coordinates;
          if (coords?.length === 2) {
            markers.push({
              id: `alert-${(al as { id: string }).id}`,
              label: (al as { title: string }).title,
              lng: coords[0],
              lat: coords[1],
              type: 'alert',
              color: SEVERITY_COLORS.emergency,
              description: (al as { city?: string }).city,
            });
          }
        }
      } catch {
        // ignore
      }

      return markers;
    },
    staleTime: 5 * 60 * 1000,
  });
}
