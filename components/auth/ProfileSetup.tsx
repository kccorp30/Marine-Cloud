"use client";

import { prepareImage } from "@/lib/image-upload";
import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { saveProfile } from "@/lib/auth/profile-actions";
import { useCommandCopy } from "@/components/ui/LocaleProvider";

export function ProfileSetup({
  name,
  phone,
  avatar,
  destination,
  organizationId,
}: {
  organizationId: string | null;
  name: string;
  phone: string;
  avatar: string | null;
  destination: string;
}) {
  const { locale, t } = useCommandCopy();
  const [error, setError] = useState("");
  const [preview, setPreview] = useState<string | null>(avatar);
  const [pending, start] = useTransition();
  const router = useRouter();
  const initials = useMemo(
    () => (name || "KCC").split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]?.toUpperCase()).join(""),
    [name],
  );

  return (
    <form
      className="space-y-5"
      onSubmit={(e) => {
        e.preventDefault();
        const form = new FormData(e.currentTarget);
        start(async () => {
          const result = await (async () => {
            try {
              await prepareImage(form, "photo");
              return await saveProfile(form);
            } catch {
              return { error: t.saveError };
            }
          })();
          if (result.error) setError(result.error);
          else {
            router.push(destination);
            router.refresh();
          }
        });
      }}
    >
      <input type="hidden" name="organizationId" value={organizationId || ""} />

      <div className="flex items-center gap-4 rounded-2xl border border-white/[.07] bg-white/[.025] p-4">
        <div className="relative grid h-16 w-16 shrink-0 place-items-center overflow-hidden rounded-2xl border border-gold/25 bg-[#0b1c2d] text-lg font-semibold text-gold shadow-[0_0_30px_-18px_rgba(228,199,122,.7)]">
          {preview ? <img src={preview} alt="" className="h-full w-full object-cover" /> : initials}
          <span className="absolute bottom-1 right-1 h-2.5 w-2.5 rounded-full border-2 border-[#0b1c2d] bg-emerald-400" />
        </div>
        <div className="min-w-0">
          <p className="text-sm font-medium text-marine-white">{name || (locale === "es" ? "Tu perfil" : "Your profile")}</p>
          <p className="mt-1 text-[11px] leading-relaxed text-cool-gray">
            {locale === "es" ? "Esta identidad aparecerá en mensajes, órdenes y actividad autorizada." : "This identity appears in messages, work orders and authorized activity."}
          </p>
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="auth-field-group sm:col-span-2">
          <label htmlFor="profile-name" className="auth-field-label">{t.fullName}</label>
          <div className="auth-input-shell">
            <span className="auth-input-icon">◎</span>
            <input id="profile-name" required name="fullName" minLength={2} maxLength={120} defaultValue={name} autoComplete="name" className="auth-input" />
          </div>
        </div>

        <div className="auth-field-group">
          <label htmlFor="profile-phone" className="auth-field-label">{t.phone}</label>
          <div className="auth-input-shell">
            <span className="auth-input-icon">⌁</span>
            <input id="profile-phone" name="phone" type="tel" maxLength={40} defaultValue={phone} autoComplete="tel" className="auth-input" />
          </div>
        </div>

        <div className="auth-field-group">
          <label htmlFor="profile-language" className="auth-field-label">{t.language}</label>
          <div className="auth-input-shell">
            <span className="auth-input-icon">文</span>
            <select id="profile-language" name="locale" defaultValue={locale} className="auth-input appearance-none">
              <option value="en">English</option>
              <option value="es">Español</option>
            </select>
          </div>
        </div>
      </div>

      <label className="group flex cursor-pointer items-center justify-between gap-4 rounded-2xl border border-dashed border-[#91afd1]/20 bg-white/[.018] p-4 transition-all hover:border-gold/40 hover:bg-white/[.03]">
        <div>
          <p className="text-xs text-marine-white">{t.photo}</p>
          <p className="mt-1 text-[10px] text-cool-gray">{t.optional} · {t.photoHint}</p>
        </div>
        <span className="rounded-xl border border-white/10 px-3 py-2 text-[9px] font-mono uppercase tracking-[.1em] text-gold transition group-hover:border-gold/30">Choose photo</span>
        <input
          type="file"
          name="photo"
          accept="image/jpeg,image/png,image/webp"
          capture="user"
          className="sr-only"
          onChange={(event) => {
            const file = event.target.files?.[0];
            if (!file) return;
            const url = URL.createObjectURL(file);
            setPreview(url);
          }}
        />
      </label>

      {error && <div role="alert" className="auth-alert"><span>!</span><p>{error}</p></div>}

      <button disabled={pending} className="auth-primary-button">
        <span>{pending ? (locale === "es" ? "Guardando…" : "Saving…") : locale === "es" ? "Entrar a Marine Cloud" : "Enter Marine Cloud"}</span>
        <span className="auth-button-arrow">→</span>
      </button>
    </form>
  );
}
