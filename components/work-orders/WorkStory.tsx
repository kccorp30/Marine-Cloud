import type { WorkStoryEntry, WorkStoryKind } from "@/lib/work-orders/work-story";
import type { Locale } from "@/lib/i18n/dictionary";
import { dictionary } from "@/lib/i18n/dictionary";
import { workspaceCopy } from "@/lib/i18n/workspace-copy";
import { Card } from "@/components/ui/primitives";

// =========================================================
// WORK STORY — presentación del feed único
// =========================================================
// Este componente NO decide qué se ve: recibe las entradas que RLS ya
// autorizó para ese usuario. Un customer y un técnico renderizan el
// mismo componente; lo que cambia es lo que llegó, no la lógica de acá.
//
// Todo string visible sale de workspaceCopy / dictionary.status. Lo
// único que se imprime tal cual es texto escrito por una persona
// (nota, resumen de visita) o el nombre real del actor.
// =========================================================

// Un punto de color por tipo de suceso — señal operativa, no decoración:
// la llegada y el inicio de trabajo se distinguen de un timer interno.
const KIND_TONE: Record<WorkStoryKind, string> = {
  created: "bg-cool-gray",
  status: "bg-gold",
  assigned: "bg-blue-400",
  unassigned: "bg-cool-gray",
  en_route: "bg-gold",
  arrived: "bg-emerald-400",
  work_started: "bg-emerald-400",
  departed: "bg-cool-gray",
  note: "bg-cool-gray",
  progress: "bg-blue-400",
  media: "bg-blue-400",
  measurement: "bg-cool-gray",
  checklist: "bg-cool-gray",
  visit_finished: "bg-amber-400",
  appointment: "bg-blue-400",
  estimate: "bg-blue-400",
  approval: "bg-emerald-400",
  request: "bg-cool-gray",
  timer: "bg-cool-gray/60",
  other: "bg-cool-gray/60",
};

function copy(locale: Locale, key: string): string {
  const table = workspaceCopy[locale] as Record<string, string>;
  // Fallback a inglés y luego a la propia clave: una entrada real nunca
  // desaparece por una traducción faltante.
  return table[key] ?? (workspaceCopy.en as Record<string, string>)[key] ?? key;
}

export function WorkStory({
  entries,
  locale,
  title,
  limit,
}: {
  entries: WorkStoryEntry[];
  locale: Locale;
  title?: string;
  limit?: number;
}) {
  const t = workspaceCopy[locale] as Record<string, string>;
  const statusLabels = dictionary[locale].status as Record<string, string>;
  const shown = typeof limit === "number" ? entries.slice(0, limit) : entries;

  return (
    <Card>
      <div className="font-mono text-[10px] uppercase tracking-[0.15em] text-gold-dim mb-4">
        {title ?? copy(locale, "workStory.heading")}
      </div>
      {shown.length === 0 ? (
        <p className="text-xs text-cool-gray">{copy(locale, "workStory.empty")}</p>
      ) : (
        <ol className="relative pl-4 space-y-4">
          <span className="absolute left-0 top-1.5 bottom-1.5 w-px bg-gradient-to-b from-gold-dim via-white/10 to-transparent" />
          {shown.map((entry, i) => (
            <li
              key={entry.id}
              className="relative animate-fade-up"
              style={{ animationDelay: `${Math.min(i, 8) * 40}ms` }}
            >
              {i === 0 ? (
                <span className="absolute -left-[17px] top-1 flex h-2.5 w-2.5">
                  <span className="animate-pulse-soft absolute inline-flex h-full w-full rounded-full bg-gold opacity-60" />
                  <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-gold shadow-glow-gold" />
                </span>
              ) : (
                <span
                  className={`absolute -left-[15px] top-1.5 w-1.5 h-1.5 rounded-full ${KIND_TONE[entry.kind]}`}
                />
              )}

              <div className="flex items-baseline justify-between gap-2">
                <span className="text-sm font-medium text-marine-white">
                  {copy(locale, entry.titleKey)}
                  {entry.continuation && (
                    <span className="ml-2 rounded-full border border-gold/30 px-2 py-0.5 font-mono text-[9px] uppercase tracking-wider text-gold">
                      {copy(locale, "workStory.continuation")}
                    </span>
                  )}
                </span>
                <span className="font-mono text-[9px] text-cool-gray whitespace-nowrap">
                  {new Date(entry.occurredAt).toLocaleString(locale, {
                    month: "short",
                    day: "numeric",
                    hour: "2-digit",
                    minute: "2-digit",
                  })}
                </span>
              </div>

              {entry.statusTo && (
                <div className="text-xs text-gold/80 mt-0.5">
                  → {statusLabels[entry.statusTo] ?? entry.statusTo.replace(/_/g, " ")}
                </div>
              )}

              {entry.visitOutcome && (
                <div className="text-xs text-amber-300/90 mt-0.5">
                  {copy(locale, `workStory.outcome.${entry.visitOutcome}`)}
                </div>
              )}

              {entry.body && (
                <p className="text-xs text-cool-gray mt-1 leading-relaxed whitespace-pre-line">
                  {entry.body}
                </p>
              )}

              {entry.media.length > 0 && (
                <div className="flex gap-2 overflow-x-auto mt-2 pb-1">
                  {entry.media.map((m) => (
                    <a key={m.id} href={m.url} target="_blank" rel="noreferrer" className="shrink-0">
                      <img
                        src={m.url}
                        alt={m.caption ?? copy(locale, `workStory.category.${m.category}`)}
                        loading="lazy"
                        className="h-20 w-20 rounded-lg object-cover border border-white/10"
                      />
                      <span className="mt-1 block font-mono text-[8px] uppercase tracking-wider text-cool-gray">
                        {copy(locale, `workStory.category.${m.category}`)}
                      </span>
                    </a>
                  ))}
                </div>
              )}

              {entry.actorName && (
                <div className="text-[10px] text-cool-gray/70 mt-0.5">
                  {t["workStory.by"] ?? "by"} {entry.actorName}
                </div>
              )}
            </li>
          ))}
        </ol>
      )}
    </Card>
  );
}
