"use server";

import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { ACTIVE_ORG_COOKIE_NAME } from "./active-org";

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}

export async function setActiveOrganizationId(organizationId: string) {
  const db = await createClient();
  const {
    data: { user },
  } = await db.auth.getUser();
  if (!user) redirect("/login");
  const { data } = await db
    .from("organization_memberships")
    .select("organization_id")
    .eq("profile_id", user.id)
    .eq("organization_id", organizationId)
    .eq("status", "active")
    .limit(1);
  if (!data?.length) throw new Error("Workspace unavailable");
  const cookieStore = await cookies();
  cookieStore.set(ACTIVE_ORG_COOKIE_NAME, organizationId, {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
  });
}
