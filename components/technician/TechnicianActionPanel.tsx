"use client";
import { UiText } from "@/components/ui/UiText";

import { LuzWorkGuide } from "@/components/luz/LuzWorkGuide";
import { useState, useTransition, useEffect } from "react";
import {
  startRoute,
  checkIn,
  checkOut,
  startTimer,
  stopTimer,
  addWorkNote,
  addMeasurement,
  addProgressUpdate,
  submitChecklistResponse,
  initiateMediaUpload,
  confirmMediaUpload,
} from "@/lib/technician/actions";
import { enqueue } from "@/lib/offline/queue";
import {
  ALLOWED_MEDIA_MIME_TYPES,
  MAX_MEDIA_SIZE_BYTES,
} from "@/lib/technician/media-validation";
import { attemptOnlinePhotoUpload } from "@/lib/technician/photo-upload";
import { transitionWorkOrder } from '@/lib/work-orders/actions';

interface Props {
  workOrderId: string;
  vesselId: string;
  appointmentId: string | null;
  currentStatus: string;
  activeCheckInId: string | null;
  activeTimeEntryId: string | null;
  checklistItems: {
    id: string;
    label: string;
    response_type: string;
    completed: boolean;
  }[];
}

type Panel = null | "note" | "measurement" | "progress" | "photo";

