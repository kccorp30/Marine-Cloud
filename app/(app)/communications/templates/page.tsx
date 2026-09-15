import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getTemplates } from '@/lib/communications/data';
import { createTemplateAction } from '@/lib/communications/actions';
import { TemplateEditForm } from '@/components/communications/TemplateEditForm';
import { Card, PageTitle, Field, inputClass, SubmitButton } from '@/components/ui/primitives';

const CATEGORIES = [
  'estimate_ready', 'estimate_reminder', 'estimate_approved', 'estimate_declined',
  'invoice_ready', 'deposit_required', 'payment_received', 'balance_due',
  'appointment_confirmation', 'appointment_reminder', 'service_update', 'work_completed', 'general',
];

export default async function TemplatesPage() {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const templates = await getTemplates(activeOrgId!);

  return (
    <div className="max-w-2xl space-y-6">
      <PageTitle>Templates</PageTitle>

      <div className="space-y-2">
        {templates.map((t) => (
          <Card key={t.id} className={!t.isActive ? 'opacity-50' : ''}>
            <div className="flex items-center justify-between mb-1">
              <span className="text-sm font-semibold">{t.name}</span>
              <span className="font-mono text-[9px] uppercase text-cool-gray">
                {t.category.replace('_', ' ')} · {t.language.toUpperCase()} {!t.isActive && '· inactive'}
              </span>
            </div>
            {t.subject && <p className="text-xs text-cool-gray mb-1">Subject: {t.subject}</p>}
            <p className="text-xs text-cool-gray whitespace-pre-wrap">{t.body}</p>
            <TemplateEditForm template={t} />
          </Card>
        ))}
        {templates.length === 0 && <p className="text-sm text-cool-gray">No templates yet.</p>}
      </div>

      <Card>
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">New Template</div>
        <form action={createTemplateAction} className="space-y-3">
          <input type="hidden" name="organizationId" value={activeOrgId ?? ''} />
          <Field label="Name">
            <input name="name" required className={inputClass} />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Category">
              <select name="category" required className={inputClass} defaultValue="general">
                {CATEGORIES.map((c) => (
                  <option key={c} value={c} className="bg-navy">
                    {c.replace('_', ' ')}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Language">
              <select name="language" required className={inputClass} defaultValue="en">
                <option value="en" className="bg-navy">English</option>
                <option value="es" className="bg-navy">Spanish</option>
              </select>
            </Field>
          </div>
          <Field label="Subject (optional)">
            <input name="subject" placeholder="Your estimate {{estimate.number}} is ready" className={inputClass} />
          </Field>
          <Field label="Body">
            <textarea name="body" required rows={5} placeholder="Hi {{customer.first_name}}, ..." className={inputClass} />
          </Field>
          <p className="text-[10px] text-cool-gray">
            Variables: {'{{customer.first_name}}'} {'{{company.name}}'} {'{{vessel.name}}'} {'{{estimate.number}}'} {'{{estimate.total}}'}{' '}
            {'{{invoice.number}}'} {'{{invoice.balance_due}}'} {'{{appointment.date}}'} {'{{technician.name}}'}
          </p>
          <SubmitButton>Create Template</SubmitButton>
        </form>
      </Card>
    </div>
  );
}
