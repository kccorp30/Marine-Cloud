import { describe, it, expect, vi, beforeEach } from "vitest";
vi.mock("server-only", () => ({}));
vi.mock("@/lib/auth/session", () => ({ getSessionContext: vi.fn() }));
vi.mock("@/lib/supabase/server", () => ({ createClient: vi.fn() }));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
import { getSessionContext } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { enableLaunchAccess } from "@/lib/launch/actions";
describe("launch access authorization", () => {
  beforeEach(() => vi.clearAllMocks());
  it("rejects a non-admin without querying or mutating the database", async () => {
    vi.mocked(getSessionContext).mockResolvedValue({
      isKccAdmin: false,
    } as any);
    expect(await enableLaunchAccess("other-company")).toHaveProperty("error");
    expect(createClient).not.toHaveBeenCalled();
  });
  it("does not reactivate a suspended company", async () => {
    vi.mocked(getSessionContext).mockResolvedValue({ isKccAdmin: true } as any);
    const single = vi.fn(async () => ({
      data: { status: "suspended" },
      error: null,
    }));
    const rpc = vi.fn();
    vi.mocked(createClient).mockResolvedValue({
      from: () => ({ select: () => ({ eq: () => ({ single }) }) }),
      rpc,
    } as any);
    expect(await enableLaunchAccess("suspended-company")).toHaveProperty(
      "error",
    );
    expect(rpc).not.toHaveBeenCalled();
  });
});
