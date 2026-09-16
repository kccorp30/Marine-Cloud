import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { createServiceRequest } from '@/lib/service-requests/actions';
import { Card, PageTitle, Field, inputClass, SubmitButton } from '@/components/ui/primitives';
import { MediaActionForm } from '@/components/media/MediaActionForm';
import { MultiImagePicker } from '@/components/media/MultiImagePicker';

export default async function RequestServicePage({
  searchParams,
}: {
  searchParams: Promise<{ vesselId?: string }>;
}) {
  const { vesselId } = await searchParams;
  const session = await getSessionContext();
  const supabase = await createClient();

  const { data: customer } = await supabase.from('customers').select('id').eq('profile_id', session.userId).maybeSingle();
  const { data: vessels } = customer
    ? await supabase.from('vessels').select('id, name, make, model').eq('current_customer_id', customer.id)
    : { data: [] };

  return (
    <div className="max-w-lg">
      <PageTitle>Request Service</PageTitle>
      <p className="text-xs text-cool-gray mb-6">
        Tell us what&apos;s going on and we&apos;ll follow up to confirm the details.
      </p>

      <Card>
        <MediaActionForm action={createServiceRequest} className="space-y-4">
          <Field label="Vessel">
            <select name="vesselId" required defaultValue={vesselId ?? ''} className={inputClass}>
              <option value="">Select…</option>
              {(vessels ?? []).map((v) => (
                <option key={v.id} value={v.id} className="bg-navy">
                  {v.name || `${v.make ?? ''} ${v.model ?? ''}`.trim() || 'Unnamed Vessel'}
                </option>
              ))}
            </select>
          </Field>

          <Field label="Service Category">
            <select name="serviceCategory" className={inputClass} defaultValue="">
              <option value="" className="bg-navy">Not sure / general</option>
              <option value="electrical" className="bg-navy">Electrical</option>
              <option value="electronics" className="bg-navy">Electronics &amp; Navigation</option>
              <option value="diagnostics" className="bg-navy">Diagnostics</option>
              <option value="installation" className="bg-navy">New Installation</option>
              <option value="other" className="bg-navy">Other</option>
            </select>
          </Field>

          <Field label="What's the issue?">
            <input name="title" required placeholder="e.g. No power at the helm" className={inputClass} />
          </Field>

          <Field label="Details (optional)">
            <textarea name="description" rows={4} className={inputClass} />
          </Field>

          <Field label="How urgent is this?">
            <select name="urgency" className={inputClass} defaultValue="normal">
              <option value="low" className="bg-navy">Low — whenever is convenient</option>
              <option value="normal" className="bg-navy">Normal</option>
              <option value="high" className="bg-navy">High</option>
              <option value="urgent" className="bg-navy">Urgent</option>
            </select>
          </Field>

          <div className="grid grid-cols-2 gap-4">
            <Field label="Preferred date (optional)">
              <input name="preferredDate" type="date" className={inputClass} />
            </Field>
            <Field label="Preferred window (optional)">
              <input name="preferredWindow" placeholder="e.g. mornings" className={inputClass} />
            </Field>
          </div>

          <MultiImagePicker label="Add photos of the issue" hint="Show us the boat, system, damage or warning screen · up to 5 photos" />

          <div className="rounded-xl border border-cyan-300/15 bg-cyan-300/[0.04] p-4 text-xs text-cool-gray leading-relaxed">
            <strong className="text-cyan-100">✦ Luz tip:</strong> Clear photos help the team understand the problem before arriving and can be reused in your estimate.
          </div>
          <SubmitButton>Submit Request</SubmitButton>
        </MediaActionForm>
      </Card>
    </div>
  );
}