export function TechnicianActionPanel({
  workOrderId,
  vesselId,
  appointmentId,
  currentStatus,
  activeCheckInId,
  activeTimeEntryId,
  checklistItems,
}: Props) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [openPanel, setOpenPanel] = useState<Panel>(null);
  const [isOnline, setIsOnline] = useState(true);

  useEffect(() => {
    if (window.location.hash === "#evidence") setOpenPanel("photo");
    setIsOnline(navigator.onLine);
    const goOnline = () => setIsOnline(true);
    const goOffline = () => setIsOnline(false);
    window.addEventListener("online", goOnline);
    window.addEventListener("offline", goOffline);
    return () => {
      window.removeEventListener("online", goOnline);
      window.removeEventListener("offline", goOffline);
    };
  }, []);

  function run(
    fn: () => Promise<{ error?: string; success?: boolean } | void>,
  ) {
    setError(null);
    startTransition(async () => {
      const result = await fn();
      if (result && "error" in result && result.error) setError(result.error);
    });
  }

  return (
    <div id="technician-actions" className="space-y-4 scroll-mt-24">
      {!isOnline && (
        <div className="bg-amber-500/10 border border-amber-500/30 rounded-sm px-3 py-2 text-xs text-amber-300">
          {" "}
          <UiText text="Offline — documentation queues locally. Connection required to change job status." />{" "}
        </div>
      )}
      {error && (
        <div
          className="bg-red-500/10 border border-red-500/30 rounded-sm px-3 py-2 text-xs text-red-300"
          role="alert"
        >
          {error}
        </div>
      )}

      <LuzWorkGuide
        workOrderId={workOrderId}
        items={checklistItems}
        onEvidence={() => setOpenPanel("photo")}
        onNote={() => setOpenPanel("note")}
      />
      <div className="grid grid-cols-1 gap-2">
        {currentStatus === "technician_assigned" && (
          <BigButton
            disabled={isPending || !isOnline}
            onClick={() => run(() => startRoute(workOrderId))}
          >
            {" "}
            <UiText text="START ROUTE" />{" "}
          </BigButton>
        )}

        {currentStatus === "en_route" && appointmentId && (
          <BigButton
            disabled={isPending || !isOnline}
            onClick={() => run(() => checkIn(appointmentId, workOrderId))}
          >
            {" "}
            <UiText text="CHECK IN" />{" "}
          </BigButton>
        )}

        {currentStatus === "checked_in" && (
          <BigButton disabled={isPending || !isOnline} onClick={() => run(() => transitionWorkOrder(workOrderId, "diagnosis", "Technician started diagnostic"))}>
            <UiText text="START DIAGNOSTIC" />
          </BigButton>
        )}
        {currentStatus === "diagnosis" && (
          <BigButton disabled={isPending || !isOnline} onClick={() => run(() => transitionWorkOrder(workOrderId, "work_in_progress", "Diagnostic complete — work started"))}>
            <UiText text="START WORK" />
          </BigButton>
        )}
        {currentStatus === "work_in_progress" && (
          <>
            <BigButton disabled={isPending || !isOnline} onClick={() => run(() => transitionWorkOrder(workOrderId, "quality_control", "Technician submitted work for QC"))}>
              <UiText text="SEND TO QC" />
            </BigButton>
            <BigButton tone="secondary" disabled={isPending || !isOnline} onClick={() => run(() => transitionWorkOrder(workOrderId, "waiting_parts", "Waiting for parts"))}>
              <UiText text="WAITING FOR PARTS" />
            </BigButton>
          </>
        )}
        {currentStatus === "waiting_parts" && (
          <BigButton disabled={isPending || !isOnline} onClick={() => run(() => transitionWorkOrder(workOrderId, "work_in_progress", "Parts available — work resumed"))}>
            <UiText text="RESUME WORK" />
          </BigButton>
        )}

        {activeCheckInId &&
          currentStatus !== "quality_control" &&
          currentStatus !== "completed" && (
            <BigButton
              tone="secondary"
              disabled={isPending || !isOnline}
              onClick={() => run(() => checkOut(activeCheckInId, workOrderId))}
            >
              {" "}
              <UiText text="CHECK OUT" />{" "}
            </BigButton>
          )}
      </div>

      <div className="bg-white/[0.03] border border-white/10 rounded-sm p-3">
        <div className="flex items-center justify-between">
          <span className="font-mono text-[10px] uppercase tracking-[0.08em] text-cool-gray">
            {activeTimeEntryId ? "Timer running" : "Timer stopped"}
          </span>
          {activeTimeEntryId ? (
            <button
              disabled={isPending || !isOnline}
              onClick={() =>
                run(() => stopTimer(activeTimeEntryId, workOrderId))
              }
              className="text-[11px] uppercase tracking-[0.08em] text-red-400 border border-red-400/40 px-3 py-1.5 rounded-sm disabled:opacity-40"
            >
              {" "}
              <UiText text="Stop" />{" "}
            </button>
          ) : (
            <button
              disabled={isPending || !isOnline}
              onClick={() =>
                run(() =>
                  startTimer(workOrderId, appointmentId, crypto.randomUUID()),
                )
              }
              className="text-[11px] uppercase tracking-[0.08em] text-gold border border-gold-dim px-3 py-1.5 rounded-sm disabled:opacity-40"
            >
              {" "}
              <UiText text="Start" />{" "}
            </button>
          )}
        </div>
        {/* Política explícita (item 4): el timer afecta horas/nómina —
            requiere conexión real, nunca se encola offline. La
            documentación de campo sigue funcionando sin señal. */}
        {!isOnline && (
          <p className="text-[10px] text-amber-300/80 mt-1.5">
            {" "}
            <UiText text="Connection required to change timer status." />{" "}
          </p>
        )}
      </div>

      <div className="grid grid-cols-2 gap-2">
        <QuickAction label="ADD PHOTO" onClick={() => setOpenPanel("photo")} />
        <QuickAction label="ADD NOTE" onClick={() => setOpenPanel("note")} />
        <QuickAction
          label="MEASUREMENT"
          onClick={() => setOpenPanel("measurement")}
        />
        <QuickAction
          label="PROGRESS UPDATE"
          onClick={() => setOpenPanel("progress")}
        />
      </div>

      {openPanel === "photo" && (
        <PhotoPanel
          workOrderId={workOrderId}
          vesselId={vesselId}
          appointmentId={appointmentId}
          onClose={() => setOpenPanel(null)}
          isOnline={isOnline}
        />
      )}
      {openPanel === "note" && (
        <NotePanel
          workOrderId={workOrderId}
          appointmentId={appointmentId}
          onClose={() => setOpenPanel(null)}
          isOnline={isOnline}
        />
      )}
      {openPanel === "measurement" && (
        <MeasurementPanel
          workOrderId={workOrderId}
          vesselId={vesselId}
          appointmentId={appointmentId}
          onClose={() => setOpenPanel(null)}
          isOnline={isOnline}
        />
      )}
      {openPanel === "progress" && (
        <ProgressPanel
          workOrderId={workOrderId}
          appointmentId={appointmentId}
          onClose={() => setOpenPanel(null)}
          isOnline={isOnline}
        />
      )}

      {checklistItems.length > 0 && (
        <ChecklistPanel
          workOrderId={workOrderId}
          appointmentId={appointmentId}
          items={checklistItems}
          isOnline={isOnline}
        />
      )}
    </div>
  );
}

