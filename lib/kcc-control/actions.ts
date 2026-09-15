"use server";

import { BILLING_PAUSED } from "@/lib/launch/config";
import { getLaunchPlan } from "@/lib/launch/plan";
import { getSessionContext } from "@/lib/auth/session";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { logger } from "@/lib/logger";
import { deliverOrganizationInvitation } from "@/lib/auth/invitations";

export async function createOrganizationAction(formData: FormData) {
  const supabase = await createClient();
  const session = await getSessionContext();
  if (!session.isKccAdmin)
    return { error: "KCC administrator access required." };
  const launchPlan = BILLING_PAUSED ? await getLaunchPlan(supabase) : null;
  if (launchPlan && "error" in launchPlan) return { error: launchPlan.error };
  const noTrial = formData.get("noTrial") === "on";
  const complimentary =
    BILLING_PAUSED || formData.get("complimentary") === "on";
  const trialDaysRaw = formData.get("trialDays") as string;

  const { data: orgId, error } = await supabase.rpc(
    "create_organization_with_commercial_setup",
    {
      p_name: formData.get("name") as string,
      p_plan_id: launchPlan?.id || (formData.get("planId") as string),
      p_billing_cycle: BILLING_PAUSED
        ? "custom"
        : (formData.get("billingCycle") as string) || "weekly",
      p_legal_name: (formData.get("legalName") as string) || null,
      p_slug: (formData.get("slug") as string) || null,
      p_timezone: (formData.get("timezone") as string) || "America/New_York",
      p_currency: (formData.get("currency") as string) || "USD",
      p_locale: (formData.get("locale") as string) || "en",
      p_location_name: (formData.get("locationName") as string) || null,
      p_location_address: (formData.get("locationAddress") as string) || null,
      p_owner_email: (formData.get("ownerEmail") as string) || null,
      // Commercial Setup — todo o nada junto con la organización, nunca
      // un segundo paso separado que pueda dejar la compañía en un
      // estado comercial ambiguo.
      p_trial_days:
        noTrial || complimentary
          ? null
          : trialDaysRaw
            ? Number(trialDaysRaw)
            : null,
      p_price_override: null,
      p_complimentary: complimentary,
      p_complimentary_reason: BILLING_PAUSED
        ? "Initial operational launch. Platform billing paused by KCC."
        : complimentary
          ? (formData.get("complimentaryReason") as string)
          : null,
      p_custom_terms: (formData.get("customTerms") as string) || null,
    },
  );
  if (error || !orgId) {
    logger.warn("createOrganizationAction failed", { message: error?.message });
    return { error: error?.message ?? "Could not create organization" };
  }
  const ownerEmail = String(formData.get("ownerEmail") || "").trim().toLowerCase();
  let invitationId: string | undefined;
  let emailSent: boolean | undefined;
  let emailError: string | undefined;

  // create_organization_with_commercial_setup() creates the pending owner
  // invitation atomically with the company, but external email delivery must
  // happen only AFTER the database transaction has committed successfully.
  if (ownerEmail) {
    const { data: invitation } = await supabase
      .from("organization_invitations")
      .select("id")
      .eq("organization_id", orgId)
      .eq("email", ownerEmail)
      .eq("intended_role", "company_owner")
      .eq("status", "pending")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    invitationId = invitation?.id;
    if (!invitationId) {
      emailSent = false;
      emailError = "Company created, but the owner invitation could not be located. Use Resend Invitation from the company page.";
    } else {
      const reissued = await supabase.rpc("reissue_invitation_token", {
        p_invitation_id: invitationId,
      });
      const rawToken = reissued.data?.[0]?.raw_token as string | undefined;
      if (reissued.error || !rawToken) {
        emailSent = false;
        emailError = reissued.error?.message || "Company created, but the invitation token could not be prepared.";
      } else {
        const delivery = await deliverOrganizationInvitation({
          email: ownerEmail,
          rawToken,
          organizationName: String(formData.get("name") || "").trim(),
          role: "company_owner",
        });
        emailSent = delivery.success;
        emailError = delivery.success ? undefined : delivery.error;
      }
    }
  }

  revalidatePath("/companies");
  revalidatePath(`/companies/${orgId}`);
  return { organizationId: orgId, invitationId, emailSent, emailError };
}

export async function setOrganizationStatusAction(
  organizationId: string,
  status: string,
) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_organization_status", {
    p_organization_id: organizationId,
    p_status: status,
  });
  if (error) {
    logger.warn("setOrganizationStatusAction failed", {
      message: error.message,
    });
    return { error: error.message };
  }
  revalidatePath("/companies");
  revalidatePath(`/companies/${organizationId}`);
  return {};
}

export async function changeMemberRoleAction(formData: FormData) {
  const supabase = await createClient();
  const membershipId = formData.get("membershipId") as string;
  const organizationId = formData.get("organizationId") as string;
  const { error } = await supabase.rpc("change_member_role", {
    p_membership_id: membershipId,
    p_new_role: formData.get("newRole") as string,
  });
  if (error) {
    logger.warn("changeMemberRoleAction failed", { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  return {};
}

export async function createCompensationAgreementAction(formData: FormData) {
  const supabase = await createClient();
  const organizationId = formData.get("organizationId") as string;
  const compensationType = formData.get("compensationType") as string;
  const { error } = await supabase.rpc("create_compensation_agreement", {
    p_organization_id: organizationId,
    p_compensation_type: compensationType,
    p_percentage_rate:
      compensationType === "percentage"
        ? Number(formData.get("percentageRate"))
        : null,
    p_fixed_amount:
      compensationType === "fixed" ? Number(formData.get("fixedAmount")) : null,
    p_currency: (formData.get("currency") as string) || "USD",
    p_effective_from:
      (formData.get("effectiveFrom") as string) ||
      new Date().toISOString().slice(0, 10),
    p_effective_until: (formData.get("effectiveUntil") as string) || null,
    p_notes: (formData.get("notes") as string) || null,
  });
  if (error) {
    logger.warn("createCompensationAgreementAction failed", {
      message: error.message,
    });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  return {};
}

export async function deactivateCompensationAgreementAction(
  agreementId: string,
  organizationId: string,
) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("deactivate_compensation_agreement", {
    p_agreement_id: agreementId,
  });
  if (error) {
    logger.warn("deactivateCompensationAgreementAction failed", {
      message: error.message,
    });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  return {};
}
