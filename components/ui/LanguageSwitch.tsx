"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { setLocaleAction } from "@/lib/i18n/actions";
import type { Locale } from "@/lib/i18n/dictionary";

export function LanguageSwitch({
  current,
  variant = "default",
}: {
  current: Locale;
  variant?: "default" | "onDark";
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  function switchTo(locale: Locale) {
    if (locale === current || pending) return;
    startTransition(async () => {
      await setLocaleAction(locale);
      router.refresh();
    });
  }

  const base = variant === "onDark" ? "text-cool-gray/80" : "text-cool-gray";

  return (
    <div
      className={`inline-flex items-center gap-1 font-mono text-[10px] uppercase tracking-[0.08em] ${base}`}
      role="group"
      aria-label="Language"
    >
      <button
        type="button"
        onClick={() => switchTo("en")}
        aria-pressed={current === "en"}
        className={`px-2 py-1 rounded-sm transition-colors ${current === "en" ? "text-gold bg-gold/10" : "hover:text-marine-white"}`}
      >
        EN
      </button>
      <span className="opacity-30">/</span>
      <button
        type="button"
        onClick={() => switchTo("es")}
        aria-pressed={current === "es"}
        className={`px-2 py-1 rounded-sm transition-colors ${current === "es" ? "text-gold bg-gold/10" : "hover:text-marine-white"}`}
      >
        ES
      </button>
    </div>
  );
}
