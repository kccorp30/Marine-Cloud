import "server-only";
import { createClient } from "@/lib/supabase/server";

export interface KccDashboardData {
  totalOrganizations: number;
  activeOrganizations: number;
  inactiveOrganizations: number;
  suspendedOrganizations: number;
  activeWorkOrders: number;
  workOrdersNeedingAttention: number;
  openAssistanceRequests: number;
  estimatesAwaitingApproval: number;
  openInvoicesCount: number;
  openInvoicesTotal: number;
  paidAmountLast30Days: number;
  kccGeneratedWorkOrders: number;
  recentOrganizations: { id: string; name: string; createdAt: string }[];
  recentActivity: {
    id: string;
    eventType: string;
    occurredAt: string;
    organizationName: string | null;
  }[];
}

// "Requiring attention" — definición explícita y conservadora: work
// orders activos (no completados/cancelados) atascados en
// waiting_parts, o con una solicitud de KCC Assistance todavía
// abierta. Documentado acá porque no hay un único campo que ya
// signifique esto.
const ATTENTION_STATUSES = ["waiting_parts"];

export async function getKccDashboardData(): Promise<KccDashboardData> {
  const supabase = await createClient();

  const [
    { count: totalOrganizations },
    { count: activeOrganizations },
    { count: inactiveOrganizations },
    { count: suspendedOrganizations },
    { count: activeWorkOrders },
    { count: workOrdersNeedingAttention },
    { count: openAssistanceRequests },
    { count: estimatesAwaitingApproval },
    { data: openInvoices },
    { data: recentPayments },
    { count: kccGeneratedWorkOrders },
    { data: recentOrgs },
    { data: recentEvents },
  ] = await Promise.all([
    supabase
      .from("organizations")
      .select("id", { count: "exact", head: true })
      .throwOnError(),
    supabase
      .from("organizations")
      .select("id", { count: "exact", head: true })
      .eq("status", "active")
      .throwOnError(),
    supabase
      .from("organizations")
      .select("id", { count: "exact", head: true })
      .eq("status", "inactive")
      .throwOnError(),
    supabase
      .from("organizations")
      .select("id", { count: "exact", head: true })
      .eq("status", "suspended")
      .throwOnError(),
    supabase
      .from("work_orders")
      .select("id", { count: "exact", head: true })
      .not("current_status", "in", "(completed,cancelled)")
      .throwOnError(),
    supabase
      .from("work_orders")
      .select("id", { count: "exact", head: true })
      .in("current_status", ATTENTION_STATUSES)
      .throwOnError(),
    supabase
      .from("kcc_assistance_requests")
      .select("id", { count: "exact", head: true })
      .in("status", ["open", "accepted", "started"])
      .throwOnError(),
    supabase
      .from("estimates")
      .select("id", { count: "exact", head: true })
      .in("status", ["sent"])
      .throwOnError(),
    supabase
      .from("invoices")
      .select("balance_due")
      .in("status", ["sent", "partially_paid", "overdue"])
      .throwOnError(),
    supabase
      .from("payments")
      .select("amount")
      .eq("status", "settled")
      .gte(
        "received_at",
        new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(),
      )
      .throwOnError(),
    supabase
      .from("work_orders")
      .select("id", { count: "exact", head: true })
      .eq("kcc_generated", true)
      .throwOnError(),
    supabase
      .from("organizations")
      .select("id, name, created_at")
      .order("created_at", { ascending: false })
      .limit(5)
      .throwOnError(),
    supabase
      .from("domain_events")
      .select("id, event_type, occurred_at, organization:organizations(name)")
      .order("occurred_at", { ascending: false })
      .limit(15)
      .throwOnError(),
  ]);

  const openInvoicesTotal = (openInvoices ?? []).reduce(
    (sum, inv) => sum + Number(inv.balance_due ?? 0),
    0,
  );
  const paidAmountLast30Days = (recentPayments ?? []).reduce(
    (sum, p) => sum + Number(p.amount ?? 0),
    0,
  );

  return {
    totalOrganizations: totalOrganizations ?? 0,
    activeOrganizations: activeOrganizations ?? 0,
    inactiveOrganizations: inactiveOrganizations ?? 0,
    suspendedOrganizations: suspendedOrganizations ?? 0,
    activeWorkOrders: activeWorkOrders ?? 0,
    workOrdersNeedingAttention: workOrdersNeedingAttention ?? 0,
    openAssistanceRequests: openAssistanceRequests ?? 0,
    estimatesAwaitingApproval: estimatesAwaitingApproval ?? 0,
    openInvoicesCount: (openInvoices ?? []).length,
    openInvoicesTotal,
    paidAmountLast30Days,
    kccGeneratedWorkOrders: kccGeneratedWorkOrders ?? 0,
    recentOrganizations: (recentOrgs ?? []).map((o) => ({
      id: o.id,
      name: o.name,
      createdAt: o.created_at,
    })),
    recentActivity: (recentEvents ?? []).map((e: any) => ({
      id: e.id,
      eventType: e.event_type,
      occurredAt: e.occurred_at,
      organizationName:
        (Array.isArray(e.organization) ? e.organization[0] : e.organization)
          ?.name ?? null,
    })),
  };
}
