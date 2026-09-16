function escape(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
export function renderOperationalEmail({
  body,
  signature,
  portalUrl,
  locale = "en",
}: {
  body: string;
  signature?: string | null;
  portalUrl: string;
  locale?: "en" | "es";
}) {
  const url = new URL(portalUrl);
  if (!["https:", "http:"].includes(url.protocol))
    throw new Error("Invalid portal URL");
  const es = locale === "es";
  return `<!doctype html><html lang="${locale}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:#eef2f5;font-family:Arial,sans-serif;color:#15273a"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:32px 12px"><table role="presentation" width="600" style="max-width:600px;width:100%;border-radius:18px;overflow:hidden;background:white" cellpadding="0" cellspacing="0"><tr><td style="background:#071827;padding:32px;border-bottom:3px solid #d7b96e"><p style="color:#d7b96e;letter-spacing:4px;font-size:12px;margin:0">KCC MARINE CLOUD</p><h1 style="color:#fff;font-size:26px;font-weight:normal;margin:18px 0 0">${es ? "Tu embarcación, en buenas manos." : "Your vessel, in good hands."}</h1></td></tr><tr><td style="padding:32px;font-size:15px;line-height:1.75">${escape(body).replaceAll("\n", "<br>")}<p style="margin:28px 0"><a href="${escape(url.href)}" style="display:inline-block;background:#dfbd70;color:#071827;border-radius:8px;padding:14px 24px;font-weight:bold;text-decoration:none">${es ? "Abrir mi portal" : "Open my portal"} &rarr;</a></p><p style="color:#5c6c7b;font-size:13px">${es ? "Consulta tus estimados, aprobaciones, fotografías y avances desde tu cuenta segura." : "Review estimates, approvals, photos and service updates in your secure account."}</p>${signature ? `<div style="border-top:1px solid #e1e7ed;margin-top:24px;padding-top:20px;color:#5c6c7b;font-size:13px">${escape(signature).replaceAll("\n", "<br>")}</div>` : ""}</td></tr><tr><td style="background:#f5f7f9;padding:20px 32px;color:#708090;font-size:11px">KCC · MARINE SOLUTIONS · TECHNOLOGY · EXCELLENCE</td></tr></table></td></tr></table></body></html>`;
}