function BigButton({
  children,
  onClick,
  disabled,
  tone = "primary",
}: {
  children: React.ReactNode;
  onClick: () => void;
  disabled?: boolean;
  tone?: "primary" | "secondary";
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={
        tone === "primary"
          ? "w-full py-4 rounded-md font-bold text-sm uppercase tracking-[0.08em] bg-gradient-to-r from-gold to-silver text-navy disabled:opacity-40"
          : "w-full py-4 rounded-md font-bold text-sm uppercase tracking-[0.08em] border border-white/20 text-marine-white disabled:opacity-40"
      }
    >
      {children}
    </button>
  );
}

function QuickAction({
  label,
  onClick,
}: {
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="py-5 rounded-md border border-white/10 bg-white/[0.03] text-[11px] font-bold uppercase tracking-[0.06em] text-marine-white active:bg-white/[0.08]"
    >
      {label}
    </button>
  );
}

function PhotoPanel({
  workOrderId,
  vesselId,
  appointmentId,
  onClose,
  isOnline,
}: {
  workOrderId: string;
  vesselId: string;
  appointmentId: string | null;
  onClose: () => void;
  isOnline: boolean;
}) {
  const [category, setCategory] = useState("before");
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [capturedAt, setCapturedAt] = useState<string | null>(null);
  const [caption, setCaption] = useState("");
  // Un solo id por operación lógica de foto — generado UNA vez, en el
  // momento en que se elige el archivo, y reusado en TODOS los
  // caminos posteriores (upload online, confirmMediaUpload, y
  // cualquier encolado por falla, sea online→falla u offline desde
  // el inicio). Antes, queueLocally() generaba un id nuevo cada vez
  // que se llamaba — eso rompía la garantía de reintento
  // determinístico: un mismo archivo podía terminar con dos ids
  // distintos, dos paths de Storage distintos, y un objeto huérfano.
  const [clientGeneratedId, setClientGeneratedId] = useState<string | null>(
    null,
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function handleFile(f: File | null) {
    setFile(f);
    setPreview(f ? URL.createObjectURL(f) : null);
    // capturedAt = el momento en que el técnico eligió/sacó la foto,
    // NO cuando eventualmente se sincroniza (item 6 del brief).
    setCapturedAt(f ? new Date().toISOString() : null);
    // La identidad de la operación se fija ACÁ, una sola vez por
    // archivo elegido — no en handleSave, no en queueLocally.
    setClientGeneratedId(f ? crypto.randomUUID() : null);
  }

  async function queueLocally(id: string): Promise<boolean> {
    if (!file || !capturedAt) return false;
    const result = await enqueue({
      id,
      type: "photo",
      workOrderId,
      blob: file,
      payload: {
        vesselId,
        appointmentId,
        category,
        mimeType: file.type,
        sizeBytes: file.size,
        caption: caption.trim() || undefined,
        visibility: "internal",
        capturedAt,
      },
    });
    // Nunca decir "quedó en la cola" sin haberlo confirmado de verdad
    // (item 2 del brief) — si guardar localmente también falla, se
    // lo decimos claro al técnico.
    if ("error" in result) {
      setError(result.error);
      return false;
    }
    return true;
  }

  async function handleSave() {
    if (!file || !capturedAt || !clientGeneratedId) return;

    if (!ALLOWED_MEDIA_MIME_TYPES.includes(file.type)) {
      setError("Unsupported file type.");
      return;
    }
    if (file.size > MAX_MEDIA_SIZE_BYTES) {
      setError("File exceeds the 25MB limit.");
      return;
    }

    setSaving(true);
    setError(null);

    if (!isOnline) {
      const queued = await queueLocally(clientGeneratedId);
      setSaving(false);
      if (queued) onClose();
      return;
    }

    const { createClient } = await import("@/lib/supabase/client");
    const supabase = createClient();

    const result = await attemptOnlinePhotoUpload(
      {
        workOrderId,
        vesselId,
        appointmentId,
        category,
        file,
        mimeType: file.type,
        sizeBytes: file.size,
        caption: caption.trim() || undefined,
        capturedAt,
        clientGeneratedId,
      },
      {
        initiateMediaUpload: async (wo, cat, mime, id) => {
          const r = await initiateMediaUpload(wo, cat, mime, id);
          if ("error" in r && r.error) return { error: r.error };
          if (!("path" in r) || !r.path || !r.token)
            return { error: "Could not prepare upload." };
          return {
            success: true,
            path: r.path,
            token: r.token,
            vesselId: r.vesselId,
          };
        },
        confirmMediaUpload,
        uploadToSignedUrl: (path, token, f) =>
          supabase.storage
            .from("vessel-media")
            .uploadToSignedUrl(path, token, f),
        queueLocally,
      },
    );

    setSaving(false);
    if (result.outcome === "confirmed") {
      onClose();
    } else if (result.outcome === "queued") {
      setError(result.reason);
      setTimeout(onClose, 1200);
    } else {
      setError(result.error);
    }
  }

  return (
    <div className="bg-white/[0.04] border border-white/10 rounded-md p-4 space-y-3">
      <div className="flex gap-2 flex-wrap">
        {["before", "diagnosis", "progress", "after", "part", "damage"].map(
          (c) => (
            <button
              key={c}
              onClick={() => setCategory(c)}
              className={`text-[10px] uppercase tracking-[0.06em] px-2.5 py-1.5 rounded-sm border ${
                category === c
                  ? "bg-gold text-navy border-gold"
                  : "border-white/15 text-cool-gray"
              }`}
            >
              {c}
            </button>
          ),
        )}
      </div>

      {preview ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={preview}
          alt="Preview"
          className="w-full rounded-sm max-h-56 object-cover"
        />
      ) : (
        <label className="block border-2 border-dashed border-white/15 rounded-sm py-8 text-center cursor-pointer">
          <input
            type="file"
            accept="image/*"
            capture="environment"
            className="hidden"
            onChange={(e) => handleFile(e.target.files?.[0] ?? null)}
          />
          <span className="text-xs text-cool-gray">
            {" "}
            <UiText text="Tap to open camera" />{" "}
          </span>
        </label>
      )}

      {file && (
        <input
          value={caption}
          onChange={(e) => setCaption(e.target.value)}
          placeholder="Caption (optional)"
          className="w-full bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2 text-xs"
        />
      )}

      {error && <p className="text-xs text-amber-300">{error}</p>}

      <div className="flex gap-2">
        <button
          onClick={onClose}
          className="flex-1 py-2.5 text-xs uppercase text-cool-gray border border-white/10 rounded-sm"
        >
          {" "}
          <UiText text="Cancel" />{" "}
        </button>
        <button
          onClick={handleSave}
          disabled={!file || saving}
          className="flex-1 py-2.5 text-xs uppercase font-bold text-navy bg-gold rounded-sm disabled:opacity-40"
        >
          {saving ? "Saving…" : "Save Photo"}
        </button>
      </div>
    </div>
  );
}

