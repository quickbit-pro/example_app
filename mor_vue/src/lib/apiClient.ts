import axios from 'axios';

// Only the sample backend is a data API. The staging Hoppa key stays server-side.
const backendBaseUrl = import.meta.env.VITE_BACKEND_API_BASE_URL || 'http://localhost:5188';
const backendOrigin = new URL(backendBaseUrl).origin;
const allowed = ['/api/v1/mor/', '/api/v1/auth/'];
export const apiClient = axios.create({ baseURL: backendBaseUrl, withCredentials: true,
  headers: { Accept: 'application/json', 'Content-Type': 'application/json' } });
apiClient.interceptors.request.use(config => {
  const target = new URL(config.url || '', backendBaseUrl);
  if (target.origin !== backendOrigin || !allowed.some(prefix => target.pathname.startsWith(prefix)))
    throw new Error('The MOR portal can only call its backend APIs.');
  return config;
});
