import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
const MODULES = [
  "work_orders",
  "service_requests",
  "estimates",
  "tracking",
  "warranty",
  "communications",
];
export async function getLaunchPlan(db: SupabaseClient) {
  let plan = await db
    .from("subscription_plans")
    .select("id")
    .eq("code", "kcc-operational-launch")
    .maybeSingle();
  if (plan.error) return { error: plan.error.message };
  if (!plan.data) {
    const created = await db.rpc("create_subscription_plan_with_entitlements", {
      p_code: "kcc-operational-launch",
      p_name: "KCC Operational Access",
      p_description: "Initial operation without platform subscription charges.",
      p_currency: "USD",
      p_weekly_price: null,
      p_monthly_price: null,
      p_annual_price: null,
      p_trial_default_days: null,
      p_is_public: false,
      p_is_custom: true,
      p_module_keys: MODULES,
    });
    if (created.error && created.error.code !== "23505")
      return { error: created.error.message };
    plan = await db
      .from("subscription_plans")
      .select("id")
      .eq("code", "kcc-operational-launch")
      .single();
  }
  if (!plan.data)
    return { error: "Operational access configuration unavailable." };
  return { id: plan.data.id };
}
