import { dictionary, type Locale } from "@/lib/i18n/dictionary";
import { commandCopy } from "@/lib/i18n/command-copy";
const journey = [
  "request_received",
  "triage",
  "estimate",
  "awaiting_approval",
  "scheduled",
  "technician_assigned",
  "en_route",
  "checked_in",
  "diagnosis",
  "work_in_progress",
  "waiting_parts",
  "waiting_customer_approval",
  "quality_control",
  "invoice",
  "payment",
  "completed",
  "warranty",
];
/** Show recorded events and the actual current state; do not infer completed stages. */
export function StatusTimeline({
  status,
  events = [],
  locale = "en",
}: {
  status: string;
  events?: { status: string; at: string }[];
  locale?: Locale;
}) {
  const copy = commandCopy[locale];
  const labels = dictionary[locale].status as Record<string, string>;
  const seen = events.filter(
    (e) => journey.includes(e.status) || e.status === "cancelled",
  );
  const steps = seen.length ? [...seen] : [{ status, at: "" }];
  if (steps[steps.length - 1]?.status !== status)
    steps.push({ status, at: "" });
  return (
    <ol className="status-timeline" aria-label={copy.service}>
      {steps.map((step, i) => (
        <li
          key={`${step.status}-${i}`}
          aria-current={i === steps.length - 1 ? "step" : undefined}
        >
          <span className="timeline-node" aria-hidden="true">
            {i === steps.length - 1 ? "◉" : "✓"}
          </span>
          <div>
            <p>{labels[step.status] || step.status.replaceAll("_", " ")}</p>
            {step.at ? (
              <time dateTime={step.at}>
                {new Date(step.at).toLocaleString(locale, {
                  month: "short",
                  day: "numeric",
                  hour: "2-digit",
                  minute: "2-digit",
                  timeZone: "UTC",
                })}{" "}
                UTC
              </time>
            ) : (
              <span>{copy.current}</span>
            )}
          </div>
        </li>
      ))}
    </ol>
  );
}
