import {CreateWorkOrderFlow} from "@/components/work-orders/CreateWorkOrderFlow";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { getSessionContext } from "@/lib/auth/session";
import { getActiveOrganizationId } from "@/lib/auth/active-org";
import { createWorkOrder } from "@/lib/work-orders/actions";
import {
  Card,
  PageTitle,
  Field,
  inputClass,
  SubmitButton,
  StatusBadge,
} from "@/components/ui/primitives";
import { RelativeTime } from "@/components/work-orders/Timeline";

const STATUS_OPTIONS = [
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
  "invoice",
  "payment",
  "completed",
  "warranty",
  "cancelled",
];

export default async function WorkOrdersPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; q?: string; customer?:string }>;
}) {
  const { status, q, customer } = await searchParams;
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const activeMembership = session.memberships.find(
    (m) => m.organization_id === activeOrgId,
  );
  const canCreate =
    session.isKccAdmin ||
    ["company_owner", "company_admin", "manager"].includes(
      activeMembership?.role ?? "",
    );
  const canFilter =
    session.isKccAdmin ||
    ["company_owner", "company_admin", "manager"].includes(
      activeMembership?.role ?? "",
    );

  const supabase = await createClient();

  // Misma query para los 3 roles — RLS ya devuelve solo lo que cada
  // uno puede ver (staff: todo el tenant; technician: solo asignados;
  // customer: solo lo propio). No hay lógica de rol acá, salvo los
  // filtros (que solo tienen sentido cuando hay volumen — staff).
  let query = supabase
    .from("work_orders")
    .select(
      "id, title, current_status, priority, created_at, last_activity_at, customer:customers(first_name, last_name), vessel:vessels(name)",
    )
    .eq("organization_id", activeOrgId)
    .order("created_at", { ascending: false });

  if (canFilter && status) query = query.eq("current_status", status);
  if (canFilter && q) query = query.ilike("title", `%${q}%`);

  const { data: workOrders } = await query;

  const { data: customers } = canCreate
    ? await supabase
        .from("customers")
        .select("id, first_name, last_name")
        .eq("organization_id", activeOrgId)
    : { data: [] };
  const { data: vessels } = canCreate
    ? await supabase
        .from("vessels")
        .select("id, name, current_customer_id")
        .eq("organization_id", activeOrgId)
    : { data: [] };

  return (
    <div className="max-w-4xl">
      <PageTitle>
        {activeMembership?.role === "technician"
          ? "Assigned Work"
          : activeMembership?.role === "customer"
            ? "My Service"
            : "Work Orders"}
      </PageTitle>

      {canCreate && <div className="mb-6" id="new-work-order"><CreateWorkOrderFlow customers={customers??[]} vessels={vessels??[]} initialCustomer={customer}/></div>}

      {canFilter && (
        <form method="GET" className="flex gap-3 flex-wrap mb-4 items-end">
          <div className="min-w-[160px]">
            <Field label="Status">
              <select
                name="status"
                defaultValue={status ?? ""}
                className={inputClass}
              >
                <option value="">All</option>
                {STATUS_OPTIONS.map((s) => (
                  <option key={s} value={s} className="bg-navy">
                    {s.replace(/_/g, " ")}
                  </option>
                ))}
              </select>
            </Field>
          </div>
          <div className="flex-1 min-w-[180px]">
            <Field label="Search title">
              <input
                name="q"
                defaultValue={q ?? ""}
                className={inputClass}
                placeholder="e.g. no power"
              />
            </Field>
          </div>
          <SubmitButton>Filter</SubmitButton>
          {(status || q) && (
            <Link
              href="/work-orders"
              className="text-[10px] font-mono uppercase text-cool-gray hover:text-gold pb-2.5"
            >
              Clear
            </Link>
          )}
        </form>
      )}

      <div className="kcc-record-grid">
        {(workOrders ?? []).map((wo: any) => (
          <Link key={wo.id} href={`/work-orders/${wo.id}`}>
            <Card className="flex items-center justify-between hover:border-gold/40 transition-colors">
              <div>
                <div className="text-sm font-semibold">{wo.title}</div>
                <div className="text-xs text-cool-gray">
                  {wo.customer
                    ? `${wo.customer.first_name} ${wo.customer.last_name}`
                    : "—"}{" "}
                  · {wo.vessel?.name || "Unnamed Vessel"}
                </div>
              </div>
              <div className="text-right">
                <StatusBadge status={wo.current_status} />
                <div className="mt-1">
                  <RelativeTime date={wo.last_activity_at ?? wo.created_at} />
                </div>
              </div>
            </Card>
          </Link>
        ))}
        {(!workOrders || workOrders.length === 0) && (
          <p className="text-sm text-cool-gray">No work orders yet.</p>
        )}
      </div>
    </div>
  );
}
