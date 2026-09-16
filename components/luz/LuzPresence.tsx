import Link from "next/link";
import { getLocale } from "@/lib/i18n/server";
import { commandCopy } from "@/lib/i18n/command-copy";
export async function LuzPresence({
  context = "company",
  compact = false,
}: {
  context?: "admin" | "company" | "technician" | "customer";
  compact?: boolean;
}) {
  const locale = await getLocale();
  const t = commandCopy[locale];
  const customer = context === "customer";
  return (
    <section className="luz-card p-5">
      <div className="luz-orb" aria-hidden="true">
        ✦
      </div>
      <div className="min-w-0">
        <p className="eyebrow text-gold">LUZ</p>
        <h2 className="text-lg font-semibold mt-1">
          {customer ? t.support : t.tools}
        </h2>
        {!compact && (
          <p className="text-xs text-cool-gray mt-2 leading-relaxed">
            {customer
              ? locale === "es"
                ? "Conecta con tu equipo y consulta las actualizaciones del servicio."
                : "Connect with your team and review service updates."
              : t.aiHelp}
          </p>
        )}
        <Link
          className="inline-block text-sm text-gold py-3"
          href={
            customer
              ? "/messages"
              : context === "technician"
                ? "/today"
                : "/luz"
          }
        >
          {t.open} →
        </Link>
      </div>
    </section>
  );
}
