"use client";
import { useCommandCopy } from "@/components/ui/LocaleProvider";
export default function ErrorPage({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  const { t } = useCommandCopy();
  return (
    <section
      role="alert"
      className="command-panel command-empty max-w-xl mx-auto my-10"
    >
      <p className="eyebrow text-gold mb-4">KCC MARINE CLOUD</p>
      <h1 className="text-2xl mb-6">{t.unavailable}</h1>
      <button className="command-button" onClick={reset}>
        {t.retry}
      </button>
    </section>
  );
}
