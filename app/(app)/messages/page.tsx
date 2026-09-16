import Link from 'next/link';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getConversationList } from '@/lib/communications/data';
import { startCustomerSupportAction } from '@/lib/communications/actions';
import { getLocale } from '@/lib/i18n/server';
import { MediaActionForm } from '@/components/media/MediaActionForm';
import { MultiImagePicker } from '@/components/media/MultiImagePicker';

export default async function CustomerMessagesPage() {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const locale = await getLocale();
  const es = locale === 'es';
  const supabase = await createClient();
  const { data: customer } = await supabase
    .from('customers')
    .select('id')
    .eq('profile_id', session.userId)
    .eq('organization_id', activeOrgId)
    .maybeSingle();

  const [conversations, vesselsResult] = await Promise.all([
    customer ? getConversationList(activeOrgId!, customer.id) : Promise.resolve([]),
    customer
      ? supabase.from('vessels').select('id,name,make,model,year').eq('organization_id', activeOrgId).eq('current_customer_id', customer.id).order('created_at', { ascending: false })
      : Promise.resolve({ data: [] as any[] }),
  ]);
  const vessels = vesselsResult.data ?? [];

  return (
    <div className="max-w-5xl space-y-6">
      <section className="support-hero">
        <div className="support-orb">✦</div>
        <div className="min-w-0 flex-1">
          <p className="eyebrow text-cyan-200">LUZ · {es ? 'ASISTENCIA MARINA' : 'MARINE SUPPORT'}</p>
          <h1 className="text-3xl sm:text-4xl font-semibold mt-2">{es ? '¿Cómo podemos ayudarte?' : 'How can we help?'}</h1>
          <p className="text-sm text-cool-gray mt-3 max-w-2xl leading-relaxed">
            {es
              ? 'Cuéntanos qué ocurre, selecciona la embarcación y el equipo recibirá una alerta prioritaria. Tu conversación quedará aquí para continuarla sin perder contexto.'
              : 'Tell us what is happening, choose the vessel and the team will receive a priority alert. Your conversation stays here so you can continue without losing context.'}
          </p>
        </div>
      </section>

      <section className="premium-card rounded-2xl p-5 sm:p-6">
        <div className="flex flex-wrap justify-between gap-3 items-center mb-5">
          <div><p className="command-kicker">{es ? 'NUEVA SOLICITUD DE ASISTENCIA' : 'NEW SUPPORT REQUEST'}</p><h2 className="text-xl font-semibold mt-1">{es ? 'Habla con el equipo' : 'Talk to the team'}</h2></div>
          <span className="text-xs text-emerald-200">● {es ? 'Canal seguro del portal' : 'Secure portal channel'}</span>
        </div>
        <MediaActionForm action={startCustomerSupportAction} className="grid md:grid-cols-2 gap-4">
          <label className="command-field">
            {es ? 'Embarcación' : 'Vessel'}
            <select name="vesselId" defaultValue="">
              <option value="">{es ? 'General / no aplica' : 'General / not applicable'}</option>
              {vessels.map((v:any) => <option key={v.id} value={v.id}>{v.name || [v.make,v.model,v.year].filter(Boolean).join(' ') || 'Vessel'}</option>)}
            </select>
          </label>
          <label className="command-field">
            {es ? 'Prioridad' : 'Priority'}
            <select name="urgency" defaultValue="normal"><option value="normal">{es ? 'Normal' : 'Normal'}</option><option value="urgent">{es ? 'Urgente' : 'Urgent'}</option></select>
          </label>
          <label className="command-field md:col-span-2">
            {es ? '¿Qué necesitas?' : 'What do you need?'}
            <input name="subject" required minLength={2} maxLength={180} placeholder={es ? 'Ej. Necesito ayuda con el sistema eléctrico' : 'e.g. I need help with the electrical system'} />
          </label>
          <label className="command-field md:col-span-2">
            {es ? 'Cuéntanos los detalles' : 'Tell us the details'}
            <textarea name="body" required minLength={2} maxLength={5000} rows={5} placeholder={es ? 'Describe qué ocurre, cuándo empezó y cualquier detalle que pueda ayudarnos.' : 'Describe what is happening, when it started and anything that can help us.'} />
          </label>
          <div className="md:col-span-2"><MultiImagePicker label={es ? 'Agregar fotos' : 'Add photos'} hint={es ? 'Fotos del barco, sistema, daño o pantalla de error · hasta 5' : 'Boat, system, damage or error screen · up to 5'} /></div>
          <div className="md:col-span-2 flex flex-wrap items-center gap-3">
            <button className="command-button" type="submit">{es ? 'Enviar a mi equipo' : 'Send to my team'} →</button>
            <span className="text-xs text-cool-gray">✦ {es ? 'Luz avisará a la compañía y mantendrá el contexto de la conversación.' : 'Luz will alert the company and keep the conversation context.'}</span>
          </div>
        </MediaActionForm>
      </section>

      <section className="premium-card rounded-2xl p-5 sm:p-6">
        <div className="flex justify-between gap-3 items-center mb-4"><h2 className="text-xl font-semibold">{es ? 'Mis conversaciones' : 'My conversations'}</h2><span className="text-xs text-cool-gray">{conversations.length}</span></div>
        <div className="space-y-2">
          {conversations.map((c) => (
            <Link key={c.id} href={`/communications/${c.id}`} className="support-thread">
              <span className="support-thread-icon">✦</span>
              <span className="min-w-0 flex-1">
                <strong className="block text-sm truncate">{c.subject ?? (es ? 'Conversación' : 'Conversation')}</strong>
                <small className="block text-cool-gray mt-1 truncate">{[c.vesselName,c.lastMessagePreview].filter(Boolean).join(' · ') || (es ? 'Abrir conversación' : 'Open conversation')}</small>
              </span>
              <span className="text-right shrink-0"><small className="block text-cool-gray">{c.lastMessageAt ? new Date(c.lastMessageAt).toLocaleDateString(locale) : ''}</small><span className="text-gold text-sm">→</span></span>
            </Link>
          ))}
          {conversations.length === 0 && (
            <div className="py-10 text-center"><span className="support-empty-icon">✦</span><p className="font-semibold mt-3">{es ? 'Aún no tienes conversaciones' : 'No conversations yet'}</p><p className="text-sm text-cool-gray mt-2">{es ? 'Usa el formulario de arriba y el equipo recibirá tu mensaje.' : 'Use the form above and your team will receive your message.'}</p></div>
          )}
        </div>
      </section>
    </div>
  );
}
