import "server-only";
import { createClient } from "@/lib/supabase/server";
import {
  mapWorkOrderStatusToCustomerStage,
  CUSTOMER_STAGES,
} from "@/lib/work-orders/customer-stages";

export interface CustomerVesselCard {
  id: string;
  name: string;
  make: string | null;
  model: string | null;
  year: number | null;
  status: string;
}

export interface CustomerActiveWorkOrder {
  id: string;
  title: string;
  vesselName: string | null;
  stageLabel: string;
  currentStatus: string;
  subStatus: string;
  lastActivityAt: string | null;
}

export interface CustomerRecentWorkOrder {
  id: string;
  title: string;
  vesselName: string | null;
  completedAt: string | null;
}

export interface CustomerActionableEstimate {
  id: string;
  estimateNumber: string;
  vesselName: string | null;
  total: number;
}

export interface CustomerPaymentDue {
  id: string;
  invoiceNumber: string;
  invoiceType: string;
  vesselName: string | null;
  balanceDue: number;
}

export interface CustomerHomeData {
  firstName: string | null;
  vessels: CustomerVesselCard[];
  activeWorkOrders: CustomerActiveWorkOrder[];
  recentWorkOrders: CustomerRecentWorkOrder[];
  actionableEstimates: CustomerActionableEstimate[];
  paymentsDue: CustomerPaymentDue[];
}

const ACTIVE_STATUSES = [
  "request_received",
  "invoice",
  "payment",
  "triage",
  "estimate",
  "awaiting_approval",
  "scheduled",
  "technician_assigned",
  "en_route",
  "checked_in",
  "diagnosis",
  "work_in_progress",
  "waiting_parts",
  "waiting_customer_approval",
  "quality_control",
];

// Server-only — nunca se importa desde un client component. RLS ya
// garantiza que cada query acá abajo solo devuelve lo del customer
// autenticado (is_own_customer_record) — esta función no agrega
// ninguna restricción propia, solo arma el DTO tipado que consume
// el home.
export async function getCustomerHomeData(
  userId: string,
  organizationId: string,
): Promise<CustomerHomeData | null> {
  const supabase = await createClient();

  const { data: customer } = await supabase
    .from("customers")
    .select("id, first_name")
    .eq("profile_id", userId)
    .eq("organization_id", organizationId)
    .maybeSingle();
  if (!customer) return null;

  const { data: vessels } = await supabase
    .from("vessels")
    .select("id, name, make, model, year, status")
    .eq("current_customer_id", customer.id)
    .order("created_at", { ascending: false });

  const { data: activeRaw } = await supabase
    .from("work_orders")
    .select("id, title, current_status, last_activity_at, vessel:vessels(name)")
    .eq("customer_id", customer.id)
    .in("current_status", ACTIVE_STATUSES)
    .order("last_activity_at", { ascending: false, nullsFirst: false });

  const { data: recentRaw } = await supabase
    .from("work_orders")
    .select("id, title, updated_at, vessel:vessels(name)")
    .eq("customer_id", customer.id)
    .eq("current_status", "completed")
    .order("updated_at", { ascending: false })
    .limit(5);

  const activeWorkOrders: CustomerActiveWorkOrder[] = (activeRaw ?? []).map(
    (wo: any) => {
      const mapping = mapWorkOrderStatusToCustomerStage(wo.current_status);
      const stage = CUSTOMER_STAGES.find((s) => s.index === mapping.stageIndex);
      return {
        id: wo.id,
        title: wo.title,
        vesselName: wo.vessel?.name ?? null,
        currentStatus: wo.current_status,
        stageLabel: stage?.label ?? "In Progress",
        subStatus: mapping.subStatus,
        lastActivityAt: wo.last_activity_at,
      };
    },
  );

  const recentWorkOrders: CustomerRecentWorkOrder[] = (recentRaw ?? []).map(
    (wo: any) => ({
      id: wo.id,
      title: wo.title,
      vesselName: wo.vessel?.name ?? null,
      completedAt: wo.updated_at,
    }),
  );

  // Estimates accionables — RLS ya filtra a las del propio customer;
  // acá filtramos explícito por estado accionable (sent/viewed) para
  // que el DTO nunca dependa solo de la policy para el significado.
  const { data: actionableRaw } = await supabase
    .from("estimates")
    .select(
      "id, estimate_number, vessel:vessels(name), current_version:estimate_versions!fk_estimates_current_version(status, total)",
    )
    .eq("customer_id", customer.id)
    .in("status", ["sent", "viewed"])
    .order("created_at", { ascending: false });

  const actionableEstimates: CustomerActionableEstimate[] = (
    actionableRaw ?? []
  )
    .map((e: any) => {
      const version = Array.isArray(e.current_version)
        ? e.current_version[0]
        : e.current_version;
      return {
        id: e.id,
        estimateNumber: e.estimate_number,
        vesselName: e.vessel?.name ?? null,
        total: Number(version?.total ?? 0),
      };
    })
    .filter((e) => e.total > 0);

  // Invoices con balance pendiente — RLS ya filtra a lo propio.
  const { data: paymentsDueRaw } = await supabase
    .from("invoices")
    .select(
      "id, invoice_number, invoice_type, balance_due, vessel:vessels(name)",
    )
    .eq("customer_id", customer.id)
    .in("status", ["sent", "partially_paid", "overdue"])
    .order("created_at", { ascending: false });

  const paymentsDue: CustomerPaymentDue[] = (paymentsDueRaw ?? [])
    .map((i: any) => ({
      id: i.id,
      invoiceNumber: i.invoice_number,
      invoiceType: i.invoice_type,
      vesselName: i.vessel?.name ?? null,
      balanceDue: Number(i.balance_due),
    }))
    .filter((i) => i.balanceDue > 0);

  return {
    firstName: customer.first_name,
    vessels: (vessels ?? []).map((v) => ({
      id: v.id,
      name: v.name,
      make: v.make,
      model: v.model,
      year: v.year,
      status: v.status,
    })),
    activeWorkOrders,
    recentWorkOrders,
    actionableEstimates,
    paymentsDue,
  };
}
