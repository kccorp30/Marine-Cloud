import { describe, it, expect } from "vitest";
import { isToday } from "@/lib/technician/day-plan";
describe("company-local technician schedule", () => {
  it("does not call tomorrow’s appointment a job for today", () =>
    expect(
      isToday(
        "2026-09-15T15:00:00Z",
        "America/Bogota",
        new Date("2026-09-14T16:00:00Z"),
      ),
    ).toBe(false));
  it("uses company date across the UTC midnight boundary", () =>
    expect(
      isToday(
        "2026-09-15T01:00:00Z",
        "America/Bogota",
        new Date("2026-09-14T23:30:00Z"),
      ),
    ).toBe(true));
  it("handles the daylight saving transition", () =>
    expect(
      isToday(
        "2026-11-01T06:30:00Z",
        "America/New_York",
        new Date("2026-11-01T05:30:00Z"),
      ),
    ).toBe(true));
  it("keeps unscheduled jobs outside today", () =>
    expect(isToday(null, "America/Bogota")).toBe(false));
});
