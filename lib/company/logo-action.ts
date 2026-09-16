"use server";
import sharp from "sharp";
import { getSessionContext } from "@/lib/auth/session";
import { getActiveOrganizationId } from "@/lib/auth/active-org";
import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
export async function saveCompanyLogo(form: FormData) {
  const session = await getSessionContext();
  const org = await getActiveOrganizationId(session.memberships);
  if (!org) return { error: "No workspace selected." };
  if (
    !session.isKccAdmin &&
    !session.memberships.some(
      (m) =>
        m.organization_id === org &&
        ["company_owner", "company_admin"].includes(m.role),
    )
  )
    return { error: "Company administrator access required." };
  const file = form.get("logo");
  if (
    !(file instanceof File) ||
    !file.size ||
    file.size > 12 * 1024 * 1024 ||
    !["image/png", "image/jpeg", "image/webp"].includes(file.type)
  )
    return { error: "Use JPEG, PNG or WebP under 12 MB." };
  let image: Buffer;
  try {
    const source = sharp(Buffer.from(await file.arrayBuffer()), {
      limitInputPixels: 80000000,
    }).rotate().resize(640, 360, { fit: "inside", withoutEnlargement: true }).ensureAlpha();

    if (form.get("removeDarkBackground") === "on") {
      const { data, info } = await source.raw().toBuffer({ resolveWithObject: true });
      // Background helper intended for logos photographed/exported on near-black canvas.
      // It preserves bright/gold artwork and feathers the threshold instead of a hard cut.
      for (let i = 0; i < data.length; i += 4) {
        const r = data[i], g = data[i + 1], b = data[i + 2];
        const max = Math.max(r, g, b);
        const min = Math.min(r, g, b);
        const chroma = max - min;
        if (max <= 42 && chroma <= 22) data[i + 3] = 0;
        else if (max < 82 && chroma <= 28) data[i + 3] = Math.min(data[i + 3], Math.round(((max - 42) / 40) * 255));
      }
      image = await sharp(data, { raw: info })
        .trim({ background: { r: 0, g: 0, b: 0, alpha: 0 } })
        .resize(420, 240, { fit: "inside", withoutEnlargement: true })
        .webp({ quality: 88, alphaQuality: 100 })
        .toBuffer();
    } else {
      image = await source
        .resize(420, 240, { fit: "inside", withoutEnlargement: true })
        .webp({ quality: 86, alphaQuality: 100 })
        .toBuffer();
    }
  } catch {
    return { error: "Unable to read this image." };
  }
  const db = await createClient();
  const { error } = await db.rpc("update_company_logo", {
    p_organization_id: org,
    p_logo: `data:image/webp;base64,${image.toString("base64")}`,
  });
  if (error) return { error: error.code === "PGRST202" ? "Company logo uploads need to be enabled by KCC support. Your current logo has not been changed." : error.message };
  revalidatePath("/", "layout");
  return { success: true };
}
