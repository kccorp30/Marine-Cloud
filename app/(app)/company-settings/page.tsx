import {ActionForm} from '@/components/ui/ActionForm';
import { UiText } from "@/components/ui/UiText";
import { CompanyLogoForm } from "@/components/auth/CompanyLogoForm";
import { createClient } from "@/lib/supabase/server";
import { getSessionContext } from "@/lib/auth/session";
import { getActiveOrganizationId } from "@/lib/auth/active-org";
import {
  updateCompanyProfile,
  updateCompanySettings,
  createLocation,
} from "@/lib/company/settings-actions";
import { updatePaymentSettingsAction } from "@/lib/invoices/actions";
import { updateEmailSettingsAction } from "@/lib/communications/actions";
import {
  Card,
  PageTitle,
  Field,
  inputClass,
  SubmitButton,
} from "@/components/ui/primitives";

export default async function CompanySettingsPage() {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const actorRole = session.memberships.find(
    (m) => m.organization_id === activeOrgId,
  )?.role;
  const canManage = ["company_owner", "company_admin", "manager"].includes(
    actorRole ?? "",
  );

  const supabase = await createClient();
  const [
    { data: org },
    { data: settings },
    { data: locations },
    { data: paymentSettings },
    { data: emailSettings },
  ] = await Promise.all([
    supabase
      .from("organizations")
      .select("name, phone, email")
      .eq("id", activeOrgId)
      .maybeSingle(),
    supabase
      .from("organization_settings")
      .select("timezone, currency, locale, units_system")
      .eq("organization_id", activeOrgId)
      .maybeSingle(),
    supabase
      .from("organization_locations")
      .select("id, name, address, marina_name, is_primary")
      .eq("organization_id", activeOrgId)
      .order("is_primary", { ascending: false }),
    supabase
      .from("organization_payment_settings")
      .select("*")
      .eq("organization_id", activeOrgId)
      .maybeSingle(),
    supabase
      .from("organization_email_settings")
      .select("*")
      .eq("organization_id", activeOrgId)
      .maybeSingle(),
  ]);

  if (!canManage) {
    return (
      <div className="max-w-2xl">
        <PageTitle>
          {" "}
          <UiText text="Company Settings" />{" "}
        </PageTitle>
        <p className="text-sm text-cool-gray">
          {" "}
          <UiText text="Only company owners and admins can view and edit these settings." />{" "}
        </p>
      </div>
    );
  }

  return (
    <div className="max-w-2xl space-y-8">
      <PageTitle>
        {" "}
        <UiText text="Company Settings" />{" "}
      </PageTitle>
      {["company_owner", "company_admin"].includes(actorRole || "") && (
        <CompanyLogoForm />
      )}

      <Card>
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">
          {" "}
          <UiText text="Company Profile" />{" "}
        </div>
        <form action={updateCompanyProfile} className="space-y-3">
          <Field label="Display Name">
            <input
              name="name"
              defaultValue={org?.name ?? ""}
              className={inputClass}
            />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Phone">
              <input
                name="phone"
                defaultValue={org?.phone ?? ""}
                className={inputClass}
              />
            </Field>
            <Field label="Email">
              <input
                name="email"
                type="email"
                defaultValue={org?.email ?? ""}
                className={inputClass}
              />
            </Field>
          </div>
          <SubmitButton>
            {" "}
            <UiText text="Save Profile" />{" "}
          </SubmitButton>
        </form>
      </Card>

      <Card>
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">
          {" "}
          <UiText text="Regional Settings" />{" "}
        </div>
        <form action={updateCompanySettings} className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Timezone">
              <input
                name="timezone"
                defaultValue={settings?.timezone ?? ""}
                className={inputClass}
              />
            </Field>
            <Field label="Currency">
              <input
                name="currency"
                defaultValue={settings?.currency ?? ""}
                className={inputClass}
              />
            </Field>
            <Field label="Locale">
              <input
                name="locale"
                defaultValue={settings?.locale ?? ""}
                className={inputClass}
              />
            </Field>
            <Field label="Units">
              <select
                name="unitsSystem"
                defaultValue={settings?.units_system ?? "imperial"}
                className={inputClass}
              >
                <option value="imperial" className="bg-navy">
                  {" "}
                  <UiText text="Imperial" />{" "}
                </option>
                <option value="metric" className="bg-navy">
                  {" "}
                  <UiText text="Metric" />{" "}
                </option>
              </select>
            </Field>
          </div>
          <SubmitButton>
            {" "}
            <UiText text="Save Settings" />{" "}
          </SubmitButton>
        </form>
      </Card>

      <div>
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">
          {" "}
          <UiText text="Locations" />{" "}
        </div>
        <div className="space-y-2 mb-4">
          {(locations ?? []).map((l) => (
            <Card key={l.id} className="flex items-center justify-between">
              <div>
                <span className="text-sm">{l.name}</span>
                {l.is_primary && (
                  <span className="ml-2 font-mono text-[9px] uppercase text-gold">
                    {" "}
                    <UiText text="Primary" />{" "}
                  </span>
                )}
                {l.address && (
                  <div className="text-xs text-cool-gray mt-0.5">
                    {l.address}
                  </div>
                )}
              </div>
            </Card>
          ))}
          {(!locations || locations.length === 0) && (
            <p className="text-sm text-cool-gray">
              {" "}
              <UiText text="No locations added yet." />{" "}
            </p>
          )}
        </div>
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">
            {" "}
            <UiText text="Add Location" />{" "}
          </div>
          <form action={createLocation} className="space-y-3">
            <Field label="Name">
              <input name="name" required className={inputClass} />
            </Field>
            <Field label="Address (optional)">
              <input name="address" className={inputClass} />
            </Field>
            <Field label="Marina Name (optional)">
              <input name="marinaName" className={inputClass} />
            </Field>
            <SubmitButton>
              {" "}
              <UiText text="Add Location" />{" "}
            </SubmitButton>
          </form>
        </Card>
      </div>

      <div>
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">
          {" "}
          <UiText text="Payment Settings" />{" "}
        </div>
        <Card>
          <form action={updatePaymentSettingsAction} className="space-y-4">
            <input
              type="hidden"
              name="organizationId"
              value={activeOrgId ?? ""}
            />
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                name="depositRequired"
                defaultChecked={paymentSettings?.deposit_required ?? false}
              />{" "}
              <UiText text="Require a deposit before final billing" />{" "}
            </label>
            <div className="grid grid-cols-2 gap-3">
              <Field label="Deposit Type">
                <select
                  name="depositType"
                  defaultValue={paymentSettings?.deposit_type ?? "percentage"}
                  className={inputClass}
                >
                  <option value="percentage" className="bg-navy">
                    {" "}
                    <UiText text="Percentage" />{" "}
                  </option>
                  <option value="fixed_amount" className="bg-navy">
                    {" "}
                    <UiText text="Fixed Amount" />{" "}
                  </option>
                </select>
              </Field>
              <Field label="Deposit Value">
                <input
                  name="depositValue"
                  type="number"
                  step="0.01"
                  defaultValue={paymentSettings?.deposit_value ?? 0}
                  className={inputClass}
                />
              </Field>
            </div>
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                name="requireDepositBeforeStart"
                defaultChecked={
                  paymentSettings?.require_deposit_before_start ?? false
                }
              />{" "}
              <UiText text="Require deposit satisfied before work starts" />{" "}
            </label>
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                name="manualPaymentsEnabled"
                defaultChecked={
                  paymentSettings?.manual_payments_enabled ?? true
                }
              />{" "}
              <UiText text="Accept manual payments (cash, Zelle, etc.)" />{" "}
            </label>

            <div>
              <div className="text-xs text-cool-gray mb-2">
                {" "}
                <UiText text="Accepted Methods" />{" "}
              </div>
              <div className="flex gap-4 flex-wrap">
                {["cash", "zelle", "bank_transfer", "check"].map((m) => (
                  <label key={m} className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      name="acceptedMethods"
                      value={m}
                      defaultChecked={
                        paymentSettings?.accepted_payment_methods?.includes(
                          m,
                        ) ?? true
                      }
                    />
                    {m.replace("_", " ")}
                  </label>
                ))}
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <Field label="Zelle Recipient Name">
                <input
                  name="zelleRecipientName"
                  defaultValue={paymentSettings?.zelle_recipient_name ?? ""}
                  className={inputClass}
                />
              </Field>
              <Field label="Zelle Contact">
                <input
                  name="zelleContact"
                  defaultValue={paymentSettings?.zelle_contact ?? ""}
                  className={inputClass}
                />
              </Field>
            </div>
            <Field label="Zelle Instructions">
              <input
                name="zelleInstructions"
                defaultValue={paymentSettings?.zelle_instructions ?? ""}
                className={inputClass}
              />
            </Field>
            <Field label="Bank Transfer Instructions">
              <input
                name="bankTransferInstructions"
                defaultValue={paymentSettings?.bank_transfer_instructions ?? ""}
                className={inputClass}
              />
            </Field>
            <Field label="Cash Instructions">
              <input
                name="cashInstructions"
                defaultValue={paymentSettings?.cash_instructions ?? ""}
                className={inputClass}
              />
            </Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label="Check Payable To">
                <input
                  name="checkPayableTo"
                  defaultValue={paymentSettings?.check_payable_to ?? ""}
                  className={inputClass}
                />
              </Field>
              <Field label="Check Instructions">
                <input
                  name="checkInstructions"
                  defaultValue={paymentSettings?.check_instructions ?? ""}
                  className={inputClass}
                />
              </Field>
            </div>
            <p className="text-[10px] text-cool-gray">
              {" "}
              <UiText text="Online card payments via Stripe are not yet available in this version — manual payment methods above cover collection today." />{" "}
            </p>
            <SubmitButton>
              {" "}
              <UiText text="Save Payment Settings" />{" "}
            </SubmitButton>
          </form>
        </Card>
      </div>

      <div>
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">
          {" "}
          <UiText text="Email Identity" />{" "}
        </div>
        <Card>
          <ActionForm action={updateEmailSettingsAction} className="space-y-4">
            <input
              type="hidden"
              name="organizationId"
              value={activeOrgId ?? ""}
            />
            <div className="grid grid-cols-2 gap-3">
              <Field label="Display Name">
                <input
                  name="senderName"
                  defaultValue={emailSettings?.sender_name ?? ""}
                  placeholder={org?.name ?? ""}
                  className={inputClass}
                />
              </Field>
              <Field label="Reply-To Email">
                <input
                  name="replyToEmail"
                  type="email"
                  defaultValue={emailSettings?.reply_to_email ?? ""}
                  className={inputClass}
                />
              </Field>
            </div>
            <Field label="Signature">
              <textarea
                name="signatureText"
                rows={3}
                defaultValue={emailSettings?.signature_text ?? ""}
                placeholder={`${org?.name ?? ""}\n${org?.phone ?? ""}`}
                className={inputClass}
              />
            </Field>
            <div className="text-[10px] font-mono uppercase text-cool-gray">
              {" "}
              <UiText text="Sending address:" />{" "}
              {emailSettings?.sender_email ?? "not yet verified"}{" "}
              <UiText text="· Status:" />{" "}
              {emailSettings?.verification_status ?? "unverified"}
            </div>
            <p className="text-[10px] text-cool-gray">
              {" "}
              <UiText text="The sending address and its verification are managed by KCC platform staff and cannot be self-configured, to prevent one company from impersonating another. Contact KCC to set up a verified sending domain." />{" "}
            </p>
            <SubmitButton>
              {" "}
              <UiText text="Save Email Identity" />{" "}
            </SubmitButton>
          </ActionForm>
        </Card>
      </div>
    </div>
  );
}
