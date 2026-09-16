import Link from "next/link";
import { getSessionContext } from "@/lib/auth/session";
import { getActiveOrganizationId } from "@/lib/auth/active-org";
import { createClient } from "@/lib/supabase/server";
import { getLocale } from "@/lib/i18n/server";
import { commandCopy } from "@/lib/i18n/command-copy";
export default async function SearchPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const session = await getSessionContext();
  const org = await getActiveOrganizationId(session.memberships);
  const locale = await getLocale();
  const t = commandCopy[locale];
  const { q = "" } = await searchParams;
  const query = q.trim().slice(0, 100);
  const db = await createClient();
  let results: { id: string; title: string }[] = [];
  let failed = false;
  if (query.length >= 2 && (org || session.isKccAdmin)) {
    let request = db
      .from("work_orders")
      .select("id,title")
      .ilike("title", `%${query.replace(/[%_\\]/g, "\\$&")}%`)
      .order("created_at", { ascending: false })
      .limit(30);
    if (!session.isKccAdmin) request = request.eq("organization_id", org);
    const response = await request;
    failed = !!response.error;
    results = response.data || [];
  }
  return (
    <div className="command-stack">
      <h1 className="text-3xl font-semibold">{t.search}</h1>
      <form className="flex gap-3">
        <label className="command-field flex-1">
          <span>{t.workOrders}</span>
          <input name="q" defaultValue={query} minLength={2} maxLength={100} />
        </label>
        <button className="command-button self-end">{t.search}</button>
      </form>
      <section className="command-panel p-5">
        {failed ? (
          <p role="alert">{t.unavailable}</p>
        ) : results.length ? (
          results.map((r) => (
            <Link
              className="block p-4 border-b border-white/10"
              key={r.id}
              href={`/work-orders/${r.id}`}
            >
              {r.title}
              <span className="float-right text-gold">→</span>
            </Link>
          ))
        ) : (
          <p className="command-empty">{t.noData}</p>
        )}
      </section>
    </div>
  );
}
