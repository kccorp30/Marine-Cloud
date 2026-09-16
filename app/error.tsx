"use client";
import { useRouter } from "next/navigation";
import { useCommandCopy } from "@/components/ui/LocaleProvider";

export default function ErrorPage({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  const { t } = useCommandCopy();
  const router = useRouter();
  return (
    <section role="alert" className="command-panel command-empty max-w-xl mx-auto my-10 relative overflow-hidden">
      <div className="absolute -top-24 left-1/2 -translate-x-1/2 w-80 h-52 rounded-full bg-blue-400/[.08] blur-3xl pointer-events-none" />
      <div className="relative">
        <p className="eyebrow text-gold mb-4">KCC MARINE CLOUD · RECOVERY</p>
        <h1 className="text-2xl mb-3">{t.unavailable}</h1>
        <p className="text-sm text-cool-gray mb-6">The workspace can recover without losing your session. Retry the view first; if the route was changing, refresh its server data.</p>
        <div className="flex flex-wrap justify-center gap-3">
          <button className="command-button" onClick={() => reset()}>{t.retry}</button>
          <button className="command-button command-button-secondary" onClick={() => router.refresh()}>Refresh data</button>
          <a className="command-button command-button-secondary" href="/dashboard">Home</a>
        </div>
      </div>
    </section>
  );
}
