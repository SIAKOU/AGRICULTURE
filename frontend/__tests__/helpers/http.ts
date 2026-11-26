/**
 * Fabrique de réponses HTTP pour les tests.
 *
 * `jest-environment-jsdom` n'expose pas `Response` (ni `fetch`), alors que
 * l'environnement Node le fait. Plutôt que d'ajouter une dépendance de
 * polyfill, on construit un objet minimal qui reproduit exactement la surface
 * utilisée par `lib/api-client.ts` : `ok`, `status`, `headers.get`,
 * `json()`, `text()`.
 */

export interface MockResponseInit {
  status?: number;
  statusText?: string;
  contentType?: string;
  /** Simule une réponse sans corps (204 / content-length: 0). */
  empty?: boolean;
}

export function mockResponse(body: unknown, init: MockResponseInit = {}): Response {
  const status = init.status ?? 200;
  const headers: Record<string, string> = {
    'content-type': init.contentType ?? 'application/json',
    'content-length': init.empty ? '0' : String(JSON.stringify(body ?? null).length),
  };

  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: init.statusText ?? '',
    headers: {
      get: (name: string) => headers[name.toLowerCase()] ?? null,
    },
    json: async () => {
      if (init.empty) throw new SyntaxError('Unexpected end of JSON input');
      return body;
    },
    text: async () => (init.empty ? '' : JSON.stringify(body)),
  } as unknown as Response;
}

/** Réponse JSON d'erreur, pour tester les chemins d'échec. */
export function mockErrorResponse(status: number, detail: string): Response {
  return mockResponse({ detail }, { status });
}
