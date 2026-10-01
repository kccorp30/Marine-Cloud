import "server-only";
import { createClient } from "@/lib/supabase/server";

// =========================================================
// WORK STORY — UN solo feed operativo normalizado
// =========================================================
// Brief item 4: "Do not build three unrelated timelines."
//
// Este módulo es la ÚNICA fuente del relato de un work order para los
// tres roles. No hay un feed para el técnico, otro para la compañía y
// otro para el customer: hay UNA query sobre domain_events, y el
// filtrado por rol lo hace la policy role_scoped_read_domain_events
// (migración 040), que ya distingue:
//
//   kcc_admin / org staff  → todo lo de su organización
//   técnico asignado       → todo lo de SU work order
//   customer dueño         → WORK_NOTE_ADDED solo si visibility='customer_visible'
//                            MEDIA_ADDED solo si visibility='customer_visible'
//                            PROGRESS_UPDATE_ADDED solo si customer_visible=true
//                            el resto según domain_event_visibility
//
// Es decir: la misma llamada a getWorkStory() devuelve exactamente lo
// que ese usuario puede ver, sin que este archivo decida nada. Nunca
// filtramos por rol en TypeScript — si lo hiciéramos, la seguridad
// dependería del frontend, y un bug acá se convertiría en una fuga.
// El enriquecimiento de abajo (media_assets, work_notes,
// progress_updates) vuelve a pasar por RLS, así que es defensa en
// profundidad, no una segunda puerta.
//
// Los títulos NO se escriben acá. Cada entrada devuelve un titleKey
// que el componente resuelve contra workspaceCopy (brief: "Do not
// hardcode visible strings outside i18n"). Lo único que viaja como
// texto libre es lo que un humano escribió de verdad (nota, resumen
// de visita) o datos reales (categoría de foto, estado destino).
// =========================================================

export type WorkStoryKind =
  | "created"
  | "status"
  | "assigned"
  | "unassigned"
  | "en_route"
  | "arrived"
  | "work_started"
  | "departed"
  | "note"
  | "progress"
  | "media"
  | "measurement"
  | "checklist"
  | "visit_finished"
  | "appointment"
  | "estimate"
  | "approval"
  | "request"
  | "timer"
  | "other";

export interface WorkStoryMedia {
  id: string;
  url: string;
  category: string;
  caption: string | null;
}

export interface WorkStoryEntry {
  id: string;
  kind: WorkStoryKind;
  /** Clave i18n en workspaceCopy (`workStory.*`). Nunca texto visible. */
  titleKey: string;
  /** Texto escrito por una persona real (nota, resumen de visita). Puede ser null. */
  body: string | null;
  /** Estado destino de una transición, sin traducir — el componente usa dictionary.status. */
  statusTo: string | null;
  /** Resultado de una visita multi-día (`continue_tomorrow`, `waiting_parts`, …). */
  visitOutcome: string | null;
  occurredAt: string;
  actorName: string | null;
  media: WorkStoryMedia[];
  /** true = ruta/llegada de una visita de continuación (Día 2+), no la primera. */
  continuation: boolean;
}

