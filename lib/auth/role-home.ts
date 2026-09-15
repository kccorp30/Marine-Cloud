export type MarineCloudRole =
  | 'kcc_admin'
  | 'company_owner'
  | 'company_admin'
  | 'manager'
  | 'technician'
  | 'customer';

export function roleHome(role: string | null | undefined, isKccAdmin = false): string {
  if (isKccAdmin || role === 'kcc_admin') return '/dashboard';
  if (role === 'technician') return '/today';
  if (role === 'customer') return '/customer';
  if (role === 'company_owner' || role === 'company_admin' || role === 'manager') return '/company';
  return '/';
}
