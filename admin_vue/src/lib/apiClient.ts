import axios from 'axios';

const backendBaseUrl =
  import.meta.env.VITE_BACKEND_API_BASE_URL ?? 'https://demo-api.roks.dev';

const allowedApiPrefixes = ['/api/v1/admin', '/api/v1/auth', '/api/v1/branding'];

export const apiClient = axios.create({
  baseURL: backendBaseUrl,
  headers: {
    Accept: 'application/json',
    'Content-Type': 'application/json',
  },
  withCredentials: true,
});

apiClient.interceptors.request.use((config) => {
  const requestPath = config.url ?? '';
  const backendOrigin = new URL(backendBaseUrl).origin;
  const normalizedPath = requestPath.startsWith('http')
    ? new URL(requestPath).pathname
    : requestPath;

  if (requestPath.startsWith('http') && new URL(requestPath).origin !== backendOrigin) {
    throw new Error(`Admin UI may not call external APIs directly: ${requestPath}`);
  }

  if (normalizedPath.startsWith('/api/') &&
    !allowedApiPrefixes.some((prefix) => normalizedPath.startsWith(prefix))
  ) {
    throw new Error(
      `Admin UI may only call backend-owned admin/auth APIs: ${normalizedPath}`,
    );
  }

  return config;
});

export function backendUrl(path: string): string {
  return new URL(path, backendBaseUrl).toString();
}
