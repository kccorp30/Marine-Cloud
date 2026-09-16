import Link from "next/link";
import { redirect } from "next/navigation";
import { getSessionContext } from "@/lib/auth/session";
import { getActiveOrganizationId } from "@/lib/auth/active-org";
import { getLocale } from "@/lib/i18n/server";
import { commandCopy } from "@/lib/i18n/command-copy";
import { dictionary } from "@/lib/i18n/dictionary";
import { getCompanyOperationsData } from "@/lib/company/operations-data";
import { createClient } from "@/lib/supabase/server";
import { CommandHero } from "@/components/ui/CommandHero";
import { MetricCard } from "@/components/ui/command";
import { LuzPresence } from "@/components/luz/LuzPresence";
import { CompanyKccAccountCard } from "@/components/kcc-control/CompanyKccAccountCard";
import { getCompanyKccAccountSummary } from "@/lib/company/kcc-account";
export default async function CompanyPage() {
  const session = await getSessionContext();
  const org = await getActiveOrganizationId(session.memberships);
  const membership = session.memberships.find((m) => m.organization_id === org);
  if (
    !org ||
    !membership ||
    (!session.isKccAdmin &&
      !["company_owner", "company_admin", "manager"].includes(membership.role))
  )
    redirect("/dashboard");
  const locale = await getLocale();
  const t = commandCopy[locale];
  const labels = dictionary[locale].status as Record<string, string>;
  const data = await getCompanyOperationsData(org);
  const canSeeKccAccount = session.isKccAdmin || ["company_owner", "company_admin"].includes(membership.role);
  const kccAccount = canSeeKccAccount ? await getCompanyKccAccountSummary(org) : null;
  const db = await createClient();
  const teamProfiles = await db.from('profiles').select('id,avatar_url').in('id', data.technicianWorkload.map(t=>t.profileId));
  const portraits = new Map((teamProfiles.data??[]).map(p=>[p.id,p.avatar_url]));
  const orders = await db
    .from("work_orders")
    .select(
      "id,title,current_status,vessel:vessels(name),customer:customers(first_name,last_name)",
    )
    .eq("organization_id", org)
    .order("created_at", { ascending: false })
    .limit(8);
  const [priorityRequests, approvedEstimates] = await Promise.all([
    db.from("service_requests")
      .select("id,title,urgency,created_at,customer:customers(first_name,last_name),vessel:vessels(name)")
      .eq("organization_id", org)
      .in("status", ["submitted", "under_review"])
      .order("created_at", { ascending: false })
      .limit(4),
    db.from("estimates")
      .select("id,estimate_number,updated_at,work_order_id,customer:customers(first_name,last_name),vessel:vessels(name)")
      .eq("organization_id", org)
      .eq("status", "approved")
      .order("updated_at", { ascending: false })
      .limit(4),
  ]);
  return (
    <div className="command-stack kcc-company">
      <CommandHero
        eyebrow={membership.organization.name}
        title={t.welcome}
        name={session.fullName?.split(" ")[0]}
        description={t.workSummary}
        actions={
          <>
            <Link className="command-button" href="/work-orders#new-work-order">
              ＋ {t.newOrder}
            </Link>
            <Link
              className="command-button command-button-secondary"
              href="/team"
            >
              {t.team} →
            </Link>
          </>
        }
      />
      {(data.incomingRequests.submittedCount > 0 || data.commercial.recentlyApprovedCount > 0 || data.workOverview.awaitingAssignmentCount > 0) && (
        <section className="operations-attention">
          <div className="operations-attention-glow" />
          <div className="relative flex flex-col xl:flex-row xl:items-center justify-between gap-5">
            <div>
              <p className="eyebrow text-amber-200">✦ LUZ · {locale === "es" ? "REQUIERE TU ATENCIÓN" : "NEEDS YOUR ATTENTION"}</p>
              <h2 className="text-2xl font-semibold mt-2">{locale === "es" ? "Hay novedades operativas listas para actuar" : "Operational updates are ready for action"}</h2>
              <p className="text-sm text-cool-gray mt-2 max-w-2xl">
                {locale === "es" ? "Las solicitudes nuevas, estimados aprobados y trabajos sin técnico se mantienen visibles hasta que el equipo actúe." : "New requests, approved estimates and jobs without a technician stay visible until your team acts."}
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              {data.incomingRequests.submittedCount > 0 && <Link href="/service-requests" className="attention-chip"><strong>{data.incomingRequests.submittedCount}</strong> {locale === "es" ? "solicitud nueva" : "new request"} →</Link>}
              {data.commercial.recentlyApprovedCount > 0 && <Link href="/estimates?status=approved" className="attention-chip attention-chip-green"><strong>{data.commercial.recentlyApprovedCount}</strong> {locale === "es" ? "aprobado" : "approved"} →</Link>}
              {data.workOverview.awaitingAssignmentCount > 0 && <Link href="/work-orders" className="attention-chip attention-chip-blue"><strong>{data.workOverview.awaitingAssignmentCount}</strong> {locale === "es" ? "sin asignar" : "unassigned"} →</Link>}
            </div>
          </div>
          <div className="relative grid lg:grid-cols-2 gap-3 mt-5">
            {(priorityRequests.data ?? []).slice(0,2).map((r:any) => <Link key={r.id} href="/service-requests" className="attention-item"><span className="attention-icon">!</span><span><b>{r.title}</b><small>{[r.customer?.first_name,r.customer?.last_name].filter(Boolean).join(" ")} · {r.vessel?.name || "Vessel"}</small></span><span className="text-gold">Review →</span></Link>)}
            {(approvedEstimates.data ?? []).filter((e:any)=>!e.work_order_id).slice(0,2).map((e:any) => <Link key={e.id} href={`/estimates/${e.id}`} className="attention-item"><span className="attention-icon attention-icon-green">✓</span><span><b>{locale === "es" ? "Estimado aprobado" : "Estimate approved"} · {e.estimate_number}</b><small>{[e.customer?.first_name,e.customer?.last_name].filter(Boolean).join(" ")} · {e.vessel?.name || "Vessel"}</small></span><span className="text-gold">{locale === "es" ? "Crear orden" : "Create job"} →</span></Link>)}
          </div>
        </section>
      )}
      {kccAccount && <CompanyKccAccountCard summary={kccAccount} locale={locale} />}
      <section className="kcc-command-strip">
        <MetricCard
          label={t.active}
          value={data.workOverview.activeCount}
          href="/work-orders"
          tone="gold"
        />
        <MetricCard
          label={t.today}
          value={data.workOverview.scheduledTodayCount}
          href="/schedule"
          tone="blue"
        />
        <MetricCard
          label={t.approvals}
          value={data.commercial.awaitingDecisionCount}
          href="/estimates"
          tone="green"
        />
        <MetricCard
          label={t.waiting}
          value={data.workOverview.waitingCount}
          href="/work-orders"
          tone="red"
        />
      </section>
      <div className="command-section">
        <section className="kcc-section">
          <div className="flex justify-between gap-3 mb-5">
            <h2 className="text-xl font-semibold">{t.workOrders}</h2>
            <Link href="/work-orders" className="text-sm text-gold">
              {t.viewAll} →
            </Link>
          </div>
          <div className="command-table">
            <div className="command-table-head grid-cols-[1fr_1.5fr_1fr]">
              <span>{t.status}</span>
              <span>{t.service}</span>
              <span>{t.vessels}</span>
            </div>
            {orders.error ? (
              <p role="alert" className="p-5">
                {t.unavailable}
              </p>
            ) : orders.data?.length ? (
              orders.data.map((w: any) => (
                <Link
                  className="command-table-row grid-cols-[1fr_1.5fr_1fr] items-center"
                  key={w.id}
                  href={`/work-orders/${w.id}`}
                >
                  <span className="text-xs text-gold">
                    {labels[w.current_status] || w.current_status}
                  </span>
                  <span className="text-sm">
                    {w.title}
                    <small className="block text-cool-gray mt-1">
                      {[w.customer?.first_name, w.customer?.last_name]
                        .filter(Boolean)
                        .join(" ")}
                    </small>
                  </span>
                  <span className="text-xs text-cool-gray">
                    {w.vessel?.name || "—"}
                  </span>
                </Link>
              ))
            ) : (
              <p className="command-empty">{t.noWork}</p>
            )}
          </div>
        </section>
        <div className="command-stack">
          <section className="kcc-section">
            <h2 className="text-xl font-semibold">{t.team}</h2>
            {data.technicianWorkload.map((tech) => (
              <Link href={membership.role === "manager" ? "/team" : `/team/${tech.profileId}`}
                key={tech.profileId}
                className="py-4 flex gap-4 items-center border-b border-white/10"
              >
                {portraits.get(tech.profileId) ? <img src={portraits.get(tech.profileId)!} alt="" className="w-16 h-16 rounded-2xl object-cover"/> : <span className="w-16 h-16 rounded-2xl grid place-items-center bg-blue-300/10 text-blue-200">{tech.name[0]}</span>}
                <div className="flex-1">
                  <p className="text-sm">{tech.name}</p>
                  <p className="text-xs text-cool-gray mt-1">
                    {tech.activeAssignments} · {t.activeJobs}
                  </p>
                </div>
                <span className="text-gold">→</span>
              </Link>
            ))}
            {!data.technicianWorkload.length && (
              <Link className="command-button mt-5" href="/team">
                {t.team} →
              </Link>
            )}
          </section>
          <LuzPresence context="company" />
        </div>
      </div>
      <div className="command-section">
        <section className="kcc-section">
          <h2 className="text-xl font-semibold">{t.schedule}</h2>
          {data.upcomingAppointments.map((a) => (
            <Link
              className="flex justify-between gap-4 py-4 border-b border-white/10 text-sm"
              href={`/work-orders/${a.workOrderId}`}
              key={a.id}
            >
              <span>{a.workOrderTitle}</span>
              <time className="text-cool-gray">
                {new Date(a.scheduledStart).toLocaleString(locale, {
                  month: "short",
                  day: "numeric",
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </time>
            </Link>
          ))}
          {!data.upcomingAppointments.length && (
            <p className="command-empty">{t.noData}</p>
          )}
        </section>
        <section className="kcc-section">
          <h2 className="text-xl font-semibold">{t.attention}</h2>
          {data.alerts.map((a, i) => (
            <Link
              className="block p-4 mt-3 rounded-xl border border-amber-300/20 bg-amber-300/5 text-sm"
              href={
                a.workOrderId
                  ? `/work-orders/${a.workOrderId}`
                  : "/service-requests"
              }
              key={i}
            >
              {locale === "es"
                ? {
                    unassigned: "Orden sin técnico asignado",
                    overdue_appointment:
                      "Cita pendiente después de su hora programada",
                    request_waiting: "Solicitud pendiente de revisión",
                    stalled: "Trabajo pendiente de seguimiento",
                  }[a.kind]
                : a.message}{" "}
              →
            </Link>
          ))}
          {!data.alerts.length && <p className="command-empty">{t.noAlerts}</p>}
        </section>
      </div>
      <section className="kcc-command-strip">
        {[
          ["/customers", t.customers],
          ["/vessels", t.vessels],
          ["/invoices", t.invoices],
          ...(membership.role !== "manager" ? [["/finances", locale === "es" ? "Finanzas y equipo" : "Finances & team"]] : []),
          ["/warranty", t.warranty],
        ].map(([href, label]) => (
          <Link
            className="command-panel p-6 text-sm flex justify-between"
            href={href}
            key={href}
          >
            {label}
            <span className="text-gold">→</span>
          </Link>
        ))}
      </section>
    </div>
  );
}
