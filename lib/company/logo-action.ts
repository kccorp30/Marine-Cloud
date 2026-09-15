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
    file.size > 2 * 1024 * 1024 ||
    !["image/png", "image/jpeg", "image/webp"].includes(file.type)
  )
    return { error: "Use JPEG, PNG or WebP under 2 MB." };
  let image: Buffer;
  try {
    image = await sharp(Buffer.from(await file.arrayBuffer()), {
      limitInputPixels: 16000000,
    })
      .rotate()
      .resize(320, 200, { fit: "inside", withoutEnlargement: true })
      .webp({ quality: 80 })
      .toBuffer();
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
