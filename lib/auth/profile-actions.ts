"use server";
import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import sharp from "sharp";
import { cookies } from "next/headers";
export async function saveProfile(form: FormData) {
  const db = await createClient();
  const {
    data: { user },
  } = await db.auth.getUser();
  if (!user) return { error: "Sign in to continue." };
  const organizationId = String(form.get("organizationId") || "");
  if (organizationId) {
    const membership = await db
      .from("organization_memberships")
      .select("organization_id")
      .eq("profile_id", user.id)
      .eq("organization_id", organizationId)
      .eq("status", "active")
      .limit(1);
    if (membership.error || !membership.data?.length)
      return { error: "Workspace unavailable." };
  }
  const name = String(form.get("fullName") || "").trim();
  const phone = String(form.get("phone") || "").trim();
  const locale = form.get("locale");
  if (
    name.length < 2 ||
    name.length > 120 ||
    phone.length > 40 ||
    !["en", "es"].includes(String(locale))
  )
    return { error: "Please check your profile details." };
  const values: Record<string, unknown> = {
    full_name: name,
    phone: phone || null,
    preferred_language: locale,
  };
  const photo = form.get("photo");
  if (photo instanceof File && photo.size) {
    if (
      photo.size > 2 * 1024 * 1024 ||
      !["image/jpeg", "image/png", "image/webp"].includes(photo.type)
    )
      return { error: "Use a JPEG, PNG or WebP image under 2 MB." };
    try {
      const output = await sharp(Buffer.from(await photo.arrayBuffer()), {
        limitInputPixels: 16000000,
      })
        .rotate()
        .resize(192, 192, { fit: "cover" })
        .webp({ quality: 75 })
        .toBuffer();
      values.avatar_url = `data:image/webp;base64,${output.toString("base64")}`;
    } catch {
      return { error: "This image could not be processed." };
    }
  }
  const { error } = await db
    .from("profiles")
    .update(values)
    .eq("id", user.id)
    .select("id")
    .single();
  if (error) return { error: error.message };
  // User-editable UX preference only. Never used to grant roles or access.
  const result = await db.auth.updateUser({
    data: { profile_setup_complete: true },
  });
  if (result.error) return { error: result.error.message };
  const cookieStore = await cookies();
  if (organizationId)
    cookieStore.set("kcc_active_org", organizationId, {
      httpOnly: true,
      sameSite: "lax",
      path: "/",
    });
  cookieStore.set("kcc_locale", String(locale), {
    path: "/",
    maxAge: 31536000,
    sameSite: "lax",
  });
  revalidatePath("/", "layout");
  return { success: true };
}
