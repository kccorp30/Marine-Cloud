import Link from 'next/link';
import type { TechnicianPaySnapshot } from '@/lib/payroll/technician-summary';

export function TechnicianPayCard({ snapshot, locale, profileId }: { snapshot: TechnicianPaySnapshot; locale: 'en' | 'es'; profileId: string }) {
  const es = locale === 'es';
  const money = new Intl.NumberFormat(locale, { style: 'currency', currency: snapshot.currency }).format(snapshot.unpaidAmount);
  return (
    <section className="premium-card rounded-2xl p-5 relative overflow-hidden">
      <div className="absolute -right-14 -top-20 w-48 h-48 rounded-full bg-emerald-300/[.06] blur-3xl" />
      <div className="relative flex justify-between gap-4 items-start">
        <div>
          <p className="eyebrow">{es ? 'MI JORNADA Y PAGO' : 'MY WORKDAY & PAY'}</p>
          <h2 className="text-xl font-semibold mt-2">{snapshot.currentShift ? (snapshot.currentShift.pausedAt ? (es ? 'Jornada en pausa' : 'Workday paused') : (es ? 'Jornada activa' : 'Workday active')) : (es ? 'Fuera de jornada' : 'Off shift')}</h2>
          <p className="text-xs text-cool-gray mt-2">{snapshot.payRate == null ? (es ? 'La compañía debe configurar tus condiciones de pago.' : 'Your company needs to configure your pay terms.') : `${snapshot.payType === 'daily' ? (es ? 'Por día' : 'Daily') : (es ? 'Por hora' : 'Hourly')} · ${new Intl.NumberFormat(locale,{style:'currency',currency:snapshot.currency}).format(snapshot.payRate)} · ${snapshot.payCycle ?? ''}`}</p>
        </div>
        <span className="text-emerald-200 text-xs">{snapshot.currentShift ? '● LIVE' : '○'}</span>
      </div>
      <div className="relative grid grid-cols-2 gap-3 mt-5">
        <div className="rounded-xl bg-white/[.035] border border-white/[.07] p-4"><p className="command-kicker">{es ? 'Pendiente de pago' : 'Pending pay'}</p><p className="text-2xl font-semibold mt-2">{money}</p><p className="text-xs text-cool-gray mt-1">{snapshot.unpaidShifts} {es ? 'jornada(s)' : 'workday(s)'}</p></div>
        <div className="rounded-xl bg-white/[.035] border border-white/[.07] p-4"><p className="command-kicker">{es ? 'Último pago' : 'Last payment'}</p><p className="text-base font-semibold mt-2">{snapshot.lastPaidAt ? new Date(snapshot.lastPaidAt).toLocaleDateString(locale) : '—'}</p><p className="text-xs text-cool-gray mt-1">{es ? 'Historial protegido por compañía' : 'Company-scoped history'}</p></div>
      </div>
      <Link href={`/team/${profileId}`} className="relative mt-4 inline-flex text-sm text-gold">{es ? 'Ver horas, jornadas y pagos' : 'View hours, shifts & payments'} →</Link>
    </section>
  );
}
