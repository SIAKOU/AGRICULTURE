/**
 * Session d'authentification côté navigateur.
 *
 * Principe de sécurité : **aucun jeton ne transite par un stockage lisible en
 * JavaScript**. Le backend pose déjà un cookie `HttpOnly` (voir
 * `backend/api/routers/auth.py`, `set_cookie(httponly=True, samesite="lax")`) ;
 * c'est lui qui authentifie les appels, grâce à `credentials: 'include'` dans
 * `lib/api-client.ts`.
 *
 * Conserver une copie du jeton dans `sessionStorage` (ou pire dans un cookie
 * écrit en JS) annulait le bénéfice du `HttpOnly` : une faille XSS pouvait lire
 * la valeur et l'exfiltrer. On ne garde donc ici qu'un **marqueur de session**
 * non sensible : instant d'expiration, pour l'affichage et le minuteur local.
 *
 * Cas particulier du développement local sans proxy : si
 * `NEXT_PUBLIC_ALLOW_JS_TOKEN=true`, l'ancien comportement est restauré
 * explicitement. Ce drapeau ne doit jamais être activé en production.
 */

const SESSION_MARKER_KEY = 'session_expires_at';
/** Ancien emplacement du jeton : purgé à chaque démarrage. */
const LEGACY_TOKEN_KEY = 'session_token';
const LEGACY_COOKIE = 'access_token';

const ALLOW_JS_TOKEN = process.env.NEXT_PUBLIC_ALLOW_JS_TOKEN === 'true';

export function persistAuthSession(accessToken: string, _refreshToken?: string, expiresIn = 3600) {
  if (typeof window === 'undefined') return;

  // Purge systématique d'une éventuelle trace laissée par l'ancienne version.
  try {
    sessionStorage.removeItem(LEGACY_TOKEN_KEY);
    document.cookie = `${LEGACY_COOKIE}=; max-age=0; path=/`;
  } catch {
    /* stockage indisponible (mode privé strict) */
  }

  try {
    sessionStorage.setItem(SESSION_MARKER_KEY, String(Date.now() + expiresIn * 1000));
  } catch {
    /* sans marqueur, l'interface se fie au cookie */
  }

  if (ALLOW_JS_TOKEN) {
    // Développement uniquement : en-tête Authorization côté client.
    sessionStorage.setItem(LEGACY_TOKEN_KEY, accessToken);
  }
}

export function clearAuthSession() {
  if (typeof window === 'undefined') return;

  sessionStorage.removeItem(SESSION_MARKER_KEY);
  sessionStorage.removeItem(LEGACY_TOKEN_KEY);
  document.cookie = `${LEGACY_COOKIE}=; max-age=0; path=/`;

  // Purge des caches et du service worker : un jeton ou une réponse d'API mise
  // en cache ne doit pas survivre à une déconnexion.
  try {
    if ('caches' in window) {
      caches.keys().then((keys) => Promise.all(keys.map((k) => caches.delete(k))));
    }
  } catch {
    // ignore
  }

  try {
    if (navigator && 'serviceWorker' in navigator) {
      navigator.serviceWorker
        .getRegistrations()
        .then((regs) => regs.forEach((r) => r.unregister()));
    }
  } catch {
    // ignore
  }
}

/**
 * Jeton d'accès accessible au JavaScript.
 *
 * Renvoie `null` en production : l'authentification repose sur le cookie
 * `HttpOnly`. Le drapeau `NEXT_PUBLIC_ALLOW_JS_TOKEN` existe uniquement pour
 * les environnements de développement sans proxy d'API.
 */
export function getStoredAccessToken(): string | null {
  if (typeof window === 'undefined') return null;
  if (!ALLOW_JS_TOKEN) return null;
  return sessionStorage.getItem(LEGACY_TOKEN_KEY);
}

/** Le navigateur pense-t-il avoir encore une session ? (marqueur local) */
export function hasLocalSessionMarker(): boolean {
  if (typeof window === 'undefined') return false;
  try {
    const raw = sessionStorage.getItem(SESSION_MARKER_KEY);
    if (!raw) return false;
    return Number(raw) > Date.now();
  } catch {
    return false;
  }
}

export function getSessionExpiry(): number | null {
  if (typeof window === 'undefined') return null;
  try {
    const raw = sessionStorage.getItem(SESSION_MARKER_KEY);
    return raw ? Number(raw) : null;
  } catch {
    return null;
  }
}
