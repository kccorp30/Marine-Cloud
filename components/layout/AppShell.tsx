"use client";

import { useState } from "react";
import type { Membership } from "@/lib/auth/session";
import { Sidebar } from "./Sidebar";
import { TopHeader } from "./TopHeader";
import type { Locale } from "@/lib/i18n/dictionary";
import type { NotificationPreferences } from "@/lib/notifications/preferences";
import { AttentionCenter } from "@/components/notifications/AttentionCenter";

export function AppShell({
  fullName,
  avatarUrl,
  memberships,
  activeOrgId,
  isKccAdmin,
  userId,
  initialUnreadCount,
  role,
  orgName,
  companyLogo,
  locale,
  notificationPreferences,
  children,
}: {
  fullName: string | null;
  avatarUrl?: string | null;
  memberships: Membership[];
  activeOrgId: string | null;
  isKccAdmin: boolean;
  userId: string;
  initialUnreadCount: number;
  role: string;
  orgName: string | null;
  companyLogo?: string | null;
  locale: Locale;
  notificationPreferences: NotificationPreferences;
  children: React.ReactNode;
}) {
  const [mobileOpen, setMobileOpen] = useState(false);
  const showSearch =
    isKccAdmin || ["company_owner", "company_admin", "manager"].includes(role);

  return (
    <div className="h-screen overflow-hidden flex relative app-grid-bg">
      <div className="fixed inset-0 pointer-events-none bg-[radial-gradient(circle_at_70%_0%,rgba(26,93,157,.10),transparent_35%),radial-gradient(circle_at_28%_100%,rgba(201,162,75,.05),transparent_26%)]" />
      <Sidebar
        companyLogo={companyLogo}
        role={role}
        isKccAdmin={isKccAdmin}
        orgName={orgName}
        fullName={fullName}
        mobileOpen={mobileOpen}
        onClose={() => setMobileOpen(false)}
      />
      <div className="flex-1 min-w-0 h-screen overflow-hidden flex flex-col relative z-[1] lg:pl-[270px]">
        <TopHeader
          fullName={fullName}
          avatarUrl={avatarUrl}
          memberships={memberships}
          activeOrgId={activeOrgId}
          isKccAdmin={isKccAdmin}
          userId={userId}
          initialUnreadCount={initialUnreadCount}
          locale={locale}
          role={role}
          notificationPreferences={notificationPreferences}
          onMenuToggle={() => setMobileOpen((v) => !v)}
          showSearch={showSearch}
        />
        <AttentionCenter userId={userId} locale={locale} soundEnabled={notificationPreferences.soundEnabled} motionEnabled={notificationPreferences.motionEnabled} />
        <main className="app-workspace-scroll flex-1 min-h-0 overflow-y-auto overscroll-contain px-4 py-5 sm:px-6 lg:px-7 xl:px-8 lg:py-7 pb-24 w-full">
          <div className="w-full max-w-[1680px] mx-auto">
          {children}
          </div>
        </main>
      </div>
    </div>
  );
}
