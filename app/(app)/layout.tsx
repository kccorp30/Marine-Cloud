import { redirect } from "next/navigation";
import { getSessionContext } from "@/lib/auth/session";
import { getActiveOrganizationId } from "@/lib/auth/active-org";
import { getUnreadNotificationCount } from "@/lib/notifications/data";
import { getLocale } from "@/lib/i18n/server";
import { AppShell } from "@/components/layout/AppShell";
import { SyncStatus } from "@/components/technician/SyncStatus";

export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const session = await getSessionContext();
  // Every workspace uses durable email + password access after activation.
  // A user authenticated only through an invitation/recovery link cannot
  // enter an operational panel until a password has been established.
  if (!session.passwordSetupComplete)
    redirect("/reset-password?welcome=1&next=/welcome");
  if (!session.profileSetupComplete && !session.isKccAdmin)
    redirect("/welcome");
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const unreadCount = await getUnreadNotificationCount();
  const locale = await getLocale();

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
      >
        {children}
      </AppShell>
      <SyncStatus />
    </>
  );
}
