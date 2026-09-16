import { describe, expect, it } from 'vitest';
import { roleHome } from '@/lib/auth/role-home';
import { safeInternalPath } from '@/lib/auth/site-url';

describe('Marine Cloud auth routing', () => {
  it('routes every operational role to its correct workspace', () => {
    expect(roleHome('company_owner')).toBe('/company');
    expect(roleHome('company_admin')).toBe('/company');
    expect(roleHome('manager')).toBe('/company');
    expect(roleHome('technician')).toBe('/today');
    expect(roleHome('customer')).toBe('/customer');
    expect(roleHome('kcc_admin')).toBe('/dashboard');
  });

  it('keeps auth continuation paths internal', () => {
    expect(safeInternalPath('/accept-invite?token=abc', '/')).toBe('/accept-invite?token=abc');
    expect(safeInternalPath('https://evil.example', '/')).toBe('/');
    expect(safeInternalPath('//evil.example', '/')).toBe('/');
  });
});
