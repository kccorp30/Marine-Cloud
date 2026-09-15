import Link from 'next/link';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getInvoiceList } from '@/lib/invoices/data';
import { Card, PageTitle, Field, inputClass, SubmitButton } from '@/components/ui/primitives';

const STATUS_OPTIONS = ['draft', 'issued', 'sent', 'partially_paid', 'paid', 'overdue', 'void'];

const STATUS_COLOR: Record<string, string> = {
  draft: 'text-cool-gray',
  issued: 'text-gold',
  sent: 'text-gold',
  partially_paid: 'text-gold',
  paid: 'text-emerald-400',
  overdue: 'text-red-400',
  void: 'text-cool-gray/60',
};

const TYPE_LABEL: Record<string, string> = {
  deposit: 'Deposit / Initial Payment',
  final: 'Remaining Balance / Final',
  progress: 'Progress Billing',
  standalone: 'Invoice',
};

export default async function InvoicesListPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const { status } = await searchParams;
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const actorRole = session.memberships.find((m) => m.organization_id === activeOrgId)?.role;
  const isCustomer = actorRole === 'customer';

  const invoices = await getInvoiceList(activeOrgId!, { status });

  return (
    <div className="max-w-4xl space-y-6">
      <PageTitle>Invoices</PageTitle>

      {!isCustomer && (
        <form method="GET" className="flex gap-3 flex-wrap items-end">
          <div className="min-w-[160px]">
            <Field label="Status">
              <select name="status" defaultValue={status ?? ''} className={inputClass}>
                <option value="">All</option>
                {STATUS_OPTIONS.map((s) => (
                  <option key={s} value={s} className="bg-navy">
                    {s.replace('_', ' ')}
                  </option>
                ))}
              </select>
            </Field>
          </div>
          <SubmitButton>Filter</SubmitButton>
          {status && (
            <Link href="/invoices" className="text-[10px] font-mono uppercase text-cool-gray hover:text-gold pb-2.5">
              Clear
            </Link>
          )}
        </form>
      )}

      <div className="space-y-2">
        {invoices.map((inv) => (
          <Link key={inv.id} href={`/invoices/${inv.id}`}>
            <Card className="flex items-center justify-between flex-wrap gap-2 hover:border-gold/40 transition-colors">
              <div>
                <div className="text-sm font-semibold">{inv.invoiceNumber}</div>
                <div className="text-xs text-cool-gray mt-0.5">
                  {TYPE_LABEL[inv.invoiceType] ?? inv.invoiceType}
                  {!isCustomer && inv.customerName && ` · ${inv.customerName}`}
                  {inv.vesselName && ` · ${inv.vesselName}`}
                </div>
              </div>
              <div className="text-right">
                <div className="text-sm font-mono">${inv.total.toFixed(2)}</div>
                {inv.balanceDue > 0 && inv.status !== 'draft' && inv.status !== 'void' && (
                  <div className="text-[10px] text-cool-gray">${inv.balanceDue.toFixed(2)} due</div>
                )}
                <span className={`font-mono text-[9px] uppercase ${STATUS_COLOR[inv.status] ?? 'text-cool-gray'}`}>{inv.status.replace('_', ' ')}</span>
              </div>
            </Card>
          </Link>
        ))}
        {invoices.length === 0 && <p className="text-sm text-cool-gray">No invoices yet.</p>}
      </div>
    </div>
  );
}
