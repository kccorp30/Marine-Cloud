import { AnimatedNumber } from "./AnimatedNumber";
import Link from "next/link";

export function CommandPanel({
  children,
  className = "",
  glow = "blue",
}: {
  children: React.ReactNode;
  className?: string;
  glow?: "blue" | "gold" | "green" | "red" | "none";
}) {
  return (
    <div className={`command-panel command-glow-${glow} ${className}`}>
      {children}
    </div>
  );
}

export function MetricCard({
  label,
  value,
  detail,
  href,
  tone = "gold",
  icon = "•",
  progress,
}: {
  label: string;
  value: React.ReactNode;
  detail?: React.ReactNode;
  href?: string;
  tone?: "gold" | "blue" | "green" | "red";
  icon?: string;
  progress?: number;
}) {
  const body = (
    <div className={`metric-card metric-${tone}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="metric-icon">{icon}</div>
        {href && <span className="metric-arrow">↗</span>}
      </div>
      <div className="mt-5">
        <div className="section-title">{label}</div>
        <div className="metric-value">
          {typeof value === "number" ? <AnimatedNumber value={value} /> : value}
        </div>
        {detail && <div className="metric-detail">{detail}</div>}
      </div>
      {typeof progress === "number" && (
        <div className="metric-track">
          <span
            style={{
              ["--metric-progress" as any]: `${Math.max(0, Math.min(100, progress))}%`,
            }}
          />
        </div>
      )}
    </div>
  );
  return href ? (
    <Link href={href} className="block h-full">
      {body}
    </Link>
  ) : (
    body
  );
}

export function RadialGauge({
  value,
  label,
  sublabel,
  tone = "green",
  size = 112,
}: {
  value: number;
  label?: string;
  sublabel?: string;
  tone?: "green" | "gold" | "blue" | "orange";
  size?: number;
}) {
  const safe = Math.max(0, Math.min(100, value));
  const r = 42;
  const c = 2 * Math.PI * r;
  const dash = c * (safe / 100);
  return (
    <div className="radial-wrap">
      <div
        className={`radial radial-${tone}`}
        style={{ width: size, height: size }}
      >
        <svg viewBox="0 0 100 100" aria-hidden="true">
          <circle cx="50" cy="50" r={r} className="radial-bg" />
          <circle
            cx="50"
            cy="50"
            r={r}
            className="radial-fg"
            strokeDasharray={`${dash} ${c - dash}`}
          />
        </svg>
        <div className="radial-value">{safe}</div>
      </div>
      {label && (
        <div className="mt-2 text-sm font-semibold text-center">{label}</div>
      )}
      {sublabel && (
        <div className="mt-1 text-[10px] text-cool-gray text-center">
          {sublabel}
        </div>
      )}
    </div>
  );
}

export function ProgressMeter({
  value,
  tone = "blue",
  label,
}: {
  value: number;
  tone?: "blue" | "gold" | "green" | "red";
  label?: string;
}) {
  const safe = Math.max(0, Math.min(100, value));
  return (
    <div className="space-y-1.5">
      {label && (
        <div className="flex justify-between text-[10px] text-cool-gray">
          <span>{label}</span>
          <span>{safe}%</span>
        </div>
      )}
      <div
        className="progress-shell"
        role="progressbar"
        aria-label={label || "Progress"}
        aria-valuenow={safe}
        aria-valuemin={0}
        aria-valuemax={100}
      >
        <span
          className={`progress-fill progress-${tone}`}
          style={{ ["--progress" as any]: `${safe}%` }}
        />
      </div>
    </div>
  );
}

export function CommandSectionTitle({
  eyebrow,
  title,
  action,
}: {
  eyebrow?: string;
  title: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex items-end justify-between gap-4 mb-4">
      <div>
        {eyebrow && <div className="eyebrow mb-1">{eyebrow}</div>}
        <h2 className="font-display text-xl lg:text-2xl font-semibold tracking-[-.025em]">
          {title}
        </h2>
      </div>
      {action}
    </div>
  );
}
