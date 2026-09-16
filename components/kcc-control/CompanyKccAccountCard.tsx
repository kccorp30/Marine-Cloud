import Link from 'next/link';
import type { KccAccountSummary } from '@/lib/company/kcc-account';

function money(value: number, currency: string, locale: string) {
  return new Intl.NumberFormat(locale, { style: 'currency', currency }).format(Number(value || 0));
}

export function CompanyKccAccountCard({ summary, locale }: { summary: KccAccountSummary; locale: 'en' | 'es' }) {
  const es = locale === 'es';
  const a = summary.agreement;
  const b = summary.balance;
  const agreementLabel = !a
    ? (es ? 'Sin acuerdo activo' : 'No active agreement')
    : a.compensation_type === 'percentage'
      ? `${a.percentage_rate ?? 0}%`
      : money(Number(a.fixed_amount ?? 0), a.currency || b.currency || 'USD', locale);
  const due = b.next_due_at ? new Date(b.next_due_at) : null;
  const overdue = Number(b.overdue_charges || 0) > 0;

  return (
    <section className={`premium-card rounded-2xl p-5 overflow-hidden relative ${overdue ? 'border-amber-300/35' : ''}`}>
      <div className="absolute -right-20 -top-20 w-56 h-56 rounded-full bg-gold/[.06] blur-3xl pointer-events-none" />
      <div className="relative flex items-start justify-between gap-5">
        <div>
          <p className="eyebrow">KCC · {es ? 'ACUERDO Y SALDO' : 'AGREEMENT & BALANCE'}</p>
          <h2 className="text-xl font-semibold mt-2">{es ? 'Cuenta con KCC' : 'Your KCC account'}</h2>
          <p className="text-xs text-cool-gray mt-2 max-w-xl">
            {es ? 'Consulta el acuerdo vigente, el saldo abierto y la próxima fecha de pago desde tu panel principal.' : 'See the current agreement, open balance and next payment date directly from your main dashboard.'}
          </p>
        </div>
        <span className={`px-3 py-1.5 rounded-full text-[10px] uppercase tracking-[.12em] ${overdue ? 'bg-amber-300/15 text-amber-200 border border-amber-300/30' : 'bg-emerald-300/10 text-emerald-200 border border-emerald-300/20'}`}>
          {overdue ? (es ? 'Pago vencido' : 'Payment overdue') : (es ? 'Al día / pendiente' : 'Current / pending')}
        </span>
      </div>
      <div className="relative grid sm:grid-cols-3 gap-3 mt-5">
        <div className="rounded-xl bg-white/[.035] border border-white/[.07] p-4">
          <p className="command-kicker">{es ? 'Acuerdo vigente' : 'Current agreement'}</p>
          <p className="text-2xl font-semibold mt-2 text-gold">{agreementLabel}</p>
          {a?.notes && <p className="text-xs text-cool-gray mt-2 line-clamp-2">{a.notes}</p>}
        </div>
        <div className="rounded-xl bg-white/[.035] border border-white/[.07] p-4">
          <p className="command-kicker">{es ? 'Saldo abierto' : 'Open balance'}</p>
          <p className="text-2xl font-semibold mt-2">{money(Number(b.open_balance || 0), b.currency || 'USD', locale)}</p>
          <p className="text-xs text-cool-gray mt-2">{b.open_charges || 0} {es ? 'cargo(s) abierto(s)' : 'open charge(s)'}</p>
        </div>
        <div className="rounded-xl bg-white/[.035] border border-white/[.07] p-4">
          <p className="command-kicker">{es ? 'Próximo vencimiento' : 'Next due date'}</p>
          <p className="text-lg font-semibold mt-2">{due ? due.toLocaleDateString(locale, { month: 'short', day: 'numeric', year: 'numeric' }) : '—'}</p>
          <p className="text-xs text-cool-gray mt-2">{es ? 'Luz te recordará cuando requiera atención.' : 'Luz will remind you when attention is required.'}</p>
        </div>
      </div>
      <div className="relative mt-4 flex flex-wrap items-center gap-3">
        <Link href="/billing" className="command-button">{es ? 'Ver facturación KCC' : 'View KCC billing'} →</Link>
        {overdue && <span className="text-xs text-amber-200">✦ {es ? 'Luz: tienes un pago vencido que requiere revisión.' : 'Luz: an overdue payment needs your attention.'}</span>}
      </div>
    </section>
  );
}
