'use client';

import { useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import type { Membership } from '@/lib/auth/session';
import { setActiveOrganizationId, signOut } from '@/lib/auth/actions';
import { NotificationBell } from '@/components/notifications/NotificationBell';

// Ítems de navegación por rol — Phase 0 solo tiene el dashboard
// placeholder; cada fase futura agrega sus rutas aquí sin tocar el
// resto del shell.
const NAV_BY_ROLE: Record<string, { href: string; label: string }[]> = {
  kcc_admin: [
    { href: '/dashboard', label: 'Overview' },
    { href: '/kcc-assistance', label: 'Assistance' },
    { href: '/website-leads', label: 'Website Leads' },
    { href: '/companies', label: 'Companies' },
    { href: '/commercial-dashboard', label: 'Commercial Dashboard' },
    { href: '/subscription-plans', label: 'Subscription Plans' },
    { href: '/warranty', label: 'Warranty' },
    { href: '/customers', label: 'Customers' },
    { href: '/vessels', label: 'Vessels' },
    { href: '/work-orders', label: 'Work Orders' },
    { href: '/service-requests', label: 'Service Requests' },
  ],
  company_owner: [
    { href: '/company', label: 'Overview' },
    { href: '/service-requests', label: 'Service Requests' },
    { href: '/work-orders', label: 'Work Orders' },
    { href: '/schedule', label: 'Schedule' },
    { href: '/estimates', label: 'Estimates' },
    { href: '/invoices', label: 'Invoices' },
    { href: '/communications', label: 'Communications' },
    { href: '/team', label: 'Team' },
    { href: '/customers', label: 'Customers' },
    { href: '/vessels', label: 'Vessels' },
    { href: '/services', label: 'Services' },
    { href: '/billing', label: 'Billing' },
    { href: '/company-settings', label: 'Company Settings' },
  ],
  company_admin: [
    { href: '/company', label: 'Overview' },
    { href: '/service-requests', label: 'Service Requests' },
    { href: '/work-orders', label: 'Work Orders' },
    { href: '/warranty', label: 'Warranty' },
    { href: '/schedule', label: 'Schedule' },
    { href: '/estimates', label: 'Estimates' },
    { href: '/invoices', label: 'Invoices' },
    { href: '/communications', label: 'Communications' },
    { href: '/team', label: 'Team' },
    { href: '/customers', label: 'Customers' },
    { href: '/vessels', label: 'Vessels' },
    { href: '/services', label: 'Services' },
    { href: '/billing', label: 'Billing' },
    { href: '/company-settings', label: 'Company Settings' },
  ],
  manager: [
    { href: '/company', label: 'Overview' },
    { href: '/service-requests', label: 'Service Requests' },
    { href: '/work-orders', label: 'Work Orders' },
    { href: '/warranty', label: 'Warranty' },
    { href: '/schedule', label: 'Schedule' },
    { href: '/estimates', label: 'Estimates' },
    { href: '/invoices', label: 'Invoices' },
    { href: '/communications', label: 'Communications' },
    { href: '/team', label: 'Team' },
    { href: '/customers', label: 'Customers' },
    { href: '/vessels', label: 'Vessels' },
    { href: '/services', label: 'Services' },
    { href: '/company-settings', label: 'Company Settings' },
  ],
  technician: [
    { href: '/today', label: 'Today' },
    { href: '/kcc-assistance', label: 'Assistance' },
  ],
  customer: [
    { href: '/customer', label: 'Home' },
    { href: '/vessels', label: 'My Vessels' },
    { href: '/work-orders', label: 'My Service' },
    { href: '/estimates', label: 'Estimates' },
    { href: '/invoices', label: 'Invoices' },
    { href: '/messages', label: 'Messages' },
    { href: '/request-service', label: 'Request Service' },
  ],
};

export function AppNav({
  fullName,
  memberships,
  activeOrgId,
  isKccAdmin,
  userId,
  initialUnreadCount,
}: {
  fullName: string | null;
  memberships: Membership[];
  activeOrgId: string | null;
  isKccAdmin: boolean;
  userId: string;
  initialUnreadCount: number;
}) {
  const router = useRouter();
  const [switching, setSwitching] = useState(false);

  const activeMembership = memberships.find((m) => m.organization_id === activeOrgId);
  const navItems = activeMembership ? NAV_BY_ROLE[activeMembership.role] ?? [] : [];

  async function handleSwitch(orgId: string) {
    setSwitching(true);
    await setActiveOrganizationId(orgId);
    router.refresh();
    setSwitching(false);
  }

  return (
    <header className="border-b border-white/10 bg-panel">
      <div className="flex items-center justify-between h-14 px-5">
        <div className="flex items-center gap-6">
          <span className="font-display font-bold text-sm bg-gradient-to-r from-gold to-silver bg-clip-text text-transparent">
            KCC
          </span>

          {/* Ajuste de claridad (verificación previa a Phase 1, punto 5):
              kcc_admin nunca muestra el nombre de la organización interna
              como si fuera "su" compañía — su privilegio es de red, no de
              tenant. Ver docs/kcc-admin-tenant-model.md. */}
          {isKccAdmin ? (
            <span className="font-mono text-[9px] uppercase tracking-[0.08em] text-gold border border-gold-dim px-2 py-0.5 rounded-sm">
              KCC Admin — Network Access
            </span>
          ) : (
            <>
              {memberships.length > 1 && (
                <select
                  value={activeOrgId ?? ''}
                  onChange={(e) => handleSwitch(e.target.value)}
                  disabled={switching}
                  className="bg-white/[0.04] border border-white/10 text-xs px-2.5 py-1.5 rounded-sm"
                >
                  {memberships.map((m) => (
                    <option key={m.organization_id} value={m.organization_id} className="bg-navy">
                      {m.organization.name} ({m.role})
                    </option>
                  ))}
                </select>
              )}

              {memberships.length === 1 && (
                <span className="text-xs text-cool-gray">
                  {memberships[0].organization.name} <span className="text-gold">· {memberships[0].role}</span>
                </span>
              )}
            </>
          )}
        </div>

        <div className="flex items-center gap-4">
          <NotificationBell userId={userId} initialUnreadCount={initialUnreadCount} />
          <span className="text-xs text-cool-gray hidden sm:block">{fullName}</span>
          <form action={signOut}>
            <button type="submit" className="text-[11px] uppercase tracking-[0.08em] text-cool-gray hover:text-gold">
              Sign Out
            </button>
          </form>
        </div>
      </div>

      <nav className="flex gap-1 px-5 h-10 items-center border-t border-white/5">
        {navItems.map((item) => (
          <Link
            key={item.href}
            href={item.href}
            className="text-[11px] uppercase tracking-[0.06em] text-cool-gray hover:text-gold px-3 py-1.5"
          >
            {item.label}
          </Link>
        ))}
      </nav>
    </header>
  );
}
