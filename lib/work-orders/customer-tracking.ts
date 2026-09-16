import "server-only";
import { createClient } from "@/lib/supabase/server";
import {
  mapWorkOrderStatusToCustomerStage,
  buildStageStatuses,
  type CustomerStageStatus,
} from "./customer-stages";

// ---------------------------------------------------------
// DTO — deliberadamente NO es el work order interno completo. Cada
// campo acá es algo que un customer puede ver, ya resuelto a un tipo
// simple. Nunca se pasa un row crudo de Supabase a un client component.
// ---------------------------------------------------------
export interface CustomerTrackingTechnician {
  name: string;
  avatarUrl: string | null;
  role: string | null;
}

export interface CustomerTrackingAppointment {
  scheduledStart: string;
  scheduledEnd: string | null;
  status: string;
  locationLabel: string | null;
}

export interface CustomerTrackingProgressUpdate {
  id: string;
  body: string | null;
  createdAt: string;
  photoUrls: string[];
}

export interface CustomerWorkOrderTracking {
  workOrderId: string;
  title: string;
  currentStatus: string;
  recordedStages: { status: string; at: string }[];
  currentStageIndex: number; // -1 = cancelado, 0 = estado no mapeado todavía
  subStatus: string;
  isPaused: boolean;
  isCancelled: boolean;
  lastActivityAt: string | null;
  stages: ReturnType<typeof buildStageStatuses>[number][];
  technician: CustomerTrackingTechnician | null;
  appointment: CustomerTrackingAppointment | null;
  progressUpdates: CustomerTrackingProgressUpdate[];
}

// Server-only a propósito (import 'server-only' arriba) — esta
// función nunca debe poder importarse desde un client component por
// accidente. RLS ya garantiza que un customer solo puede leer SU
// propio work order (is_customer_of_work_order) — esta función no
// depende únicamente del frontend para eso, cada query de acá abajo
// pasa por las mismas policies ya probadas en Phase 1-3.
export async function getCustomerWorkOrderTracking(
  workOrderId: string,
): Promise<CustomerWorkOrderTracking | null> {
  const supabase = await createClient();

  const { data: wo } = await supabase
    .from("work_orders")
    .select("id, title, current_status, last_activity_at")
    .eq("id", workOrderId)
    .maybeSingle();

  if (!wo) return null; // RLS ya filtró — null acá significa "no autorizado o no existe", igual de seguro

  const history = await supabase
    .from("work_order_status_history")
    .select("to_status,occurred_at")
    .eq("work_order_id", workOrderId)
    .order("occurred_at", { ascending: true });
  const mapping = mapWorkOrderStatusToCustomerStage(wo.current_status);
  const stages = buildStageStatuses(mapping.stageIndex);

  // Técnico activo — vía función angosta que expone SOLO
  // full_name/avatar_url del técnico realmente asignado, nunca un
  // SELECT directo de profiles (ver migración 046 — un customer no
  // tiene acceso general a profiles, ni siquiera para leer estos dos
  // campos de cualquier técnico, solo del que está realmente
  // asignado a ESTE work order).
  const { data: technicianInfo } = await supabase.rpc(
    "get_assigned_technician_public_info",
    {
      p_work_order_id: workOrderId,
    },
  );

  const technician: CustomerTrackingTechnician | null = technicianInfo?.[0]
    ? {
        name: technicianInfo[0].full_name ?? "Assigned Technician",
        avatarUrl: technicianInfo[0].avatar_url ?? null,
        role: null, // no exponemos el rol interno (technician/manager/etc.) — dato operativo, no del customer
      }
    : null;

  // Cita más reciente — RLS ya limita esto al work order del customer.
  const { data: appt } = await supabase
    .from("appointments")
    .select("scheduled_start, scheduled_end, status")
    .eq("work_order_id", workOrderId)
    .order("scheduled_start", { ascending: false })
    .limit(1)
    .maybeSingle();

  const appointment: CustomerTrackingAppointment | null = appt
    ? {
        scheduledStart: appt.scheduled_start,
        scheduledEnd: appt.scheduled_end ?? null,
        status: appt.status,
        locationLabel: null, // ubicación exacta del vessel no se expone acá — fuera de alcance de Phase 3B
      }
    : null;

  // Progress updates — RLS de progress_updates ya exige
  // customer_visible = true O ser el customer dueño; igual filtramos
  // explícito acá para que la intención quede clara en el código, no
  // solo implícita en la policy.
  const { data: updates } = await supabase
    .from("progress_updates")
    .select(
      "id, body, created_at, customer_visible, progress_update_media(media_id)",
    )
    .eq("work_order_id", workOrderId)
    .eq("customer_visible", true)
    .order("created_at", { ascending: false })
    .limit(10);

  const mediaIds = (updates ?? []).flatMap((u: any) =>
    (u.progress_update_media ?? []).map((m: any) => m.media_id),
  );
  let mediaUrlById = new Map<string, string>();
  if (mediaIds.length > 0) {
    // Solo media explícitamente customer_visible — misma regla que ya
    // usa el resto de la app (RLS + este filtro explícito acá).
    const { data: mediaRows } = await supabase
      .from("media_assets")
      .select("id, storage_path, visibility")
      .in("id", mediaIds)
      .eq("visibility", "customer_visible");

    for (const m of mediaRows ?? []) {
      const { data: signed } = await supabase.storage
        .from("vessel-media")
        .createSignedUrl(m.storage_path, 3600);
      if (signed?.signedUrl) mediaUrlById.set(m.id, signed.signedUrl);
    }
  }

  const progressUpdates: CustomerTrackingProgressUpdate[] = (updates ?? []).map(
    (u: any) => ({
      id: u.id,
      body: u.body,
      createdAt: u.created_at,
      photoUrls: (u.progress_update_media ?? [])
        .map((m: any) => mediaUrlById.get(m.media_id))
        .filter((url: string | undefined): url is string => Boolean(url)),
    }),
  );

  return {
    workOrderId: wo.id,
    title: wo.title,
    currentStatus: wo.current_status,
    recordedStages: (history.data || []).map((e) => ({
      status: e.to_status,
      at: e.occurred_at,
    })),
    currentStageIndex: mapping.stageIndex,
    subStatus: mapping.subStatus,
    isPaused: mapping.isPaused,
    isCancelled: mapping.isCancelled,
    lastActivityAt: wo.last_activity_at,
    stages,
    technician,
    appointment,
    progressUpdates,
  };
}
