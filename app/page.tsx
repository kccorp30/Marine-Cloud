import { redirect } from 'next/navigation';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { roleHome } from '@/lib/auth/role-home';

// Antes mandaba a TODO rol a /dashboard — un placeholder de debug de
// Phase 0 que ni siquiera aparece en el nav de technician o customer.
// Un customer terminaba en una pantalla de "RLS Verification" interna
// en vez de algo suyo. Cada rol ahora aterriza en su home real.
export default async function RootPage() {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const activeMembership = session.memberships.find((m) => m.organization_id === activeOrgId);

  redirect(roleHome(activeMembership?.role, session.isKccAdmin));
}
