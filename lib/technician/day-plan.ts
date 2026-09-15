export function dayKey(value: string | Date, timeZone: string) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(value));
}
export function isToday(
  value: string | null,
  timeZone: string,
  now = new Date(),
) {
  return !!value && dayKey(value, timeZone) === dayKey(now, timeZone);
}