// event_type → (kind, titleKey). Un tipo de evento que no esté acá
// igual se muestra (kind 'other' + titleKey genérico): preferimos una
// entrada pobre a esconder algo que pasó de verdad.
const EVENT_MAP: Record<string, { kind: WorkStoryKind; titleKey: string }> = {
  WORK_ORDER_CREATED: { kind: "created", titleKey: "workStory.created" },
  WORK_ORDER_STATUS_CHANGED: { kind: "status", titleKey: "workStory.status" },
  TECHNICIAN_ASSIGNED: { kind: "assigned", titleKey: "workStory.assigned" },
  TECHNICIAN_UNASSIGNED: { kind: "unassigned", titleKey: "workStory.unassigned" },
  TECHNICIAN_EN_ROUTE: { kind: "en_route", titleKey: "workStory.enRoute" },
  TECHNICIAN_CHECKED_IN: { kind: "arrived", titleKey: "workStory.arrived" },
  TECHNICIAN_CHECKED_OUT: { kind: "departed", titleKey: "workStory.departed" },
  TECHNICIAN_WORK_STARTED: { kind: "work_started", titleKey: "workStory.workStarted" },
  VISIT_FINISHED: { kind: "visit_finished", titleKey: "workStory.visitFinished" },
  APPOINTMENT_CREATED: { kind: "appointment", titleKey: "workStory.visitScheduled" },
  APPOINTMENT_RESCHEDULED: { kind: "appointment", titleKey: "workStory.visitRescheduled" },
  WORK_NOTE_ADDED: { kind: "note", titleKey: "workStory.note" },
  PROGRESS_UPDATE_ADDED: { kind: "progress", titleKey: "workStory.progress" },
  MEDIA_ADDED: { kind: "media", titleKey: "workStory.media" },
  MEASUREMENT_RECORDED: { kind: "measurement", titleKey: "workStory.measurement" },
  CHECKLIST_UPDATED: { kind: "checklist", titleKey: "workStory.checklist" },
  TIME_ENTRY_STARTED: { kind: "timer", titleKey: "workStory.timerStarted" },
  TIME_ENTRY_STOPPED: { kind: "timer", titleKey: "workStory.timerStopped" },
  ESTIMATE_SENT: { kind: "estimate", titleKey: "workStory.estimateSent" },
  ESTIMATE_APPROVED: { kind: "approval", titleKey: "workStory.estimateApproved" },
  CUSTOMER_SERVICE_REQUEST_SUBMITTED: { kind: "request", titleKey: "workStory.requestSubmitted" },
  CUSTOMER_SERVICE_REQUEST_CANCELLED: { kind: "request", titleKey: "workStory.requestCancelled" },
  KCC_ASSISTANCE_REQUESTED: { kind: "other", titleKey: "workStory.assistanceRequested" },
};

const MEDIA_BUCKET = "vessel-media";
const SIGNED_URL_TTL_SECONDS = 3600;

export interface GetWorkStoryOptions {
  /** Máximo de entradas devueltas (las más recientes). */
  limit?: number;
  /** true = más reciente primero (feeds). false = cronológico (detalle). */
  newestFirst?: boolean;
}

