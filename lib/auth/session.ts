import "server-only";
import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";

export interface Membership {
  organization_id: string;
  role:
    | "kcc_admin"
    | "company_owner"
    | "company_admin"
    | "manager"
    | "technician"
    | "customer";
  status: string;
  organization: {
    id: string;
    name: string;
    slug: string;
    branding_json: Record<string, unknown>;
  };
}

export interface SessionContext {
  userId: string;
  email: string | null;
  fullName: string | null;
  memberships: Membership[];
  isKccAdmin: boolean;
  profileSetupComplete: boolean;
  avatarUrl: string | null;
  passwordSetupComplete: boolean;
  passwordSetupRequired: boolean;
}

// Server-only. Llamado desde el layout de (app) — obtiene la sesión
// real (vía cookie, RLS aplica normalmente) y arma el contexto que
// alimenta el nav shell (qué organizaciones ve, qué rol tiene en cada
// una). Si no hay sesión, redirige a /login (defensa en profundidad —
// el middleware ya debería haberlo hecho).
export async function getSessionContext(): Promise<SessionContext> {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("full_name, email, avatar_url, password_set_at")
    .eq("id", user.id)
    .single();

  const { data: memberships } = await supabase
    .from("organization_memberships")
    .select(
      "organization_id, role, status, organization:organizations(id, name, slug, branding_json)",
    )
    .eq("profile_id", user.id)
    .eq("status", "active");

  const typedMemberships = (memberships ?? []) as unknown as Membership[];

  return {
    userId: user.id,
    email: profile?.email ?? user.email ?? null,
    fullName: profile?.full_name ?? null,
    memberships: typedMemberships,
    profileSetupComplete: user.user_metadata?.profile_setup_complete === true,
    avatarUrl: profile?.avatar_url ?? null,
    // First-time password setup is an explicit account state. A null
    // password_set_at on a legacy account is NOT enough to classify that
    // person as newly invited. This prevents existing admins/users from being
    // hijacked into onboarding after a deployment.
    passwordSetupRequired: user.user_metadata?.password_setup_required === true,
    passwordSetupComplete:
      user.user_metadata?.password_setup_complete === true ||
      Boolean(profile?.password_set_at) ||
      user.user_metadata?.password_setup_required !== true,
    isKccAdmin: typedMemberships.some((m) => m.role === "kcc_admin"),
  };
}
