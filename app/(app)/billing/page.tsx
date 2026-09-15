import {MonthlyCharges} from '@/components/launch/MonthlyCharges';
import { BILLING_PAUSED } from "@/lib/launch/config";
import { commandCopy } from "@/lib/i18n/command-copy";
import { getLocale } from "@/lib/i18n/server";
import { redirect } from "next/navigation";
import { getSessionContext } from "@/lib/auth/session";
import { getActiveOrganizationId } from "@/lib/auth/active-org";
import {
  getCurrentSubscription,
  getPublicPlans,
} from "@/lib/subscriptions/data";
import { getTrialCountdownLabel } from "@/lib/subscriptions/trial-countdown";
import { PageTitle, Card } from "@/components/ui/primitives";
import { PlanSelector } from "@/components/subscriptions/PlanSelector";

const STATUS_LABEL: Record<string, string> = {
  trialing: "Trial",
  active: "Active",
  trial_expired: "Trial Expired",
  past_due: "Past Due",
  grace_period: "Grace Period",
  cancelled: "Cancelled",
  complimentary: "Complimentary",
};

export default async function BillingPage() {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const activeMembership = session.memberships.find(
    (m) => m.organization_id === activeOrgId,
  );
  const actorRole = session.isKccAdmin ? "kcc_admin" : activeMembership?.role;

  // Solo owner/admin de la company ven billing — nunca customer/
  // technician, y kcc_admin gestiona esto desde /companies/[id].
  if (!["company_owner", "company_admin"].includes(actorRole ?? "")) {
    redirect("/dashboard");
  }
  if (!activeOrgId) redirect("/dashboard");

  const subscription = await getCurrentSubscription(activeOrgId);
  if (BILLING_PAUSED) {
    const locale = await getLocale(); const es = locale === 'es';
    return <div className="premium-card p-6 rounded-2xl max-w-xl"><h1 className="text-2xl mb-4">{es?'Cuenta de la compañía':'Company account'}</h1>{subscription?.billingCycle==='monthly' && !subscription.complimentary && subscription.priceSnapshot!=null ? <><p className="text-3xl text-gold">{new Intl.NumberFormat(locale,{style:'currency',currency:subscription.currency}).format(subscription.priceSnapshot)} <small className="text-sm">/ {es?'mes':'month'}</small></p><p className="mt-4 text-cool-gray">{subscription.customTerms}</p><p className="mt-3">{es?'Pago coordinado directamente con KCC.':'Payment arranged directly with KCC.'}</p></>:<p>{es?'Contacta a KCC para consultar tus condiciones de acceso.':'Contact KCC to review your access terms.'}</p>}<div className="mt-5"><MonthlyCharges organizationId={activeOrgId}/></div></div>;
  }
  const trialLabel =
    subscription?.effectiveStatus === "trialing"
      ? getTrialCountdownLabel(subscription.trialEndsAt)
      : null;

  // El plan puede elegirse cuando el trial venció sin un plan pre-
  // determinado, o cuando no hay ninguna suscripción todavía — nunca
  // se ofrece elegir un plan custom/complimentary/oculto.
  const canChoosePlan =
    !subscription ||
    subscription.effectiveStatus === "trial_expired" ||
    subscription.effectiveStatus === "cancelled";
  const publicPlans = canChoosePlan ? await getPublicPlans() : [];

  return (
    <div className="max-w-xl space-y-6">
      <PageTitle>Billing & Subscription</PageTitle>

      {!subscription && (
        <Card>
          <p className="text-sm text-cool-gray">
            No subscription has been set up for your account yet. Contact KCC to
            get started.
          </p>
        </Card>
      )}

      {subscription && (
        <Card className="space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium">{subscription.planName}</span>
            <span className="font-mono text-[9px] uppercase text-gold">
              {STATUS_LABEL[subscription.effectiveStatus] ??
                subscription.effectiveStatus}
            </span>
          </div>

          {trialLabel && <p className="text-xs text-amber-400">{trialLabel}</p>}
          {subscription.effectiveStatus === "trial_expired" && (
            <p className="text-xs text-red-400">
              Your trial has ended. Choose a plan below to restore full access.
            </p>
          )}
          {subscription.effectiveStatus === "cancelled" && (
            <p className="text-xs text-red-400">
              Your subscription was cancelled. Your data remains safe — choose a
              plan to reactivate.
            </p>
          )}
          {subscription.effectiveStatus === "grace_period" &&
            subscription.gracePeriodEndsAt && (
              <p className="text-xs text-amber-400">
                You're in a grace period until{" "}
                {new Date(subscription.gracePeriodEndsAt).toLocaleDateString()}.
              </p>
            )}

          <div className="text-xs text-cool-gray space-y-1">
            <div>Billing cycle: {subscription.billingCycle}</div>
            {subscription.complimentary ? (
              <div>Complimentary access — no charge</div>
            ) : (
              subscription.priceSnapshot !== null && (
                <div>
                  Price: {subscription.currency} {subscription.priceSnapshot} /{" "}
                  {subscription.billingCycle}
                </div>
              )
            )}
            {subscription.customTerms && (
              <div>Commercial notes: {subscription.customTerms}</div>
            )}
          </div>
        </Card>
      )}

      {canChoosePlan && publicPlans.length > 0 && (
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">
            Choose Your Plan
          </div>
          <PlanSelector organizationId={activeOrgId} plans={publicPlans} />
        </Card>
      )}
    </div>
  );
}
