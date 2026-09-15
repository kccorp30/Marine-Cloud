import "server-only";
import { createClient } from "@/lib/supabase/server";

// Mismos 18 estados reales del motor de work orders — nunca un motor
// paralelo, solo categorías de PRESENTACIÓN sobre current_status real
// (mismo principio que lib/work-orders/customer-stages.ts).
const ACTIVE_STATUSES = [
  "request_received",
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
const WAITING_STATUSES = [
  "waiting_parts",
  "waiting_customer_approval",
  "awaiting_approval",
];
const ASSIGNABLE_STATUSES = [
  "request_received",
  "triage",
  "estimate",
  "scheduled",
  "technician_assigned",
];

export interface WorkOverview {
  activeCount: number;
  awaitingAssignmentCount: number;
  scheduledTodayCount: number;
  inProgressCount: number;
  waitingCount: number;
  recentlyCompleted: {
    id: string;
    title: string;
    completedAt: string | null;
  }[];
}

export interface IncomingRequestsSummary {
  submittedCount: number;
  underReviewCount: number;
  recent: {
    id: string;
    title: string;
    customerName: string | null;
    urgency: string;
    createdAt: string;
  }[];
}

export interface TechnicianWorkloadRow {
  profileId: string;
  name: string;
  workingToday: boolean;
  activeAssignments: number;
}

export interface UpcomingAppointment {
  id: string;
  scheduledStart: string;
  workOrderId: string;
  workOrderTitle: string;
  technicianName: string | null;
}

export interface OperationalAlert {
  kind: "unassigned" | "overdue_appointment" | "request_waiting" | "stalled";
  message: string;
  workOrderId?: string;
}

export interface CommercialSummary {
  awaitingDecisionCount: number;
  recentlyApprovedCount: number;
  declinedNeedingReviewCount: number;
  pendingChangeOrdersCount: number;
}

export interface CompanyOperationsData {
  workOverview: WorkOverview;
  incomingRequests: IncomingRequestsSummary;
  technicianWorkload: TechnicianWorkloadRow[];
  upcomingAppointments: UpcomingAppointment[];
  alerts: OperationalAlert[];
  commercial: CommercialSummary;
}

// Server-only — cada query pasa por RLS normal (is_org_staff), esta
// función no agrega autorización propia, solo arma el DTO.
export async function getCompanyOperationsData(
  organizationId: string,
): Promise<CompanyOperationsData> {
  const supabase = await createClient();
  const todayStart = new Date();
  todayStart.setHours(0, 0, 0, 0);
  const todayEnd = new Date(todayStart);
  todayEnd.setDate(todayEnd.getDate() + 1);

  const [
    activeWO,
    assignedWOIds,
    todayAppts,
    inProgressWO,
    waitingWO,
    recentCompleted,
    submittedReqs,
    underReviewReqs,
    recentReqs,
    technicians,
    activeAssignments,
    upcomingAppts,
  ] = await Promise.all([
    supabase
      .from("work_orders")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId)
      .in("current_status", ACTIVE_STATUSES)
      .throwOnError(),
    supabase
      .from("assignments")
      .select("work_order_id")
      .eq("organization_id", organizationId)
      .eq("status", "active")
      .throwOnError(),
    supabase
      .from("appointments")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId)
      .gte("scheduled_start", todayStart.toISOString())
      .lt("scheduled_start", todayEnd.toISOString())
      .throwOnError(),
    supabase
      .from("work_orders")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId)
      .in("current_status", ["work_in_progress", "diagnosis"])
      .throwOnError(),
    supabase
      .from("work_orders")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId)
      .in("current_status", WAITING_STATUSES)
      .throwOnError(),
    supabase
      .from("work_orders")
      .select("id, title, updated_at")
      .eq("organization_id", organizationId)
      .eq("current_status", "completed")
      .order("updated_at", { ascending: false })
      .limit(5)
      .throwOnError(),
    supabase
      .from("service_requests")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId)
      .eq("status", "submitted")
      .throwOnError(),
    supabase
      .from("service_requests")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId)
      .eq("status", "under_review")
      .throwOnError(),
    supabase
      .from("service_requests")
      .select(
        "id, title, urgency, created_at, customer:customers(first_name, last_name)",
      )
      .eq("organization_id", organizationId)
      .in("status", ["submitted", "under_review"])
      .order("created_at", { ascending: false })
      .limit(5)
      .throwOnError(),
    supabase
      .from("organization_memberships")
      .select("profile_id, profile:profiles(full_name)")
      .eq("organization_id", organizationId)
      .eq("role", "technician")
      .eq("status", "active")
      .throwOnError(),
    supabase
      .from("assignments")
      .select("technician_profile_id, work_order_id")
      .eq("organization_id", organizationId)
      .eq("status", "active")
      .throwOnError(),
    supabase
      .from("appointments")
      .select("id, scheduled_start, work_order:work_orders(id, title)")
      .eq("organization_id", organizationId)
      .gte("scheduled_start", new Date().toISOString())
      .order("scheduled_start", { ascending: true })
      .limit(5)
      .throwOnError(),
  ]);

  const assignedWorkOrderIds = new Set(
    (assignedWOIds.data ?? []).map((a: any) => a.work_order_id),
  );

  // Awaiting assignment: work order en estado asignable, sin ninguna assignment activa.
  const { data: assignableWO } = await supabase
    .from("work_orders")
    .select("id")
    .eq("organization_id", organizationId)
    .in("current_status", ASSIGNABLE_STATUSES);
  const awaitingAssignment = (assignableWO ?? []).filter(
    (wo) => !assignedWorkOrderIds.has(wo.id),
  );

  const { data: checkInsToday } = await supabase
    .from("check_ins")
    .select("technician_profile_id")
    .eq("organization_id", organizationId)
    .gte("checked_in_at", todayStart.toISOString())
    .lt("checked_in_at", todayEnd.toISOString());
  const workingTodayIds = new Set(
    (checkInsToday ?? []).map((c: any) => c.technician_profile_id),
  );

  const assignmentCountByTech = new Map<string, number>();
  for (const a of activeAssignments.data ?? []) {
    assignmentCountByTech.set(
      a.technician_profile_id,
      (assignmentCountByTech.get(a.technician_profile_id) ?? 0) + 1,
    );
  }

  const technicianWorkload: TechnicianWorkloadRow[] = (
    technicians.data ?? []
  ).map((t: any) => ({
    profileId: t.profile_id,
    name: t.profile?.full_name ?? "Technician",
    workingToday: workingTodayIds.has(t.profile_id),
    activeAssignments: assignmentCountByTech.get(t.profile_id) ?? 0,
  }));

  // Alertas — derivadas del estado real, sin inventar infraestructura de notificaciones.
  const alerts: OperationalAlert[] = [];
  for (const wo of awaitingAssignment.slice(0, 5)) {
    alerts.push({
      kind: "unassigned",
      message: "Work order awaiting technician assignment",
      workOrderId: wo.id,
    });
  }
  const { data: overdueAppts } = await supabase
    .from("appointments")
    .select("id, work_order_id")
    .eq("organization_id", organizationId)
    .eq("status", "scheduled")
    .lt("scheduled_start", new Date().toISOString())
    .limit(5);
  for (const a of overdueAppts ?? []) {
    alerts.push({
      kind: "overdue_appointment",
      message:
        "Appointment is past its scheduled time and still marked scheduled",
      workOrderId: a.work_order_id,
    });
  }
  if ((submittedReqs.count ?? 0) > 0) {
    alerts.push({
      kind: "request_waiting",
      message: `${submittedReqs.count} new service request${submittedReqs.count === 1 ? "" : "s"} waiting for review`,
    });
  }
  const staleThreshold = new Date();
  staleThreshold.setDate(staleThreshold.getDate() - 5);
  const { data: stalledWO } = await supabase
    .from("work_orders")
    .select("id, title")
    .eq("organization_id", organizationId)
    .in("current_status", ACTIVE_STATUSES)
    .lt("last_activity_at", staleThreshold.toISOString())
    .limit(5);
  for (const wo of stalledWO ?? []) {
    alerts.push({
      kind: "stalled",
      message: `"${wo.title}" has had no activity in over 5 days`,
      workOrderId: wo.id,
    });
  }

  const recentThreshold = new Date();
  recentThreshold.setDate(recentThreshold.getDate() - 7);
  const [
    awaitingDecision,
    recentlyApproved,
    declinedNeedingReview,
    pendingChangeOrders,
  ] = await Promise.all([
    supabase
      .from("estimates")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId)
      .in("status", ["sent", "viewed"])
      .eq("type", "estimate"),
    supabase
      .from("estimates")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId)
      .eq("status", "approved")
      .gte("updated_at", recentThreshold.toISOString()),
    supabase
      .from("estimates")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId)
      .eq("status", "declined"),
    supabase
      .from("estimates")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId)
      .in("status", ["sent", "viewed"])
      .eq("type", "change_order"),
  ]);

  return {
    workOverview: {
      activeCount: activeWO.count ?? 0,
      awaitingAssignmentCount: awaitingAssignment.length,
      scheduledTodayCount: todayAppts.count ?? 0,
      inProgressCount: inProgressWO.count ?? 0,
      waitingCount: waitingWO.count ?? 0,
      recentlyCompleted: (recentCompleted.data ?? []).map((wo: any) => ({
        id: wo.id,
        title: wo.title,
        completedAt: wo.updated_at,
      })),
    },
    commercial: {
      awaitingDecisionCount: awaitingDecision.count ?? 0,
      recentlyApprovedCount: recentlyApproved.count ?? 0,
      declinedNeedingReviewCount: declinedNeedingReview.count ?? 0,
      pendingChangeOrdersCount: pendingChangeOrders.count ?? 0,
    },
    incomingRequests: {
      submittedCount: submittedReqs.count ?? 0,
      underReviewCount: underReviewReqs.count ?? 0,
      recent: (recentReqs.data ?? []).map((r: any) => ({
        id: r.id,
        title: r.title,
        customerName: r.customer
          ? `${r.customer.first_name} ${r.customer.last_name}`
          : null,
        urgency: r.urgency,
        createdAt: r.created_at,
      })),
    },
    technicianWorkload,
    upcomingAppointments: (upcomingAppts.data ?? []).map((a: any) => ({
      id: a.id,
      scheduledStart: a.scheduled_start,
      workOrderId: a.work_order?.id,
      workOrderTitle: a.work_order?.title ?? "Work Order",
      technicianName: null,
    })),
    alerts,
  };
}
