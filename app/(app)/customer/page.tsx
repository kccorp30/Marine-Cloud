import {TrackingStatusPanel} from "@/components/tracking/TrackingStatusPanel";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getSessionContext } from "@/lib/auth/session";
import { getActiveOrganizationId } from "@/lib/auth/active-org";
import { getLocale } from "@/lib/i18n/server";
import { commandCopy } from "@/lib/i18n/command-copy";
import { dictionary } from "@/lib/i18n/dictionary";
import { getCustomerHomeData } from "@/lib/customer/home-data";
import { getCustomerWorkOrderTracking } from "@/lib/work-orders/customer-tracking";
import { createClient } from "@/lib/supabase/server";
import { CommandHero } from "@/components/ui/CommandHero";
import { MetricCard } from "@/components/ui/command";
import { StatusTimeline } from "@/components/ui/StatusTimeline";
import { LuzPresence } from "@/components/luz/LuzPresence";
export default async function CustomerPage() {
  const session = await getSessionContext();
  const org = await getActiveOrganizationId(session.memberships);
  if (
    !org ||
    !session.memberships.some(
      (m) => m.organization_id === org && m.role === "customer",
    )
  )
    redirect("/dashboard");
  const locale = await getLocale();
  const t = commandCopy[locale];
  const labels = dictionary[locale].status as Record<string, string>;
  const data = await getCustomerHomeData(session.userId, org);
  if (!data)
    return (
      <section className="command-panel command-empty">
        <h1 className="text-xl">{t.waitingAccess}</h1>
        <p>{t.accessDetail}</p>
      </section>
    );
  const active = data.activeWorkOrders[0];
  const tracking = active
    ? await getCustomerWorkOrderTracking(active.id)
    : null;
  const db = await createClient();
  const history = active
    ? await db
        .from("work_order_status_history")
        .select("to_status,occurred_at")
        .eq("work_order_id", active.id)
        .order("occurred_at", { ascending: true })
    : null;
  return (
    <div className="command-stack">
      <CommandHero
        eyebrow="KCC · MARINE CLOUD"
        title={t.welcome}
        name={data.firstName || undefined}
        description={t.vesselSummary}
        actions={
          active ? (
            <Link className="command-button" href={`/work-orders/${active.id}`}>
              {t.service} →
            </Link>
          ) : (
            <Link className="command-button" href="/request-service">
              {t.requests} →
            </Link>
          )
        }
      />
      <section className="kcc-command-strip">
        <MetricCard
          label={t.active}
          value={data.activeWorkOrders.length}
          tone="gold"
        />
        <MetricCard
          label={t.vessels}
          value={data.vessels.length}
          href="/vessels"
          tone="blue"
        />
        <MetricCard
          label={t.approvals}
          value={data.actionableEstimates.length}
          href="/estimates"
          tone="green"
        />
        <MetricCard
          label={t.openInvoices}
          value={data.paymentsDue.length}
          href="/invoices"
          tone="red"
        />
      </section>
      {active && <section className="kcc-section"><h2 className="font-semibold mb-4">{t.service}</h2><TrackingStatusPanel workOrderId={active.id}/></section>}
      <div className="command-section">
        <section className="command-panel p-6">
          <div className="flex justify-between gap-4">
            <h2 className="text-xl font-semibold">{t.service}</h2>
            {active && (
              <Link
                className="text-gold text-sm"
                href={`/work-orders/${active.id}`}
              >
                {t.details} →
              </Link>
            )}
          </div>
          {active ? (
            <>
              <p className="mt-5 text-2xl font-semibold">
                {active.vesselName || active.title}
              </p>
              <p className="text-cool-gray text-sm mt-2">{active.title}</p>
              <StatusTimeline
                status={active.currentStatus}
                locale={locale}
                events={(history?.data || []).map((e) => ({
                  status: e.to_status,
                  at: e.occurred_at,
                }))}
              />
              <div className="rounded-xl border border-gold/20 bg-gold/5 p-4">
                <p className="command-kicker">{t.status}</p>
                <p className="text-lg mt-2 text-gold">
                  {labels[active.currentStatus] || active.currentStatus}
                </p>
              </div>
              {tracking?.progressUpdates.slice(0, 3).map((update) => (
                <article
                  key={update.id}
                  className="mt-5 border-t border-white/10 pt-5"
                >
                  <p className="text-sm leading-relaxed">{update.body}</p>
                  <div className="flex gap-3 overflow-x-auto mt-3">
                    {update.photoUrls.map((url) => (
                      <a href={url} key={url} target="_blank" rel="noreferrer">
                        <img
                          src={url}
                          alt={t.evidence}
                          className="w-24 h-24 rounded-xl object-cover shrink-0"
                          loading="lazy"
                        />
                      </a>
                    ))}
                  </div>
                  <time className="text-xs text-cool-gray mt-3 block">
                    {new Date(update.createdAt).toLocaleDateString(locale)}
                  </time>
                </article>
              ))}
            </>
          ) : (
            <p className="command-empty">{t.noWorkDetail}</p>
          )}
        </section>
        <div className="command-stack">
          <section className="command-panel p-6">
            <h2 className="text-lg font-semibold">{t.technician}</h2>
            {tracking?.technician ? (
              <div className="flex items-center gap-4 mt-5">
                {tracking.technician.avatarUrl ? (
                  <img
                    className="h-16 w-16 rounded-full object-cover border border-gold/40"
                    src={tracking.technician.avatarUrl}
                    alt=""
                  />
                ) : (
                  <span className="h-14 w-14 rounded-full bg-gold/10 text-gold grid place-items-center">
                    {tracking.technician.name[0]}
                  </span>
                )}
                <p>{tracking.technician.name}</p>
              </div>
            ) : (
              <p className="text-sm text-cool-gray mt-4">{t.unscheduled}</p>
            )}
          </section>
          <section className="command-panel p-6">
            <h2 className="text-lg font-semibold">{t.myVessel}</h2>
            {data.vessels.map((v) => (
              <Link
                key={v.id}
                href={`/vessels/${v.id}`}
                className="flex justify-between py-4 border-b border-white/10 text-sm"
              >
                <span>
                  {v.name || `${v.make || ""} ${v.model || ""}`}
                  <small className="block text-cool-gray mt-1">
                    {[v.make, v.model, v.year].filter(Boolean).join(" · ")}
                  </small>
                </span>
                <span className="text-gold">→</span>
              </Link>
            ))}
          </section>
          <LuzPresence context="customer" />
        </div>
      </div>
      <div className="command-section">
        <section className="command-panel p-6">
          <h2 className="text-xl font-semibold">{t.approvals}</h2>
          {data.actionableEstimates.length ? (
            data.actionableEstimates.map((e) => (
              <Link
                className="flex justify-between py-4 border-b border-white/10"
                href={`/estimates/${e.id}`}
                key={e.id}
              >
                <span>
                  {e.estimateNumber} · {e.vesselName}
                </span>
                <span className="text-gold">{t.review} →</span>
              </Link>
            ))
          ) : (
            <p className="command-empty">{t.noEstimate}</p>
          )}
        </section>
        <section className="command-panel p-6">
          <h2 className="text-xl font-semibold">{t.invoices}</h2>
          {data.paymentsDue.length ? (
            data.paymentsDue.map((i) => (
              <Link
                className="flex justify-between py-4 border-b border-white/10"
                href={`/invoices/${i.id}`}
                key={i.id}
              >
                <span>
                  {i.invoiceNumber} · {i.vesselName}
                </span>
                <span className="text-gold">{t.open} →</span>
              </Link>
            ))
          ) : (
            <p className="command-empty">{t.noInvoice}</p>
          )}
        </section>
      </div>
      {data.activeWorkOrders.length > 1 && (
        <section className="command-panel p-6">
          <h2 className="text-xl">{t.workOrders}</h2>
          {data.activeWorkOrders.slice(1).map((w) => (
            <Link
              className="block py-4 border-b border-white/10"
              key={w.id}
              href={`/work-orders/${w.id}`}
            >
              {w.title} · {labels[w.currentStatus]} →
            </Link>
          ))}
        </section>
      )}
    </div>
  );
}
