import Link from "next/link";
import { redirect } from "next/navigation";
import { getSessionContext } from "@/lib/auth/session";
import { getActiveOrganizationId } from "@/lib/auth/active-org";
import { getLocale } from "@/lib/i18n/server";
import { commandCopy } from "@/lib/i18n/command-copy";
import { getKccDashboardData } from "@/lib/kcc-control/dashboard-data";
import { getCompanyNetwork } from "@/lib/kcc-control/company-data";
import { CommandHero } from "@/components/ui/CommandHero";
import { MetricCard } from "@/components/ui/command";
import { LuzPresence } from "@/components/luz/LuzPresence";
export default async function DashboardPage() {
  const session = await getSessionContext();
  const locale = await getLocale();
  const t = commandCopy[locale];
  if (!session.isKccAdmin) {
    const org = await getActiveOrganizationId(session.memberships);
    const role = session.memberships.find(
      (m) => m.organization_id === org,
    )?.role;
    if (role)
      redirect(
        role === "technician"
          ? "/today"
          : role === "customer"
            ? "/customer"
            : "/company",
      );
    return (
      <section className="command-panel command-empty">
        <h1 className="text-2xl mb-4">{t.waitingAccess}</h1>
        <p>{t.accessDetail}</p>
        <Link href="/welcome" className="command-button mt-6">
          {t.profile}
        </Link>
      </section>
    );
  }
  const [data, companies] = await Promise.all([
    getKccDashboardData(),
    getCompanyNetwork({}),
  ]);
  return (
    <div className="command-stack">
      <CommandHero
        eyebrow="KCC CONTROL CENTER"
        title={t.welcome}
        name={session.fullName?.split(" ")[0]}
        description={t.adminSummary}
        actions={
          <>
            <Link className="command-button" href="/companies">
              ＋ {t.network}
            </Link>
            <Link
              className="command-button command-button-secondary"
              href="/kcc-assistance"
            >
              {t.assistance} →
            </Link>
          </>
        }
      />
      <section className="kcc-command-strip">
        <MetricCard
          label={t.network}
          value={data.activeOrganizations}
          detail={`${data.totalOrganizations} · ${t.total}`}
          href="/companies"
          tone="gold"
        />
        <MetricCard
          label={t.active}
          value={data.activeWorkOrders}
          href="/work-orders"
          tone="blue"
        />
        <MetricCard
          label={t.assistance}
          value={data.openAssistanceRequests}
          href="/kcc-assistance"
          tone="green"
        />
        <MetricCard
          label={t.approvals}
          value={data.estimatesAwaitingApproval}
          href="/estimates"
          tone="red"
        />
      </section>
      <div className="command-section">
        <section className="command-panel p-6">
          <div className="flex justify-between gap-4 mb-5">
            <h2 className="text-xl font-semibold">{t.network}</h2>
            <Link className="text-sm text-gold" href="/companies">
              {t.viewAll} →
            </Link>
          </div>
          <div className="command-table">
            <div className="command-table-head grid-cols-[1.5fr_1fr_80px_80px]">
              <span>{t.company}</span>
              <span>{t.status}</span>
              <span>{t.team}</span>
              <span>{t.workOrders}</span>
            </div>
            {companies.slice(0, 8).map((c) => (
              <Link
                className="command-table-row grid-cols-[1.5fr_1fr_80px_80px] items-center"
                href={`/companies/${c.id}`}
                key={c.id}
              >
                <span className="text-sm font-semibold">
                  {c.name}
                  <small className="block text-cool-gray font-normal mt-1">
                    {c.ownerName || "—"}
                  </small>
                </span>
                <span className="text-xs text-gold">{c.status}</span>
                <span>{c.activeTechnicianCount}</span>
                <span>{c.activeWorkOrderCount}</span>
              </Link>
            ))}
            {!companies.length && <p className="command-empty">{t.noData}</p>}
          </div>
        </section>
        <div className="command-stack">
          <section className="command-panel p-6">
            <h2 className="text-xl font-semibold">{t.attention}</h2>
            <Link
              href="/work-orders"
              className="flex justify-between py-5 border-b border-white/10 text-sm"
            >
              {t.waiting}
              <span className="text-amber-200">
                {data.workOrdersNeedingAttention}
              </span>
            </Link>
            <Link
              href="/invoices"
              className="flex justify-between py-5 text-sm"
            >
              {t.openInvoices}
              <span className="text-gold">{data.openInvoicesCount}</span>
            </Link>
          </section>
          <LuzPresence context="admin" />
        </div>
      </div>
      <section className="kcc-command-strip">
        {[
          ["/website-leads", t.leads],
          ["/kcc-assistance", t.assistance],
          ["/warranty", t.warranty],
          ["/commercial-dashboard", t.commercial],
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
      <section className="command-panel p-6">
        <h2 className="text-xl font-semibold">{t.activity}</h2>
        {data.recentActivity.map((a) => (
          <div
            className="flex flex-wrap justify-between gap-3 py-4 border-b border-white/10 text-sm"
            key={a.id}
          >
            <span>
              {a.organizationName || "KCC"}
              <small className="block text-cool-gray mt-1">
                {a.eventType.replaceAll("_", " ")}
              </small>
            </span>
            <time className="text-xs text-cool-gray">
              {new Date(a.occurredAt).toLocaleString(locale)}
            </time>
          </div>
        ))}
        {!data.recentActivity.length && (
          <p className="command-empty">{t.noData}</p>
        )}
      </section>
    </div>
  );
}