export async function getWorkStory(
  workOrderId: string,
  options: GetWorkStoryOptions = {},
): Promise<WorkStoryEntry[]> {
  const { limit = 200, newestFirst = false } = options;
  const supabase = await createClient();

  // Única query del feed. RLS decide qué filas llegan.
  const { data: events } = await supabase
    .from("domain_events")
    .select("id, event_type, entity_type, entity_id, occurred_at, payload, actor:profiles(full_name)")
    .eq("work_order_id", workOrderId)
    .order("occurred_at", { ascending: false })
    .limit(limit);

  if (!events || events.length === 0) return [];

  // --- Enriquecimiento por lotes (nunca una query por evento) ---
  const idsFor = (type: string) =>
    events
      .filter((e: any) => e.event_type === type && e.entity_id)
      .map((e: any) => e.entity_id as string);

  const noteIds = idsFor("WORK_NOTE_ADDED");
  const progressIds = idsFor("PROGRESS_UPDATE_ADDED");
  const mediaIds = idsFor("MEDIA_ADDED");
  const visitApptIds = events
    .filter((e: any) => e.event_type === "VISIT_FINISHED")
    .map((e: any) => (e.payload?.appointment_id as string) ?? null)
    .filter((v: string | null): v is string => Boolean(v));

  const [noteRes, progressRes, mediaRes, apptRes] = await Promise.all([
    noteIds.length
      ? supabase.from("work_notes").select("id, body").in("id", noteIds)
      : Promise.resolve({ data: [] as any[] }),
    progressIds.length
      ? supabase
          .from("progress_updates")
          .select("id, body, progress_update_media(media_id)")
          .in("id", progressIds)
      : Promise.resolve({ data: [] as any[] }),
    mediaIds.length
      ? supabase
          .from("media_assets")
          .select("id, category, storage_path, caption")
          .in("id", mediaIds)
          .is("deleted_at", null)
      : Promise.resolve({ data: [] as any[] }),
    visitApptIds.length
      ? supabase.from("appointments").select("id, visit_summary, visit_outcome").in("id", visitApptIds)
      : Promise.resolve({ data: [] as any[] }),
  ]);

  const noteBodyById = new Map<string, string | null>(
    (noteRes.data ?? []).map((n: any) => [n.id, n.body ?? null]),
  );
  const progressById = new Map<string, { body: string | null; mediaIds: string[] }>(
    (progressRes.data ?? []).map((p: any) => [
      p.id,
      { body: p.body ?? null, mediaIds: (p.progress_update_media ?? []).map((m: any) => m.media_id) },
    ]),
  );
  const apptById = new Map<string, { summary: string | null; outcome: string | null }>(
    (apptRes.data ?? []).map((a: any) => [
      a.id,
      { summary: a.visit_summary ?? null, outcome: a.visit_outcome ?? null },
    ]),
  );

  // Las fotos de un progress update también deben poder mostrarse en su
  // entrada, aunque el evento MEDIA_ADDED correspondiente no sea visible
  // por separado — por eso se piden acá y vuelven a pasar por RLS.
  const progressMediaIds = [...progressById.values()].flatMap((p) => p.mediaIds);
  const extraMediaIds = progressMediaIds.filter((id) => !mediaIds.includes(id));
  const { data: extraMedia } = extraMediaIds.length
    ? await supabase
        .from("media_assets")
        .select("id, category, storage_path, caption")
        .in("id", extraMediaIds)
        .is("deleted_at", null)
    : { data: [] as any[] };

  const allMediaRows = [...(mediaRes.data ?? []), ...(extraMedia ?? [])];

  // Un solo round trip para firmar todas las URLs, no una por foto.
  const signedByPath = new Map<string, string>();
  if (allMediaRows.length > 0) {
    const paths = [...new Set(allMediaRows.map((m: any) => m.storage_path))];
    const { data: signed } = await supabase.storage
      .from(MEDIA_BUCKET)
      .createSignedUrls(paths, SIGNED_URL_TTL_SECONDS);
    for (const s of signed ?? []) {
      if (s.signedUrl && s.path) signedByPath.set(s.path, s.signedUrl);
    }
  }

  const mediaById = new Map<string, WorkStoryMedia>();
  for (const m of allMediaRows as any[]) {
    const url = signedByPath.get(m.storage_path);
    if (!url) continue; // sin URL firmada no se inventa nada, la entrada va sin foto
    mediaById.set(m.id, { id: m.id, url, category: m.category, caption: m.caption ?? null });
  }

  // --- Normalización ---
  const entries: WorkStoryEntry[] = events.map((e: any) => {
    const mapped = EVENT_MAP[e.event_type] ?? { kind: "other" as WorkStoryKind, titleKey: "workStory.event" };
    const payload = (e.payload ?? {}) as Record<string, unknown>;

    let body: string | null = null;
    let media: WorkStoryMedia[] = [];
    let visitOutcome: string | null = null;

    switch (e.event_type) {
      case "WORK_NOTE_ADDED":
        body = noteBodyById.get(e.entity_id) ?? null;
        break;
      case "PROGRESS_UPDATE_ADDED": {
        const p = progressById.get(e.entity_id);
        body = p?.body ?? null;
        media = (p?.mediaIds ?? [])
          .map((id) => mediaById.get(id))
          .filter((m): m is WorkStoryMedia => Boolean(m));
        break;
      }
      case "MEDIA_ADDED": {
        const m = mediaById.get(e.entity_id);
        if (m) media = [m];
        break;
      }
      case "VISIT_FINISHED": {
        const apptId = payload.appointment_id as string | undefined;
        const appt = apptId ? apptById.get(apptId) : undefined;
        body = appt?.summary ?? null;
        visitOutcome = (payload.outcome as string | undefined) ?? appt?.outcome ?? null;
        break;
      }
      case "MEASUREMENT_RECORDED":
        body = payload.label ? `${payload.label}: ${payload.value ?? ""} ${payload.unit ?? ""}`.trim() : null;
        break;
    }

    return {
      id: e.id,
      kind: mapped.kind,
      titleKey: mapped.titleKey,
      body,
      statusTo: (payload.to_status as string | undefined) ?? null,
      visitOutcome,
      occurredAt: e.occurred_at,
      actorName: e.actor?.full_name ?? null,
      media,
      continuation: payload.continuation === true,
    };
  });

  return newestFirst ? entries : entries.reverse();
}
