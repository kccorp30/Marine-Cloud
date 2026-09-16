import Link from "next/link";
import { redirect } from "next/navigation";
import { getSessionContext } from "@/lib/auth/session";
import { getActiveOrganizationId } from "@/lib/auth/active-org";
import { getLocale } from "@/lib/i18n/server";
import { commandCopy } from "@/lib/i18n/command-copy";
import { dictionary } from "@/lib/i18n/dictionary";
import { getTechnicianDay, type DayJob } from "@/lib/technician/day-data";
import { CommandHero } from "@/components/ui/CommandHero";
import { MetricCard } from "@/components/ui/command";
import { LuzBriefing } from "@/components/luz/LuzBriefing";
import { TrackingAutoRefresh } from "@/components/work-orders/TrackingAutoRefresh";
import { getTechnicianPaySnapshot } from "@/lib/payroll/technician-summary";
import { TechnicianPayCard } from "@/components/technician/TechnicianPayCard";
export default async function TodayPage() {
  const session = await getSessionContext();
  const org = await getActiveOrganizationId(session.memberships);
  if (
    !org ||
    !session.memberships.some(
      (m) => m.organization_id === org && m.role === "technician",
    )
  )
    redirect("/dashboard");
  const locale = await getLocale();
  const t = commandCopy[locale];
  const [data, paySnapshot] = await Promise.all([
    getTechnicianDay(session.userId, org),
    getTechnicianPaySnapshot(org, session.userId),
  ]);
  const labels = dictionary[locale].status as Record<string, string>;
  const active = data.jobs.filter((j) =>
    ["checked_in", "diagnosis", "work_in_progress", "en_route"].includes(
      j.status,
    ),
  );
  const waiting = data.jobs.filter((j) =>
    ["waiting_parts", "waiting_customer_approval"].includes(j.status),
  );
  function row(job: DayJob) {
    return (
      <Link
        key={`${job.id}-${job.appointmentId}`}
        href={`/work-orders/${job.id}`}
        className="flex gap-4 items-center py-4 border-b border-white/10"
      >
        <span className="text-gold text-sm min-w-14">
          {job.scheduledStart
            ? new Date(job.scheduledStart).toLocaleTimeString(locale, {
                hour: "2-digit",
                minute: "2-digit",
                timeZone: data.timeZone,
              })
            : "—"}
        </span>
        <div className="min-w-0 flex-1">
          <p className="font-semibold text-sm">{job.vessel || job.title}</p>
          <p className="text-xs text-cool-gray mt-1">{job.title}</p>
          <p className="text-xs text-emerald-300 mt-2">
            {labels[job.status] || job.status}
          </p>
        </div>
        <span className="text-gold">→</span>
      </Link>
    );
  }
  return (
    <div className="command-stack">
      <TrackingAutoRefresh />
      <CommandHero
        eyebrow={`KCC · ${t.field}`}
        title={t.welcome}
        name={session.fullName?.split(" ")[0]}
        description={t.technicianSummary}
        actions={
          <Link
            href={
              active[0] ? `/work-orders/${active[0].id}#evidence` : "#day-plan"
            }
            className="command-button"
          >
            {active[0] ? t.evidence : t.plan} →
          </Link>
        }
      />
      <section className="launch-grid">
        <MetricCard label={t.today} value={data.today.length} tone="gold" />
        <MetricCard label={t.activeJobs} value={data.jobs.length} tone="blue" />
        <MetricCard label={t.working} value={active.length} tone="green" />
        <MetricCard label={t.waiting} value={waiting.length} tone="red" />
      </section>
      <div className="command-section">
        <section id="day-plan" className="command-panel p-6">
          <p className="eyebrow">{data.timeZone}</p>
          <h2 className="text-xl font-semibold mt-2">{t.plan}</h2>
          {data.today.length ? (
            data.today.map(row)
          ) : (
            <p className="command-empty">{t.noToday}</p>
          )}
        </section>
        <LuzBriefing jobs={data.jobs} locale={locale} />
      </div>
      <TechnicianPayCard snapshot={paySnapshot} locale={locale} profileId={session.userId} />
      <section className="command-panel p-6">
        <h2 className="text-xl font-semibold">{t.activeJobs}</h2>
        {data.jobs.length ? (
          data.jobs.map(row)
        ) : (
          <p className="command-empty">{t.noWork}</p>
        )}
      </section>
    </div>
  );
}
