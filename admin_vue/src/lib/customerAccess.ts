// Small pure helpers for the "Account access", tickets and messages panels of the customer page.
// No runtime imports so tests/customerAccess.test.mjs can transpile this file on its own.

export interface SessionLike { deviceName: string | null; expiresAt: string; revokedAt: string | null; userAgent: string | null }

/** Short device label from a user agent: "iPhone", "Android", "Chrome on Mac", "Hoppa app 1.6.0". */
export function describeUserAgent(ua: string | null | undefined): string {
  const text = ua ?? '';
  if (!text.trim()) return 'Unknown device';
  const app = text.match(/^([A-Za-z]+)App\/(\d+(?:\.\d+)*)/);
  if (app) return `${app[1]} app ${app[2]}`;
  if (/iPhone/i.test(text)) return 'iPhone';
  if (/iPad/i.test(text)) return 'iPad';
  if (/Android/i.test(text)) return 'Android';
  const os = /Macintosh|Mac OS X/i.test(text) ? 'Mac' : /Windows/i.test(text) ? 'Windows' : /Linux/i.test(text) ? 'Linux' : null;
  const browser = /Edg\//i.test(text) ? 'Edge' : /Firefox\//i.test(text) ? 'Firefox' : /Chrome\//i.test(text) ? 'Chrome' : /Safari\//i.test(text) ? 'Safari' : null;
  if (browser && os) return `${browser} on ${os}`;
  return browser ?? os ?? 'Browser';
}

export function sessionActive(session: Pick<SessionLike, 'expiresAt' | 'revokedAt'>, now = Date.now()): boolean {
  if (session.revokedAt) return false;
  const expires = Date.parse(session.expiresAt);
  return Number.isNaN(expires) || expires > now;
}

/** Distinct labels of the devices with a live session, e.g. ["iPhone 15", "Chrome on Mac"]. */
export function activeDeviceLabels(sessions: SessionLike[], now = Date.now()): string[] {
  return [...new Set(sessions.filter(s => sessionActive(s, now)).map(s => s.deviceName || describeUserAgent(s.userAgent)))];
}

/** Which currencies are hidden behind the two shown in the "Available funds" tile. */
export function hiddenCurrencies(balances: { currency: string }[], shown = 2): string[] {
  return balances.slice(shown).map(b => b.currency.toUpperCase());
}

export function ticketStatusLabel(status: string): { label: string; tone: 'neutral' | 'success' | 'warning' } {
  if (status === 'awaiting_support') return { label: 'Awaiting support', tone: 'warning' };
  if (status === 'resolved') return { label: 'Resolved', tone: 'success' };
  return { label: 'Awaiting customer', tone: 'neutral' };
}

export function messageStatusLabel(status: string): { label: string; tone: 'danger' | 'neutral' | 'success' } {
  const s = status.toLowerCase();
  if (['sent', 'delivered', 'succeeded', 'success'].includes(s)) return { label: 'Delivered', tone: 'success' };
  if (['failed', 'error', 'bounced'].includes(s)) return { label: 'Failed', tone: 'danger' };
  return { label: 'Sending', tone: 'neutral' };
}

/** "iOS", "Android", "Web" for the app line; anything else humanised. */
export function platformLabel(platform: string): string {
  const p = platform.trim().toLowerCase();
  if (p === 'ios' || p === 'iphone' || p === 'ipad') return 'iOS';
  if (p === 'android') return 'Android';
  if (p === 'web' || p === 'browser') return 'Web';
  return platform ? platform.charAt(0).toUpperCase() + platform.slice(1) : 'Unknown';
}
