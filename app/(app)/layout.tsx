import { redirect } from "next/navigation";
import { getSessionContext } from "@/lib/auth/session";
import { getActiveOrganizationId } from "@/lib/auth/active-org";
import { getUnreadNotificationCount } from "@/lib/notifications/data";
import { getLocale } from "@/lib/i18n/server";
import { getNotificationPreferences } from "@/lib/notifications/preferences";
import { AppShell } from "@/components/layout/AppShell";
import { SyncStatus } from "@/components/technician/SyncStatus";

export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const session = await getSessionContext();
  // Only accounts explicitly provisioned through the NEW first-time invite
  // flow are gated here. Legacy/existing accounts must never be mistaken for
  // first-time users merely because password_set_at was introduced later.
  if (session.passwordSetupRequired && !session.passwordSetupComplete)
    redirect("/reset-password?welcome=1&next=/welcome");
  if (!session.profileSetupComplete && !session.isKccAdmin)
    redirect("/welcome");
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const unreadCount = await getUnreadNotificationCount();
  const locale = await getLocale();
  const notificationPreferences = await getNotificationPreferences();

  const activeMembership = session.memberships.find(
    (m) => m.organization_id === activeOrgId,
  );

  return (
    <>
      <AppShell
        fullName={session.fullName}
        avatarUrl={session.avatarUrl}
        memberships={session.memberships}
        activeOrgId={activeOrgId}
        isKccAdmin={session.isKccAdmin}
        userId={session.userId}
        initialUnreadCount={unreadCount}
        role={activeMembership?.role ?? ""}
        orgName={activeMembership?.organization.name ?? null}
        companyLogo={
          typeof activeMembership?.organization.branding_json?.logo_url ===
          "string"
            ? activeMembership.organization.branding_json.logo_url
            : null
        }
        locale={locale}
        notificationPreferences={notificationPreferences}
      >
        {children}
      </AppShell>
      <SyncStatus />
    </>
  );
}
