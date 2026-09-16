import Link from "next/link";
import { commandCopy } from "@/lib/i18n/command-copy";
import type { Locale } from "@/lib/i18n/dictionary";
import type { DayJob } from "@/lib/technician/day-data";
export function LuzBriefing({
  jobs,
  locale,
}: {
  jobs: DayJob[];
  locale: Locale;
}) {
  const t = commandCopy[locale];
  const waiting = jobs.filter((j) =>
    [
      "waiting_parts",
      "waiting_customer_approval",
      "awaiting_approval",
    ].includes(j.status),
  );
  const current =
    jobs.find((j) =>
      ["checked_in", "diagnosis", "work_in_progress", "en_route"].includes(
        j.status,
      ),
    ) || jobs[0];
  return (
    <section className="command-panel p-6 border-gold/30">
      <div className="flex gap-4 items-center">
        <span className="luz-orb" aria-hidden="true">
          ✦
        </span>
        <div>
          <p className="eyebrow text-gold">LUZ · {t.field}</p>
          <h2 className="text-xl font-semibold mt-1">{t.briefing}</h2>
        </div>
      </div>
      <p className="text-sm text-cool-gray my-5">{t.briefingDetail}</p>
      <div className="space-y-3">
        {current ? (
          <div className="p-4 rounded-xl bg-white/[.03] border border-white/10">
            <p className="command-kicker">{t.next}</p>
            <p className="text-base mt-2 font-semibold">
              {current.vessel || current.title}
            </p>
            <p className="text-sm text-cool-gray mt-1">{current.title}</p>
            <div className="flex flex-wrap gap-2 mt-4">
              <Link
                className="command-button"
                href={`/work-orders/${current.id}#technician-actions`}
              >
                {t.open} →
              </Link>
              <Link
                className="command-button command-button-secondary"
                href={`/work-orders/${current.id}#evidence`}
              >
                {t.evidence}
              </Link>
            </div>
          </div>
        ) : (
          <p className="text-sm text-cool-gray">{t.noWork}</p>
        )}
        {waiting.map((j) => (
          <Link
            key={j.id}
            href={`/work-orders/${j.id}`}
            className="block p-3 rounded-xl bg-amber-300/5 border border-amber-300/20 text-sm"
          >
            <span className="text-amber-200">{t.waiting}</span> · {j.title} →
          </Link>
        ))}
      </div>
      <Link
        href="/kcc-assistance"
        className="inline-flex text-sm text-gold mt-5 py-2"
      >
        {t.support} →
      </Link>
    </section>
  );
}
