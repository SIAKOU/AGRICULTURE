/**
 * Tests du client d'API (`lib/api-client.ts`).
 *
 * Contrat réel vérifié ici :
 *  - le jeton vient de `sessionStorage.session_token`, avec repli sur le cookie
 *    `access_token` (voir `lib/auth-session.ts` et `getAuthToken`) ;
 *  - les en-têtes `Content-Type` / `Accept` sont toujours envoyés ;
 *  - une réponse non 2xx lève une `ApiError`.
 */

import { ApiClient } from '@/lib/api-client';
import { mockResponse, mockErrorResponse } from './helpers/http';

const mockFetch = jest.fn();

beforeEach(() => {
  mockFetch.mockReset();
  global.fetch = mockFetch as unknown as typeof fetch;
  sessionStorage.clear();
  document.cookie = 'access_token=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/';
  mockFetch.mockResolvedValue(mockResponse({ ok: true }));
});

describe('ApiClient — construction des requêtes', () => {
  it('instancie un client', () => {
    expect(new ApiClient()).toBeDefined();
  });

  it("n'envoie aucun jeton lisible par JavaScript (cookie HttpOnly uniquement)", async () => {
    // Sécurité : même si un jeton traîne dans sessionStorage, il ne doit pas
    // partir dans un en-tête — c'est le cookie HttpOnly qui authentifie.
    sessionStorage.setItem('session_token', 'test-jwt-token');
    document.cookie = 'access_token=cookie-token; path=/';

    mockFetch.mockImplementation(async (_url: string, opts: RequestInit) => {
      const headers = opts.headers as Record<string, string>;
      return mockResponse({
        hasAuthorizationHeader: Boolean(headers?.Authorization),
        credentials: opts.credentials,
      });
    });

    const result = await new ApiClient().get<{
      hasAuthorizationHeader: boolean;
      credentials: string;
    }>('/api/v1/auth/me');

    expect(result.hasAuthorizationHeader).toBe(false);
    // Le cookie est envoyé par le navigateur, pas par le code applicatif.
    expect(result.credentials).toBe('include');
  });

  it("n'envoie pas d'en-tête d'authentification sans jeton", async () => {
    mockFetch.mockImplementation(async (_url: string, opts: RequestInit) => {
      const headers = opts.headers as Record<string, string>;
      return mockResponse({ hasAuth: Boolean(headers?.Authorization) });
    });

    const result = await new ApiClient().get<{ hasAuth: boolean }>('/api/v1/auth/me');
    expect(result.hasAuth).toBe(false);
  });

  it('envoie un corps JSON en POST', async () => {
    mockFetch.mockImplementation(async (_url: string, opts: RequestInit) => {
      const body = JSON.parse(opts.body as string);
      return mockResponse({ received: body });
    });

    const payload = { email: 'test@example.com', password: 'secret' };
    const result = await new ApiClient().post<{ received: typeof payload }>(
      '/api/v1/auth/login',
      payload
    );
    expect(result.received.email).toBe('test@example.com');
  });

  it('inclut les en-têtes Content-Type et Accept', async () => {
    mockFetch.mockImplementation(async (_url: string, opts: RequestInit) => {
      const headers = opts.headers as Record<string, string>;
      return mockResponse({
        contentType: headers['Content-Type'],
        accept: headers['Accept'],
      });
    });

    const result = await new ApiClient().get<{ contentType: string; accept: string }>(
      '/api/v1/health'
    );
    expect(result.contentType).toBe('application/json');
    expect(result.accept).toBe('application/json');
  });

  it('ajoute les paramètres de requête à l’URL', async () => {
    mockFetch.mockImplementation(async (url: string) => mockResponse({ url }));

    const result = await new ApiClient().get<{ url: string }>('/api/v1/users', {
      params: { page: 1, limit: 20 },
    });
    expect(result.url).toContain('page=1');
    expect(result.url).toContain('limit=20');
  });
});

describe('ApiClient — gestion des erreurs', () => {
  it('lève une erreur sur une réponse 401', async () => {
    mockFetch.mockResolvedValue(mockErrorResponse(401, 'Invalid credentials'));
    await expect(new ApiClient().get('/api/v1/auth/me')).rejects.toThrow();
  });

  it('lève une erreur sur une panne réseau', async () => {
    mockFetch.mockRejectedValue(new Error('Network failure'));
    // `retries: 0` : le client réessaie les erreurs réseau avec un backoff
    // exponentiel ; sans cela le test dépasse le délai de Jest.
    await expect(new ApiClient({ retries: 0 }).get('/api/v1/health')).rejects.toThrow();
  });
});
