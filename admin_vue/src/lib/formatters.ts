export function humanize(value: string | null | undefined) {
  if (!value) return 'Not available';
  const text = value.replace(/[_-]+/g, ' ').trim();
  return text ? `${text.charAt(0).toUpperCase()}${text.slice(1)}` : 'Not available';
}

export function formatCurrency(amount: number, currency: string) {
  try {
    return new Intl.NumberFormat(undefined, {
      currency,
      currencyDisplay: 'symbol',
      maximumFractionDigits: 2,
      minimumFractionDigits: 2,
      style: 'currency',
    }).format(amount);
  } catch {
    return `${currency} ${amount.toLocaleString(undefined, { maximumFractionDigits: 2 })}`;
  }
}

export function formatDate(value: string | null | undefined) {
  if (!value) return 'Not available';
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value));
}

export function formatDateTime(value: string | null | undefined) {
  if (!value) return 'Not available';
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
}

export function relativeTime(value: string | null | undefined) {
  if (!value) return 'No recent activity';
  const delta = Date.now() - new Date(value).getTime();
  const minutes = Math.max(0, Math.floor(delta / 60_000));
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

export function toneForStatus(status: string | null | undefined) {
  const normalized = status?.toLowerCase() ?? '';
  if (['active', 'approved', 'completed', 'passed', 'posted', 'settled', 'succeeded', 'verified'].includes(normalized)) return 'success';
  if (['failed', 'rejected', 'blocked', 'cancelled', 'canceled'].includes(normalized)) return 'danger';
  if (['pending', 'submitted', 'reviewing', 'manual_review', 'in_progress'].includes(normalized)) return 'warning';
  return 'neutral';
}
