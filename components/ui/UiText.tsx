"use client";
import { useCommandCopy } from "./LocaleProvider";
import { operationalSpanish } from "@/lib/i18n/operational-copy";
export function UiText({ text }: { text: string }) {
  const { locale } = useCommandCopy();
  return <>{locale === "es" ? operationalSpanish[text] || text : text}</>;
}
