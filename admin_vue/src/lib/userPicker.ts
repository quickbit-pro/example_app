import type { UserOption } from '@/lib/referrals';

/** "Name · email" as the pickers have always shown it; falls back to whichever part exists. */
export function userLabel(user: Pick<UserOption, 'Name' | 'Email'> | null | undefined): string {
  if (!user) return '';
  const name = (user.Name ?? '').trim();
  const email = (user.Email ?? '').trim();
  return name && email ? `${name} · ${email}` : name || email;
}

/** Case-insensitive match on name, email or "#id"; an empty query keeps every user. */
export function filterUsers<T extends UserOption>(users: T[], query: string): T[] {
  const q = query.trim().toLowerCase();
  if (!q) return users;
  const id = q.startsWith('#') ? q.slice(1) : q;
  return users.filter(u => `${u.Name} ${u.Email}`.toLowerCase().includes(q) || String(u.Id) === id);
}

/** Debounce helper for the server search; returns a cancel function. */
export function debounce<A extends unknown[]>(fn: (...args: A) => void, ms: number): { call: (...args: A) => void; cancel: () => void } {
  let timer: ReturnType<typeof setTimeout> | undefined;
  return {
    call: (...args: A) => { clearTimeout(timer); timer = setTimeout(() => fn(...args), ms); },
    cancel: () => clearTimeout(timer),
  };
}
