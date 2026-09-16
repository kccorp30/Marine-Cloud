import {PendingSubmit} from './PendingSubmit';
import { UiText } from "./UiText";
import { dictionary, DEFAULT_LOCALE } from "@/lib/i18n/dictionary";
import type { Locale } from "@/lib/i18n/dictionary";

export function Card({
  children,
  className = "",
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      className={`premium-card rounded-xl p-5 shadow-premium animate-fade-up ${className}`}
    >
      {children}
    </div>
  );
}

export function PageTitle({ children }: { children: React.ReactNode }) {
  return (
    <h1 className="font-display font-bold text-2xl lg:text-3xl tracking-tight mb-6 text-marine-white">
      {children}
    </h1>
  );
}

export function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <span className="block font-mono text-[10px] uppercase tracking-[0.1em] text-cool-gray mb-1.5">
        <UiText text={label} />
      </span>
      {children}
    </label>
  );
}

export const inputClass =
  "w-full bg-[#071524]/80 border border-white/10 focus:border-gold/70 focus:shadow-glow-gold outline-none px-3.5 py-3 text-sm rounded-lg transition-all duration-200 placeholder:text-cool-gray/45";

export function SubmitButton({children}:{children:React.ReactNode}) {return <PendingSubmit>{children}</PendingSubmit>;}

export function StatusBadge({
  status,
  locale = DEFAULT_LOCALE,
}: {
  status: string;
  locale?: Locale;
}) {
  const label =
    (dictionary[locale].status as Record<string, string>)[status] ??
    status.replace(/_/g, " ");
  const lower = status.toLowerCase();
  const tone = ["completed", "paid", "active", "verified"].includes(lower)
    ? "text-emerald-300 border-emerald-400/35 bg-emerald-400/[0.08]"
    : lower.includes("route") ||
        lower.includes("en_route") ||
        lower.includes("checked")
      ? "text-sky-300 border-sky-400/35 bg-sky-400/[0.08]"
      : lower.includes("quality") ||
          lower.includes("approval") ||
          lower.includes("waiting")
        ? "text-amber-200 border-amber-300/35 bg-amber-300/[0.08]"
        : "text-gold-bright border-gold-dim/60 bg-gold/[0.07]";
  return (
    <span
      className={`font-mono text-[8px] md:text-[9px] uppercase tracking-[0.08em] px-2.5 py-1 rounded-full border ${tone}`}
    >
      {label}
    </span>
  );
}

export function LivePulse({ label }: { label: string }) {
  return (
    <span className="inline-flex items-center gap-1.5 text-[10px] font-mono uppercase text-emerald-300">
      <span className="relative flex h-2 w-2">
        <span className="animate-pulse-soft absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75" />
        <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-400 status-dot" />
      </span>
      {label}
    </span>
  );
}

export function Skeleton({ className = "" }: { className?: string }) {
  return <div className={`skeleton rounded-md ${className}`} />;
}

export function SectionHeader({
  title,
  action,
}: {
  title: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-3 mb-3">
      <div className="section-title">{title}</div>
      {action}
    </div>
  );
}

export function EmptyState({
  title,
  detail,
  action,
}: {
  title: string;
  detail?: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="premium-card rounded-xl p-7 text-center border-dashed">
      <div className="mx-auto mb-3 h-11 w-11 rounded-xl border border-gold-dim/40 bg-gold/[0.06] flex items-center justify-center text-gold">
        ◇
      </div>
      <div className="font-display font-semibold text-marine-white">
        {title}
      </div>
      {detail && (
        <p className="text-xs text-cool-gray mt-1.5 max-w-md mx-auto">
          {detail}
        </p>
      )}
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}
