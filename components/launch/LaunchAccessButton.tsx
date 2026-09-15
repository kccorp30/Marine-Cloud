"use client";
import { useState, useTransition } from "react";
import { enableLaunchAccess } from "@/lib/launch/actions";
export function LaunchAccessButton({
  organizationId,
  locale = "en",
}: {
  organizationId: string;
  locale?: "en" | "es";
}) {
  const [pending, start] = useTransition();
  const [message, setMessage] = useState("");
  return (
    <div>
      <button
        disabled={pending}
        className="command-button"
        onClick={() =>
          start(async () => {
            const result = await enableLaunchAccess(organizationId);
            setMessage(
              result.error ||
                (locale === "es"
                  ? "Acceso operativo habilitado, sin membresía."
                  : "Operational access enabled, without subscription charges."),
            );
          })
        }
      >
        {pending
          ? "…"
          : locale === "es"
            ? "Habilitar operación sin membresía"
            : "Enable operation without subscription"}
      </button>
      <p role="status" className="text-xs text-cool-gray mt-2">
        {message}
      </p>
    </div>
  );
}
