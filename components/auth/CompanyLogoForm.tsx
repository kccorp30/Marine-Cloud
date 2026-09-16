"use client";
import {prepareImage} from "@/lib/image-upload";
import { useState, useTransition } from "react";
import { saveCompanyLogo } from "@/lib/company/logo-action";
import { useCommandCopy } from "@/components/ui/LocaleProvider";
export function CompanyLogoForm() {
  const { t } = useCommandCopy();
  const [pending, start] = useTransition();
  const [message, setMessage] = useState("");
  return (
    <form
      className="command-panel p-6 space-y-4"
      onSubmit={(e) => {
        e.preventDefault();
        const form = new FormData(e.currentTarget);
        start(async () => {
          const result = await (async()=>{try{await prepareImage(form,"logo");return await saveCompanyLogo(form);}catch{return {error:t.saveError};}})();
          setMessage(result.error || t.profileSaved);
        });
      }}
    >
      <label className="command-field">
        Logo
        <input
          required
          name="logo"
          type="file"
          accept="image/jpeg,image/png,image/webp"
        />
        <small>{t.photoHint}</small>
      </label>
      <label className="flex items-center gap-3 rounded-xl border border-white/10 bg-white/[.025] p-3 text-sm">
        <input name="removeDarkBackground" type="checkbox" defaultChecked className="h-4 w-4" />
        <span>Remove dark background <small className="block text-cool-gray mt-1">Best for gold/white logos exported on a black square.</small></span>
      </label>
      <button disabled={pending} className="command-button">
        {pending ? "…" : t.save}
      </button>
      <p role="status" className="text-sm text-cool-gray">
        {message}
      </p>
    </form>
  );
}