function NotePanel({
  workOrderId,
  appointmentId,
  onClose,
  isOnline,
}: {
  workOrderId: string;
  appointmentId: string | null;
  onClose: () => void;
  isOnline: boolean;
}) {
  const [body, setBody] = useState("");
  const [noteType, setNoteType] = useState<
    "general" | "diagnostic" | "progress"
  >("diagnostic");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSave() {
    if (!body.trim()) return;
    setSaving(true);
    setError(null);
    const clientGeneratedId = crypto.randomUUID();

    if (!isOnline) {
      const result = await enqueue({
        id: clientGeneratedId,
        type: "note",
        workOrderId,
        payload: { body, noteType, appointmentId },
      });
      setSaving(false);
      // Nunca cerrar como si hubiera guardado sin confirmar que
      // IndexedDB realmente lo persistió (item 2 del brief).
      if ("error" in result) {
        setError(result.error);
        return;
      }
      onClose();
      return;
    }

    const result = await addWorkNote({
      workOrderId,
      appointmentId,
      body,
      noteType,
      visibility: "internal",
      clientGeneratedId,
    });
    setSaving(false);
    if (result && "error" in result && result.error) {
      setError(result.error);
      return;
    }
    onClose();
  }

  return (
    <div className="bg-white/[0.04] border border-white/10 rounded-md p-4 space-y-3">
      <div className="flex gap-2">
        {(["diagnostic", "progress", "general"] as const).map((t) => (
          <button
            key={t}
            onClick={() => setNoteType(t)}
            className={`text-[10px] uppercase px-2.5 py-1.5 rounded-sm border ${noteType === t ? "bg-gold text-navy border-gold" : "border-white/15 text-cool-gray"}`}
          >
            {t}
          </button>
        ))}
      </div>
      <textarea
        value={body}
        onChange={(e) => setBody(e.target.value)}
        rows={4}
        placeholder="What did you find or do?"
        className="w-full bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2.5 text-sm"
      />
      {error && <p className="text-xs text-amber-300">{error}</p>}
      <div className="flex gap-2">
        <button
          onClick={onClose}
          className="flex-1 py-2.5 text-xs uppercase text-cool-gray border border-white/10 rounded-sm"
        >
          {" "}
          <UiText text="Cancel" />{" "}
        </button>
        <button
          onClick={handleSave}
          disabled={saving || !body.trim()}
          className="flex-1 py-2.5 text-xs uppercase font-bold text-navy bg-gold rounded-sm disabled:opacity-40"
        >
          {saving ? "Saving…" : "Save Note"}
        </button>
      </div>
    </div>
  );
}

