import { describe, it, expect } from "vitest";
import { renderOperationalEmail } from "@/lib/email/operational-template";
describe("customer email", () => {
  it("escapes customer text and preserves commercial amounts", () => {
    const html = renderOperationalEmail({
      body: "Estimate $1,280.00\n<script>alert(1)</script>",
      signature: "A & B",
      portalUrl: "https://example.com/customer",
    });
    expect(html).toContain("$1,280.00");
    expect(html).not.toContain("<script>");
    expect(html).toContain("A &amp; B");
    expect(html).toContain("https://example.com/customer");
  });
  it("rejects executable links", () =>
    expect(() =>
      renderOperationalEmail({ body: "Hi", portalUrl: "javascript:alert(1)" }),
    ).toThrow());
});
