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
      <button disabled={pending} className="command-button">
        {pending ? "…" : t.save}
      </button>
      <p role="status" className="text-sm text-cool-gray">
        {message}
      </p>
    </form>
  );
}
