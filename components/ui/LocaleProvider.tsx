"use client";
import { createContext, useContext } from "react";
import type { Locale } from "@/lib/i18n/dictionary";
import { commandCopy } from "@/lib/i18n/command-copy";
export const LocaleContext = createContext<Locale>("en");
export function LocaleProvider({
  locale,
  children,
}: {
  locale: Locale;
  children: React.ReactNode;
}) {
  return (
    <LocaleContext.Provider value={locale}>{children}</LocaleContext.Provider>
  );
}
export function useCommandCopy() {
  const locale = useContext(LocaleContext);
  return { locale, t: commandCopy[locale] };
}
