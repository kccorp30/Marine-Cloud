"use client";

import { useCommandCopy } from "@/components/ui/LocaleProvider";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Membership } from "@/lib/auth/session";
import { setActiveOrganizationId, signOut } from "@/lib/auth/actions";
import { NotificationBell } from "@/components/notifications/NotificationBell";
import { LanguageSwitch } from "@/components/ui/LanguageSwitch";
import type { Locale } from "@/lib/i18n/dictionary";
import type { NotificationPreferences } from "@/lib/notifications/preferences";

export function TopHeader({
  fullName,
  avatarUrl,
  memberships,
  activeOrgId,
  isKccAdmin,
  userId,
  initialUnreadCount,
  locale,
  role,
  notificationPreferences,
  onMenuToggle,
  showSearch = false,
}: {
  fullName: string | null;
  avatarUrl?: string | null;
  memberships: Membership[];
  activeOrgId: string | null;
  isKccAdmin: boolean;
  userId: string;
  initialUnreadCount: number;
  locale: Locale;
  role: string;
  notificationPreferences: NotificationPreferences;
  onMenuToggle: () => void;
  showSearch?: boolean;
}) {
  const { t } = useCommandCopy();
  const router = useRouter();
  const [switching, setSwitching] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  async function handleSwitch(orgId: string) {
    setSwitching(true);
    await setActiveOrganizationId(orgId);
    router.refresh();
    setSwitching(false);
  }
  const initials = (fullName ?? "?")
    .split(" ")
    .map((p) => p[0])
    .slice(0, 2)
    .join("")
    .toUpperCase();
  const roleLabel = isKccAdmin ? "Administrator" : role.replace(/_/g, " ");

  return (
    <header className="relative z-30 h-[74px] shrink-0 flex items-center px-4 lg:px-7 gap-4 bg-[#061321]/82 backdrop-blur-2xl border-b border-white/[0.055] shadow-[0_18px_55px_-45px_rgba(0,0,0,.95)]">
      <button
        type="button"
        onClick={onMenuToggle}
        className="lg:hidden text-marine-white p-2 -ml-2 rounded-lg hover:bg-white/[0.05]"
        aria-label="Toggle menu"
      >
        <svg width="21" height="21" viewBox="0 0 20 20" fill="none">
          <path
            d="M2 5h16M2 10h16M2 15h16"
            stroke="currentColor"
            strokeWidth="1.5"
            strokeLinecap="round"
          />
        </svg>
      </button>

      <div className="hidden xl:flex items-center gap-3 mr-1">
        <span className="eyebrow text-silver/65">KCC Marine Cloud</span>
        <span className="w-16 h-px bg-gold-dim/60" />
      </div>

      {!isKccAdmin && memberships.length > 1 && (
        <select
          value={activeOrgId ?? ""}
          onChange={(e) => handleSwitch(e.target.value)}
          disabled={switching}
          className="hidden sm:block bg-[#0a1b2d] border border-white/10 text-xs px-3 py-2 rounded-lg"
        >
          <option value="" disabled>
            Workspace
          </option>
          {memberships.map((m) => (
            <option
              key={m.organization_id}
              value={m.organization_id}
              className="bg-navy"
            >
              {m.organization.name}
            </option>
          ))}
        </select>
      )}

      {showSearch && (
        <div className="hidden md:flex flex-1 max-w-xl">
          <form action="/search" className="relative w-full">
            <svg
              className="absolute left-3.5 top-1/2 -translate-y-1/2 text-cool-gray/65"
              width="16"
              height="16"
              viewBox="0 0 15 15"
              fill="none"
            >
              <circle
                cx="6.5"
                cy="6.5"
                r="5"
                stroke="currentColor"
                strokeWidth="1.3"
              />
              <path
                d="M10.5 10.5L14 14"
                stroke="currentColor"
                strokeWidth="1.3"
                strokeLinecap="round"
              />
            </svg>
            <input
              name="q"
              type="search"
              placeholder={t.workOrders + "…"}
              className="w-full bg-[#0a1a2a]/80 border border-[#7da1c8]/20 focus:border-gold-dim/70 outline-none pl-10 pr-4 py-2.5 text-xs rounded-xl transition-all focus:shadow-glow-gold placeholder:text-cool-gray/45"
            />
          </form>
        </div>
      )}

      <div className="flex-1" />
      <div className="hidden sm:block">
        <LanguageSwitch current={locale} />
      </div>
      <NotificationBell
        userId={userId}
        initialUnreadCount={initialUnreadCount}
        locale={locale}
        notificationPreferences={notificationPreferences}
      />

      <div className="relative">
        <button
          type="button"
          onClick={() => setMenuOpen((v) => !v)}
          className="flex items-center gap-2.5 pl-1 pr-2 py-1 rounded-xl hover:bg-white/[0.04] transition-colors"
        >
          <span className="w-9 h-9 rounded-full bg-gradient-to-br from-gold-bright via-gold to-gold-dim text-[#07101c] text-[11px] font-black flex items-center justify-center shadow-glow-gold">
            {avatarUrl ? (
              <img
                src={avatarUrl}
                alt=""
                className="w-full h-full rounded-full object-cover"
              />
            ) : (
              initials
            )}
          </span>
          <span className="hidden sm:block text-left">
            <span className="block text-xs text-marine-white max-w-[130px] truncate">
              {fullName}
            </span>
            <span className="block text-[9px] capitalize text-gold-dim mt-0.5">
              {roleLabel}
            </span>
          </span>
          <span className="hidden sm:block text-cool-gray/70 text-xs">⌄</span>
        </button>
        {menuOpen && (
          <>
            <div
              className="fixed inset-0 z-40"
              onClick={() => setMenuOpen(false)}
            />
            <div className="absolute right-0 top-full mt-2 w-52 glass-strong rounded-xl shadow-premium z-50 p-2 animate-fade-up">
              <div className="px-3 py-2 text-xs text-cool-gray border-b border-white/[0.06] mb-1 sm:hidden">
                <LanguageSwitch current={locale} />
              </div>
              <a
                href="/welcome"
                className="block px-3 py-2.5 text-xs rounded-lg hover:bg-white/5"
              >
                {t.profile}
              </a>
              <form action={signOut}>
                <button
                  type="submit"
                  className="w-full text-left px-3 py-2.5 text-xs text-cool-gray hover:text-red-300 hover:bg-white/[0.04] rounded-lg transition-colors"
                >
                  {t.signOut}
                </button>
              </form>
            </div>
          </>
        )}
      </div>
    </header>
  );
}