function MeasurementPanel({
  workOrderId,
  vesselId,
  appointmentId,
  onClose,
  isOnline,
}: {
  workOrderId: string;
  vesselId: string;
  appointmentId: string | null;
  onClose: () => void;
  isOnline: boolean;
}) {
  const [label, setLabel] = useState("");
  const [value, setValue] = useState("");
  const [unit, setUnit] = useState("V");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSave() {
    if (!value || !label.trim()) return;
    setSaving(true);
    setError(null);
    const clientGeneratedId = crypto.randomUUID();

    if (!isOnline) {
      const result = await enqueue({
        id: clientGeneratedId,
        type: "measurement",
        workOrderId,
        payload: {
          vesselId,
          appointmentId,
          measurementType: "reading",
          value: Number(value),
          unit,
          label,
        },
      });
      setSaving(false);
      if ("error" in result) {
        setError(result.error);
        return;
      }
      onClose();
      return;
    }

    const result = await addMeasurement({
      workOrderId,
      vesselId,
      appointmentId,
      measurementType: "reading",
      value: Number(value),
      unit,
      label,
      clientGeneratedId,
    });
    setSaving(false);
    if (result && "error" in result && result.error) {
      setError(result.error);
      return;
    }
    onClose();
  }

  return (
    <div className="bg-white/[0.04] border border-white/10 rounded-md p-4 space-y-3">
      <input
        value={label}
        onChange={(e) => setLabel(e.target.value)}
        placeholder="e.g. Battery Bank #2"
        className="w-full bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2.5 text-sm"
      />
      <div className="flex gap-2">
        <input
          type="number"
          inputMode="decimal"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          placeholder="12.42"
          className="flex-1 bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2.5 text-sm"
        />
        <select
          value={unit}
          onChange={(e) => setUnit(e.target.value)}
          className="bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2.5 text-sm"
        >
          <option value="V" className="bg-navy">
            V
          </option>
          <option value="A" className="bg-navy">
            A
          </option>
          <option value="°F" className="bg-navy">
            °F
          </option>
          <option value="psi" className="bg-navy">
            psi
          </option>
          <option value="Ω" className="bg-navy">
            Ω
          </option>
        </select>
      </div>
      {error && <p className="text-xs text-amber-300">{error}</p>}
      <div className="flex gap-2">
        <button
          onClick={onClose}
          className="flex-1 py-2.5 text-xs uppercase text-cool-gray border border-white/10 rounded-sm"
        >
          {" "}
          <UiText text="Cancel" />{" "}
        </button>
        <button
          onClick={handleSave}
          disabled={saving || !value || !label.trim()}
          className="flex-1 py-2.5 text-xs uppercase font-bold text-navy bg-gold rounded-sm disabled:opacity-40"
        >
          {saving ? "Saving…" : "Save Measurement"}
        </button>
      </div>
    </div>
  );
}

