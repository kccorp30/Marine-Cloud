import "server-only";
import { createClient } from "@/lib/supabase/server";
import { isToday } from "./day-plan";
export interface DayJob {
  id: string;
  title: string;
  status: string;
  vessel: string;
  appointmentId: string | null;
  scheduledStart: string | null;
}
export async function getTechnicianDay(userId: string, organizationId: string) {
  const db = await createClient();
  const settings = await db
    .from("organization_settings")
    .select("timezone")
    .eq("organization_id", organizationId)
    .single();
  if (settings.error) throw new Error("Could not load workspace timezone");
  const timeZone = settings.data.timezone;
  const response = await db
    .from("assignments")
    .select(
      "work_order:work_orders(id,title,current_status,vessel:vessels(name)),appointment:appointments(id,scheduled_start,status)",
    )
    .eq("technician_profile_id", userId)
    .eq("organization_id", organizationId)
    .eq("status", "active");
  if (response.error) throw new Error("Could not load assignments");
  const jobs: DayJob[] = (response.data || []).flatMap((row: any) => {
    const wo = Array.isArray(row.work_order)
      ? row.work_order[0]
      : row.work_order;
    const appt = Array.isArray(row.appointment)
      ? row.appointment[0]
      : row.appointment;
    if (
      !wo ||
      ["completed", "cancelled", "warranty"].includes(wo.current_status)
    )
      return [];
    return [
      {
        id: wo.id,
        title: wo.title,
        status: wo.current_status,
        vessel: wo.vessel?.name || "",
        appointmentId: appt?.id || null,
        scheduledStart:
          appt?.status === "cancelled" ? null : appt?.scheduled_start || null,
      },
    ];
  });
  const unique = Array.from(
    new Map(jobs.map((j) => [`${j.id}:${j.appointmentId || ""}`, j])).values(),
  ).sort((a, b) =>
    (a.scheduledStart || "z").localeCompare(b.scheduledStart || "z"),
  );
  return {
    jobs: unique,
    today: unique.filter((j) => isToday(j.scheduledStart, timeZone)),
    timeZone,
  };
}
