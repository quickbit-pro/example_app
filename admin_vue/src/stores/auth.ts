import { defineStore } from 'pinia';

import { apiClient } from '@/lib/apiClient';

type Role = 'admin' | 'support' | 'user';

interface AuthState {
  expiresAt: number | null;
  refreshToken: string | null;
  rememberSession: boolean;
  roles: Role[];
  token: string | null;
  pendingChallenge?: string | null;
  pendingRememberSession?: boolean;
}

interface AuthTokenResponse {
  accessToken?: string | null;
  expiresInSeconds?: number | null;
  refreshToken?: string | null;
  roles?: string[] | null;
  requiresTwoFactor?: boolean | null;
  challengeToken?: string | null;
}

const sessionStorageKey = 'admin_vue.auth';

function isRole(value: string): value is Role {
  return value === 'admin' || value === 'support' || value === 'user';
}

function normalizeRole(value: unknown): Role | null {
  if (typeof value !== 'string') {
    return null;
  }

  const normalized = value.trim().toLowerCase();

  return isRole(normalized) ? normalized : null;
}

function normalizeRoles(values: unknown[] | null | undefined): Role[] {
  return [
    ...new Set(
      (values ?? []).map(normalizeRole).filter((role): role is Role => role !== null),
    ),
  ];
}

function decodeJwtRoles(token: string): Role[] {
  const [, payload] = token.split('.');

  if (!payload) {
    return [];
  }

  try {
    const decodedPayload = JSON.parse(
      window.atob(payload.replace(/-/g, '+').replace(/_/g, '/')),
    ) as Record<string, unknown>;
    const rawRoles =
      decodedPayload.role ??
      decodedPayload.roles ??
      decodedPayload[
        'http://schemas.microsoft.com/ws/2008/06/identity/claims/role'
      ];
    const roles = Array.isArray(rawRoles) ? rawRoles : [rawRoles];

    return normalizeRoles(roles);
  } catch {
    return [];
  }
}

function persistSession(state: AuthState) {
  const storage = state.rememberSession ? window.localStorage : window.sessionStorage;
  const alternateStorage = state.rememberSession ? window.sessionStorage : window.localStorage;

  alternateStorage.removeItem(sessionStorageKey);
  storage.setItem(
    sessionStorageKey,
    JSON.stringify({
      expiresAt: state.expiresAt,
      refreshToken: state.refreshToken,
      rememberSession: state.rememberSession,
      roles: state.roles,
      token: state.token,
    }),
  );
}

function applyAuthorizationHeader(token: string | null) {
  if (token) {
    apiClient.defaults.headers.common.Authorization = `Bearer ${token}`;
    return;
  }

  delete apiClient.defaults.headers.common.Authorization;
}

export const useAuthStore = defineStore('auth', {
  state: (): AuthState => ({
    expiresAt: null,
    refreshToken: null,
    rememberSession: true,
    roles: [],
    token: null,
    pendingChallenge: null,
    pendingRememberSession: false,
  }),
  getters: {
    isAuthenticated: (state) =>
      Boolean(state.token) &&
      (!state.expiresAt || state.expiresAt > Date.now()),
    isAdmin: (state) => state.roles.includes('admin'),
  },
  actions: {
    restoreSession() {
      const savedSession =
        window.localStorage.getItem(sessionStorageKey) ??
        window.sessionStorage.getItem(sessionStorageKey);

      if (!savedSession) {
        return;
      }

      try {
        const parsed = JSON.parse(savedSession) as AuthState;
        this.token = parsed.token;
        this.refreshToken = parsed.refreshToken;
        this.expiresAt = parsed.expiresAt;
        this.rememberSession = parsed.rememberSession ?? false;
        this.roles = normalizeRoles(parsed.roles);
        applyAuthorizationHeader(this.token);

        if (!this.isAuthenticated) {
          this.clearSession();
        }
      } catch {
        this.clearSession();
      }
    },
    /**
     * Password step. Resolves to true when the account still needs a second
     * factor; the caller then collects a code for completeTwoFactor.
     */
    async login(email: string, password: string, rememberSession = false): Promise<boolean> {
      const { data } = await apiClient.post<AuthTokenResponse>(
        '/api/v1/auth/login',
        {
          email,
          password,
          deviceName: 'Admin panel',
        },
      );
      if (data.requiresTwoFactor && data.challengeToken) {
        this.pendingChallenge = data.challengeToken;
        this.pendingRememberSession = rememberSession;
        return true;
      }
      this.applyTokenResponse(data, rememberSession);
      return false;
    },
    async completeTwoFactor(code: string) {
      const challengeToken = this.pendingChallenge;
      if (!challengeToken) {
        throw new Error('No sign-in challenge is pending.');
      }
      const { data } = await apiClient.post<AuthTokenResponse>('/api/v1/auth/login/2fa', {
        challengeToken,
        code,
      });
      this.applyTokenResponse(data, this.pendingRememberSession ?? false);
      this.pendingChallenge = null;
    },
    cancelTwoFactor() {
      this.pendingChallenge = null;
    },
    applyTokenResponse(data: AuthTokenResponse, rememberSession: boolean) {
      const token = data.accessToken;

      if (!token) {
        throw new Error('Authentication response did not include an access token.');
      }

      const expiresInSeconds = data.expiresInSeconds ?? null;
      const responseRoles = normalizeRoles(data.roles);
      this.setSession(
        token,
        responseRoles.length > 0 ? responseRoles : decodeJwtRoles(token),
        data.refreshToken ?? null,
        expiresInSeconds ? Date.now() + expiresInSeconds * 1000 : null,
        rememberSession,
      );
    },
    setSession(
      token: string,
      roles: Role[],
      refreshToken: string | null = null,
      expiresAt: number | null = null,
      rememberSession = false,
    ) {
      this.token = token;
      this.roles = roles;
      this.refreshToken = refreshToken;
      this.expiresAt = expiresAt;
      this.rememberSession = rememberSession;
      applyAuthorizationHeader(token);
      persistSession(this.$state);
    },
    async logout() {
      try {
        await apiClient.post('/api/v1/auth/logout', { refreshToken: this.refreshToken });
      } finally {
        this.clearSession();
      }
    },
    clearSession() {
      this.token = null;
      this.roles = [];
      this.refreshToken = null;
      this.expiresAt = null;
      this.rememberSession = false;
      applyAuthorizationHeader(null);
      window.localStorage.removeItem(sessionStorageKey);
      window.sessionStorage.removeItem(sessionStorageKey);
    },
  },
});
