"use server";
import { getSessionContext } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { getLaunchPlan } from "./plan";

/** Explicit admin action. No global RLS bypass and no change to organization status. */
export async function enableLaunchAccess(organizationId: string) {
  const session = await getSessionContext();
  if (!session.isKccAdmin)
    return { error: "Only KCC administration can activate a company." };
  const db = await createClient();
  const org = await db
    .from("organizations")
    .select("id,status")
    .eq("id", organizationId)
    .single();
  if (org.error || org.data?.status !== "active")
    return {
      error: "The company must be active before enabling operational access.",
    };
  const plan = await getLaunchPlan(db);
  if ("error" in plan) return { error: plan.error };
  const current = await db
    .from("organization_subscriptions")
    .select("plan_id,status,complimentary")
    .eq("organization_id", organizationId)
    .is("superseded_at", null)
    .maybeSingle();
  if (current.error) return { error: current.error.message };
  if (
    current.data &&
    current.data.plan_id === plan.id &&
    current.data.complimentary &&
    current.data.status === "complimentary"
  )
    return { success: true };
  const result = await db.rpc("assign_organization_subscription", {
    p_organization_id: organizationId,
    p_plan_id: plan.id,
    p_billing_cycle: "custom",
    p_trial_days: null,
    p_price_override: null,
    p_complimentary: true,
    p_complimentary_reason:
      "Initial operational launch. Platform billing paused by KCC.",
    p_custom_terms: null,
  });
  if (result.error) return { error: result.error.message };
  revalidatePath("/companies");
  revalidatePath("/company");
  return { success: true };
}
