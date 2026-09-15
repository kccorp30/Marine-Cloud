"use client";
import { useCommandCopy } from "@/components/ui/LocaleProvider";
import { ProgressMeter } from "@/components/ui/command";
import { RequestAssistanceButton } from "@/components/kcc-assistance/RequestAssistanceButton";
export function LuzWorkGuide({
  workOrderId,
  items,
  onEvidence,
  onNote,
}: {
  workOrderId: string;
  items: { id: string; label: string; completed: boolean }[];
  onEvidence: () => void;
  onNote: () => void;
}) {
  const { t, locale } = useCommandCopy();
  const missing = items.filter((i) => !i.completed);
  const completed = items.length - missing.length;
  return (
    <section className="command-panel p-5 border-gold/30">
      <div className="flex items-center gap-3">
        <span className="luz-orb" aria-hidden="true">
          ✦
        </span>
        <div>
          <p className="eyebrow text-gold">LUZ ASSIST</p>
          <h2 className="text-lg font-semibold">{t.next}</h2>
        </div>
      </div>
      {items.length > 0 && (
        <div className="my-5">
          <ProgressMeter
            label={t.progress}
            value={Math.round((completed / items.length) * 100)}
            tone="green"
          />
        </div>
      )}
      {missing.length > 0 ? (
        <ul className="my-4 space-y-2">
          {missing.slice(0, 3).map((i) => (
            <li key={i.id}>
              <button
                className="text-left text-sm text-amber-100 p-3 w-full rounded-lg bg-amber-300/5 border border-amber-300/20"
                onClick={() => {
                  const el = document.getElementById(`checklist-${i.id}`);
                  if (el) {
                    el.scrollIntoView({
                      behavior: matchMedia("(prefers-reduced-motion: reduce)")
                        .matches
                        ? "auto"
                        : "smooth",
                      block: "center",
                    });
                    el.focus();
                  }
                }}
              >
                {i.label} →
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p className="my-4 text-sm text-cool-gray">{t.notesHelp}</p>
      )}
      <div className="flex flex-wrap gap-2">
        <button className="command-button" onClick={onEvidence}>
          {t.evidence}
        </button>
        <button
          className="command-button command-button-secondary"
          onClick={onNote}
        >
          {t.notes}
        </button>
        <RequestAssistanceButton workOrderId={workOrderId} />
      </div>
      <p className="text-xs text-cool-gray mt-4">
        {locale === "es"
          ? "Los pendientes corresponden al checklist de esta orden."
          : "Pending items come from this work order’s checklist."}
      </p>
    </section>
  );
}
