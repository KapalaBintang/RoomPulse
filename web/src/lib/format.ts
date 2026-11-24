/**
 * Timezone helpers for Asia/Jakarta (WIB: UTC+7)
 */

export const TIMEZONE = 'Asia/Jakarta';

export function formatJakartaTime(dateStr: string | null | undefined): string {
  if (!dateStr) return '-';
  const d = new Date(dateStr);
  return new Intl.DateTimeFormat('en-ID', {
    timeZone: TIMEZONE,
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(d) + ' WIB';
}

export function formatJakartaDate(dateStr: string | null | undefined): string {
  if (!dateStr) return '-';
  const d = new Date(dateStr);
  return new Intl.DateTimeFormat('en-ID', {
    timeZone: TIMEZONE,
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  }).format(d);
}

export function formatJakartaDateTime(dateStr: string | null | undefined): string {
  if (!dateStr) return '-';
  return `${formatJakartaDate(dateStr)} ${formatJakartaTime(dateStr)}`;
}

export function getSecondsRemaining(deadlineIso: string | null | undefined): number {
  if (!deadlineIso) return 0;
  const diff = Math.floor((new Date(deadlineIso).getTime() - Date.now()) / 1000);
  return Math.max(0, diff);
}
