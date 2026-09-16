import { UiText } from "@/components/ui/UiText";
import { LaunchAccessButton } from "@/components/launch/LaunchAccessButton";
import { getLocale } from "@/lib/i18n/server";
import Link from "next/link";
import { getSessionContext } from "@/lib/auth/session";
import { redirect } from "next/navigation";
import { getCompanyNetwork } from "@/lib/kcc-control/company-data";
import { CreateOrganizationForm } from "@/components/kcc-control/CreateOrganizationForm";
import { getAllPlans } from "@/lib/subscriptions/data";
import { PageTitle } from "@/components/ui/primitives";

const STATUS_COLOR: Record<string, string> = {
  active: "text-emerald-400",
  inactive: "text-cool-gray",
  suspended: "text-red-400",
  archived: "text-red-400",
};

export default async function CompaniesPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; q?: string; compensation?: string }>;
}) {
  const locale = await getLocale();
  const session = await getSessionContext();
  if (!session.isKccAdmin) redirect("/dashboard");

  const { status, q, compensation } = await searchParams;
  const allCompanies = await getCompanyNetwork({ status, search: q });
  const companies =
    compensation === "none"
      ? allCompanies.filter((c) => !c.compensationType)
      : compensation
        ? allCompanies.filter((c) => c.compensationType === compensation)
        : allCompanies;
  const plans = await getAllPlans();

  return (
    <div className="max-w-3xl space-y-6">
      <div className="flex items-center justify-between">
        <PageTitle>
          {" "}
          <UiText text="Company Network" />{" "}
        </PageTitle>
        <CreateOrganizationForm plans={plans} />
      </div>

      <form className="flex gap-3 flex-wrap items-center" action="/companies">
        <input
          name="q"
          defaultValue={q}
          placeholder="Search by name…"
          className="text-xs bg-white/[0.04] border border-white/10 rounded-sm px-3 py-1.5"
        />
        <div className="flex gap-2 text-[10px] font-mono uppercase">
          <Link
            href="/companies"
            className={!status ? "text-gold" : "text-cool-gray"}
          >
            {" "}
            <UiText text="All" />{" "}
          </Link>
          <Link
            href="/companies?status=active"
            className={status === "active" ? "text-gold" : "text-cool-gray"}
          >
            {" "}
            <UiText text="Active" />{" "}
          </Link>
          <Link
            href="/companies?status=inactive"
            className={status === "inactive" ? "text-gold" : "text-cool-gray"}
          >
            {" "}
            <UiText text="Inactive" />{" "}
          </Link>
          <Link
            href="/companies?status=suspended"
            className={status === "suspended" ? "text-gold" : "text-cool-gray"}
          >
            {" "}
            <UiText text="Suspended" />{" "}
          </Link>
        </div>
        <div className="flex gap-2 text-[10px] font-mono uppercase border-l border-white/10 pl-3">
          <Link
            href="/companies"
            className={!compensation ? "text-gold" : "text-cool-gray"}
          >
            Any Comp.
          </Link>
          <Link
            href="/companies?compensation=percentage"
            className={
              compensation === "percentage" ? "text-gold" : "text-cool-gray"
            }
          >
            {" "}
            <UiText text="Percentage" />{" "}
          </Link>
          <Link
            href="/companies?compensation=fixed"
            className={
              compensation === "fixed" ? "text-gold" : "text-cool-gray"
            }
          >
            Fixed
          </Link>
          <Link
            href="/companies?compensation=none"
            className={compensation === "none" ? "text-gold" : "text-cool-gray"}
          >
            No Agreement
          </Link>
        </div>
        <button
          type="submit"
          className="text-[10px] font-mono uppercase text-cool-gray"
        >
          {" "}
          <UiText text="Search" />{" "}
        </button>
      </form>

      <div className="space-y-2">
        {companies.map((c) => (
          <div key={c.id}>
            <Link href={`/companies/${c.id}`}>
              <div className="bg-white/[0.03] border border-white/10 rounded-sm p-4 hover:border-gold/30 transition-colors">
                <div className="flex items-center justify-between mb-1">
                  <span className="text-sm font-semibold">{c.name}</span>
                  <span
                    className={`font-mono text-[9px] uppercase ${STATUS_COLOR[c.status] ?? "text-cool-gray"}`}
                  >
                    {c.status}
                  </span>
                </div>
                <div className="text-xs text-cool-gray">
                  {c.primaryLocation && <>{c.primaryLocation} · </>}
                  {c.ownerName ?? "No owner assigned"} ·{" "}
                  {c.activeTechnicianCount} technicians ·{" "}
                  {c.activeWorkOrderCount} active work orders
                  {c.compensationType && (
                    <> · {c.compensationType} compensation</>
                  )}
                </div>
              </div>
            </Link>
            <div className="px-4 pb-4">
              <LaunchAccessButton organizationId={c.id} locale={locale} />
            </div>
          </div>
        ))}
        {companies.length === 0 && (
          <p className="text-sm text-cool-gray">
            No companies match this filter.
          </p>
        )}
      </div>
    </div>
  );
}
