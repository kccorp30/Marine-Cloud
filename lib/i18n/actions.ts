"use server";

import { cookies } from "next/headers";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { LOCALE_COOKIE_NAME } from "./server";
import type { Locale } from "./dictionary";

export async function setLocaleAction(locale: Locale) {
  if (locale !== "en" && locale !== "es")
    throw new Error("Unsupported language");
  const cookieStore = await cookies();
  cookieStore.set(LOCALE_COOKIE_NAME, locale, {
    maxAge: 60 * 60 * 24 * 365,
    path: "/",
  });

  try {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (user) {
      await supabase
        .from("profiles")
        .update({ preferred_language: locale })
        .eq("id", user.id);
    }
  } catch {
    // Sin sesión (ej. en /login) — la cookie ya alcanza para persistir la elección.
  }

  revalidatePath("/", "layout");
}