function ProgressPanel({
  workOrderId,
  appointmentId,
  onClose,
  isOnline,
}: {
  workOrderId: string;
  appointmentId: string | null;
  onClose: () => void;
  isOnline: boolean;
}) {
  const [body, setBody] = useState("");
  const [customerVisible, setCustomerVisible] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSave() {
    if (!body.trim()) return;
    setSaving(true);
    setError(null);
    const clientGeneratedId = crypto.randomUUID();

    if (!isOnline) {
      const result = await enqueue({
        id: clientGeneratedId,
        type: "progress_update",
        workOrderId,
        payload: { body, customerVisible, appointmentId },
      });
      setSaving(false);
      if ("error" in result) {
        setError(result.error);
        return;
      }
      onClose();
      return;
    }

    const result = await addProgressUpdate({
      workOrderId,
      appointmentId,
      body,
      customerVisible,
      clientGeneratedId,
    });
    setSaving(false);
    if (result && "error" in result && result.error) {
      setError(result.error);
      return;
    }
    onClose();
  }

  return (
    <div className="bg-white/[0.04] border border-white/10 rounded-md p-4 space-y-3">
      <textarea
        value={body}
        onChange={(e) => setBody(e.target.value)}
        rows={3}
        placeholder="Progress update…"
        className="w-full bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2.5 text-sm"
      />
      <label className="flex items-center gap-2 text-xs text-cool-gray">
        <input
          type="checkbox"
          checked={customerVisible}
          onChange={(e) => setCustomerVisible(e.target.checked)}
        />{" "}
        <UiText text="Visible to customer" />{" "}
      </label>
      {error && <p className="text-xs text-amber-300">{error}</p>}
      <div className="flex gap-2">
        <button
          onClick={onClose}
          className="flex-1 py-2.5 text-xs uppercase text-cool-gray border border-white/10 rounded-sm"
        >
          {" "}
          <UiText text="Cancel" />{" "}
        </button>
        <button
          onClick={handleSave}
          disabled={saving || !body.trim()}
          className="flex-1 py-2.5 text-xs uppercase font-bold text-navy bg-gold rounded-sm disabled:opacity-40"
        >
          {saving ? "Saving…" : "Save Update"}
        </button>
      </div>
    </div>
  );
}

function ChecklistPanel({
  workOrderId,
  appointmentId,
  items,
  isOnline,
}: {
  workOrderId: string;
  appointmentId: string | null;
  items: {
    id: string;
    label: string;
    response_type: string;
    completed: boolean;
  }[];
  isOnline: boolean;
}) {
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function respond(itemId: string, value: Record<string, unknown>) {
    setPending(itemId);
    setError(null);

    if (!isOnline) {
      const result = await enqueue({
        id: crypto.randomUUID(),
        type: "checklist_response",
        workOrderId,
        payload: {
          appointmentId,
          templateItemId: itemId,
          responseValue: value,
        },
      });
      if ("error" in result) setError(result.error);
      setPending(null);
      return;
    }

    const result = await submitChecklistResponse({
      workOrderId,
      appointmentId,
      templateItemId: itemId,
      responseValue: value,
      clientGeneratedId: crypto.randomUUID(),
    });
    if (result && "error" in result && result.error) {
      // Falla online real — se encola igual, no se pierde la respuesta.
      const queued = await enqueue({
        id: crypto.randomUUID(),
        type: "checklist_response",
        workOrderId,
        payload: {
          appointmentId,
          templateItemId: itemId,
          responseValue: value,
        },
      });
      setError(
        "error" in queued
          ? queued.error
          : "Saved offline — will sync automatically.",
      );
    }
    setPending(null);
  }

  return (
    <div className="bg-white/[0.03] border border-white/10 rounded-sm p-4">
      <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">
        {" "}
        <UiText text="Checklist" />{" "}
      </div>
      {error && <p className="text-xs text-amber-300 mb-2">{error}</p>}
      <ul className="space-y-2">
        {items.map((item) => (
          <li
            key={item.id}
            id={`checklist-${item.id}`}
            tabIndex={-1}
            className="flex items-center justify-between text-sm"
          >
            <span
              className={item.completed ? "text-cool-gray line-through" : ""}
            >
              {item.label}
            </span>
            {item.response_type === "pass_fail" ? (
              <div className="flex gap-1.5">
                <button
                  disabled={pending === item.id}
                  onClick={() => respond(item.id, { result: "pass" })}
                  className="text-[10px] uppercase px-2 py-1 rounded-sm border border-white/15 text-marine-white"
                >
                  {" "}
                  <UiText text="Pass" />{" "}
                </button>
                <button
                  disabled={pending === item.id}
                  onClick={() => respond(item.id, { result: "fail" })}
                  className="text-[10px] uppercase px-2 py-1 rounded-sm border border-red-400/40 text-red-400"
                >
                  {" "}
                  <UiText text="Fail" />{" "}
                </button>
              </div>
            ) : (
              <button
                disabled={pending === item.id}
                onClick={() => respond(item.id, { checked: !item.completed })}
                className={`text-[10px] uppercase px-2 py-1 rounded-sm border ${item.completed ? "bg-gold text-navy border-gold" : "border-white/15 text-cool-gray"}`}
              >
                {item.completed ? "Done" : "Mark"}
              </button>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}
