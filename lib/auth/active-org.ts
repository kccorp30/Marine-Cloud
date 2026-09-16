import 'server-only';
import { cookies } from 'next/headers';
import type { Membership } from './session';

const COOKIE_NAME = 'kcc_active_org';

// La "organización activa" es puramente un filtro de UI — decide QUÉ
// mostrás, no protege nada (RLS ya garantiza que solo veas datos de
// organizaciones a las que realmente pertenecés, sin importar cuál
// esté "activa"). Por eso es seguro que viva en una cookie simple.
export async function getActiveOrganizationId(memberships: Membership[]): Promise<string | null> {
  if (memberships.length === 0) return null;

  const cookieStore = await cookies();
  const stored = cookieStore.get(COOKIE_NAME)?.value;

  // Si la cookie apunta a una organización a la que ya no pertenece
  // (o nunca apuntó a ninguna), cae a la primera membership disponible.
  if (stored && memberships.some((m) => m.organization_id === stored)) {
    return stored;
  }

  return memberships[0].organization_id;
}

export const ACTIVE_ORG_COOKIE_NAME = COOKIE_NAME;
