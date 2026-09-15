import { describe, it, expect, vi, beforeEach } from "vitest";
import { IDBFactory } from "fake-indexeddb";

vi.mock("@/lib/technician/actions", () => ({
  addWorkNote: vi.fn(async () => ({ success: true })),
  addMeasurement: vi.fn(async () => ({ success: true })),
  addProgressUpdate: vi.fn(async () => ({ success: true })),
  submitChecklistResponse: vi.fn(async () => ({ success: true })),
  initiateMediaUpload: vi.fn(async () => ({
    success: true,
    path: "org/wo/before/photo-1.jpg",
    token: "fake-token",
    vesselId: "vessel-1",
  })),
  confirmMediaUpload: vi.fn(async () => ({ success: true })),
}));

const uploadToSignedUrlMock = vi.fn(
  async (): Promise<{ error: null | { message: string } }> => ({ error: null }),
);
vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    storage: {
      from: () => ({ uploadToSignedUrl: uploadToSignedUrlMock }),
    },
  }),
}));

beforeEach(() => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (globalThis as any).indexedDB = new IDBFactory();
  vi.clearAllMocks();
  uploadToSignedUrlMock.mockResolvedValue({ error: null });
});

describe("syncQueue", () => {
  it("routes a note item to addWorkNote and removes it from the queue on success", async () => {
    const { enqueue, listQueue } = await import("@/lib/offline/queue");
    const { syncQueue } = await import("@/lib/offline/sync");
    const actions = await import("@/lib/technician/actions");

    await enqueue({
      id: "n1",
      type: "note",
      workOrderId: "wo-1",
      payload: { appointmentId: null, body: "test", noteType: "general" },
    });

    const result = await syncQueue();
    expect(result).toEqual({ synced: 1, failed: 0 });
    expect(actions.addWorkNote).toHaveBeenCalledWith(
      expect.objectContaining({ clientGeneratedId: "n1", body: "test" }),
    );

    const remaining = await listQueue();
    expect(remaining).toHaveLength(0);
  });

  it("uploads the real photo Blob to Storage AND confirms media_assets — both steps required", async () => {
    const { enqueue } = await import("@/lib/offline/queue");
    const { syncQueue } = await import("@/lib/offline/sync");
    const actions = await import("@/lib/technician/actions");

    const blob = new Blob(["image-bytes"], { type: "image/jpeg" });
    await enqueue({
      id: "photo-1",
      type: "photo",
      workOrderId: "wo-1",
      blob,
      payload: {
        vesselId: "vessel-1",
        appointmentId: null,
        category: "before",
        mimeType: "image/jpeg",
        sizeBytes: blob.size,
        visibility: "internal",
        capturedAt: "2026-01-01T10:00:00.000Z",
      },
    });

    const result = await syncQueue();
    expect(result).toEqual({ synced: 1, failed: 0 });

    expect(actions.initiateMediaUpload).toHaveBeenCalledWith(
      "wo-1",
      "before",
      "image/jpeg",
      "photo-1",
    );
    expect(uploadToSignedUrlMock).toHaveBeenCalledWith(
      "org/wo/before/photo-1.jpg",
      "fake-token",
      blob,
    );
    expect(actions.confirmMediaUpload).toHaveBeenCalledWith(
      expect.objectContaining({
        capturedAt: "2026-01-01T10:00:00.000Z",
        clientGeneratedId: "photo-1",
      }),
    );
  });

  it("D: caption survives the full offline queue → reconnect → sync round trip", async () => {
    const { enqueue } = await import("@/lib/offline/queue");
    const { syncQueue } = await import("@/lib/offline/sync");
    const actions = await import("@/lib/technician/actions");

    const blob = new Blob(["image-bytes"], { type: "image/jpeg" });
    await enqueue({
      id: "photo-caption-1",
      type: "photo",
      workOrderId: "wo-1",
      blob,
      payload: {
        vesselId: "vessel-1",
        appointmentId: null,
        category: "diagnosis",
        mimeType: "image/jpeg",
        sizeBytes: blob.size,
        caption: "Corroded terminal on positive lead",
        visibility: "internal",
        capturedAt: "2026-01-01T10:00:00.000Z",
      },
    });

    const result = await syncQueue();
    expect(result).toEqual({ synced: 1, failed: 0 });

    expect(actions.confirmMediaUpload).toHaveBeenCalledWith(
      expect.objectContaining({
        caption: "Corroded terminal on positive lead",
        clientGeneratedId: "photo-caption-1",
      }),
    );
  });

  it("keeps the photo item in the queue if the Storage upload fails (never confirms without the binary)", async () => {
    uploadToSignedUrlMock.mockResolvedValueOnce({
      error: { message: "network down" },
    });

    const { enqueue, listQueue } = await import("@/lib/offline/queue");
    const { syncQueue } = await import("@/lib/offline/sync");
    const actions = await import("@/lib/technician/actions");

    const blob = new Blob(["x"], { type: "image/jpeg" });
    await enqueue({
      id: "photo-2",
      type: "photo",
      workOrderId: "wo-1",
      blob,
      payload: {
        vesselId: "vessel-1",
        appointmentId: null,
        category: "before",
        mimeType: "image/jpeg",
        sizeBytes: blob.size,
        visibility: "internal",
        capturedAt: new Date().toISOString(),
      },
    });

    const result = await syncQueue();
    expect(result).toEqual({ synced: 0, failed: 1 });
    expect(actions.confirmMediaUpload).not.toHaveBeenCalled();

    const remaining = await listQueue();
    expect(remaining).toHaveLength(1);
    expect(remaining[0].status).toBe("failed");
    if (remaining[0].type === "photo") {
      expect(remaining[0].blob).toBeInstanceOf(Blob);
    }
  });

  it("routes a checklist_response item to submitChecklistResponse", async () => {
    const { enqueue } = await import("@/lib/offline/queue");
    const { syncQueue } = await import("@/lib/offline/sync");
    const actions = await import("@/lib/technician/actions");

    await enqueue({
      id: "chk-1",
      type: "checklist_response",
      workOrderId: "wo-1",
      payload: {
        appointmentId: null,
        templateItemId: "item-1",
        responseValue: { result: "pass" },
      },
    });

    const result = await syncQueue();
    expect(result).toEqual({ synced: 1, failed: 0 });
    expect(actions.submitChecklistResponse).toHaveBeenCalledWith(
      expect.objectContaining({
        templateItemId: "item-1",
        responseValue: { result: "pass" },
        clientGeneratedId: "chk-1",
      }),
    );
  });

  it("applies queued checklist corrections in creation order (later answer wins)", async () => {
    const { enqueue } = await import("@/lib/offline/queue");
    const { syncQueue } = await import("@/lib/offline/sync");
    const actions = await import("@/lib/technician/actions");

    await enqueue({
      id: "chk-a",
      type: "checklist_response",
      workOrderId: "wo-1",
      payload: {
        appointmentId: null,
        templateItemId: "item-1",
        responseValue: { result: "pass" },
      },
    });
    await new Promise((r) => setTimeout(r, 5));
    await enqueue({
      id: "chk-b",
      type: "checklist_response",
      workOrderId: "wo-1",
      payload: {
        appointmentId: null,
        templateItemId: "item-1",
        responseValue: { result: "fail" },
      },
    });

    await syncQueue();

    const calls = (actions.submitChecklistResponse as ReturnType<typeof vi.fn>)
      .mock.calls;
    expect(calls[0][0]).toMatchObject({
      clientGeneratedId: "chk-a",
      responseValue: { result: "pass" },
    });
    expect(calls[1][0]).toMatchObject({
      clientGeneratedId: "chk-b",
      responseValue: { result: "fail" },
    });
  });

  it("marks a failed item with its error and does not remove it from the queue", async () => {
    const actions = await import("@/lib/technician/actions");
    (actions.addMeasurement as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      error: "server rejected",
    });

    const { enqueue, listQueue } = await import("@/lib/offline/queue");
    const { syncQueue } = await import("@/lib/offline/sync");

    await enqueue({
      id: "m1",
      type: "measurement",
      workOrderId: "wo-1",
      payload: {
        vesselId: "v1",
        appointmentId: null,
        measurementType: "voltage",
        value: 12.4,
        unit: "V",
        label: "Test",
      },
    });

    const result = await syncQueue();
    expect(result).toEqual({ synced: 0, failed: 1 });

    const remaining = await listQueue();
    expect(remaining).toHaveLength(1);
    expect(remaining[0].status).toBe("failed");
    expect(remaining[0].error).toBe("server rejected");
  });
});
