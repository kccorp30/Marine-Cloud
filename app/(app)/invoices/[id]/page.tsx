import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { createClient } from '@/lib/supabase/server';
import { getInvoiceDetail } from '@/lib/invoices/data';
import { issueInvoiceAction } from '@/lib/invoices/actions';
import { RecordPaymentForm } from '@/components/invoices/RecordPaymentForm';
import { VoidInvoiceForm } from '@/components/invoices/VoidInvoiceForm';
import { SendInvoiceEmailButton } from '@/components/invoices/SendInvoiceEmailButton';
import { Card, PageTitle } from '@/components/ui/primitives';

const TYPE_LABEL: Record<string, string> = {
  deposit: 'Deposit / Initial Payment',
  final: 'Remaining Balance / Final Invoice',
  progress: 'Progress Billing',
  standalone: 'Invoice',
};

export default async function InvoiceDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const actorRole = session.memberships.find((m) => m.organization_id === activeOrgId)?.role;
  const isCustomer = actorRole === 'customer';
  const isStaff = ['company_owner', 'company_admin', 'manager', 'kcc_admin'].includes(actorRole ?? '');

  const invoice = await getInvoiceDetail(id);
  if (!invoice) notFound();

  const visibleLines = isCustomer ? invoice.lineItems.filter((l) => l.customerVisible) : invoice.lineItems;

  let paymentSettings: { accepted_payment_methods: string[]; zelle_recipient_name: string | null; zelle_contact: string | null; zelle_instructions: string | null; bank_transfer_instructions: string | null; cash_instructions: string | null; check_payable_to: string | null; check_instructions: string | null; stripe_connect_enabled: boolean } | null = null;
  if (isCustomer && invoice.balanceDue > 0) {
    const supabase = await createClient();
    const { data } = await supabase
      .from('organization_payment_settings')
      .select('accepted_payment_methods, zelle_recipient_name, zelle_contact, zelle_instructions, bank_transfer_instructions, cash_instructions, check_payable_to, check_instructions, stripe_connect_enabled')
      .eq('organization_id', activeOrgId)
      .maybeSingle();
    paymentSettings = data;
  }

  return (
    <div className="max-w-2xl space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <PageTitle>{invoice.invoiceNumber}</PageTitle>
          <p className="text-xs text-cool-gray mt-1">
            {TYPE_LABEL[invoice.invoiceType] ?? invoice.invoiceType}
            {!isCustomer && invoice.customerName && ` · ${invoice.customerName}`}
            {invoice.vesselName && ` · ${invoice.vesselName}`}
          </p>
        </div>
        <span className="font-mono text-[10px] uppercase text-gold border border-gold-dim px-2 py-1 rounded-sm">{invoice.status.replace('_', ' ')}</span>
      </div>

      <Card>
        <div className="space-y-2 mb-4">
          {visibleLines.map((li) => (
            <div key={li.id} className="flex items-center justify-between text-sm">
              <div>
                <span>{li.description}</span>
                <span className="text-cool-gray text-xs ml-2">
                  {li.quantity} × ${li.unitPrice.toFixed(2)}
                </span>
              </div>
              <span className="font-mono">${li.lineTotal.toFixed(2)}</span>
            </div>
          ))}
        </div>

        <div className="border-t border-white/10 pt-3 space-y-1 text-sm">
          <div className="flex justify-between text-cool-gray">
            <span>Subtotal</span>
            <span>${invoice.subtotal.toFixed(2)}</span>
          </div>
          {invoice.tax > 0 && (
            <div className="flex justify-between text-cool-gray">
              <span>Tax</span>
              <span>${invoice.tax.toFixed(2)}</span>
            </div>
          )}
          <div className="flex justify-between text-base font-semibold pt-1">
            <span>Total</span>
            <span>${invoice.total.toFixed(2)}</span>
          </div>
          <div className="flex justify-between text-cool-gray">
            <span>Paid</span>
            <span>${invoice.amountPaid.toFixed(2)}</span>
          </div>
          <div className="flex justify-between text-base font-semibold text-gold">
            <span>Balance Due</span>
            <span>${invoice.balanceDue.toFixed(2)}</span>
          </div>
        </div>

        {invoice.dueDate && <p className="text-[10px] font-mono uppercase text-cool-gray mt-3">Due {invoice.dueDate}</p>}
        {invoice.voidReason && <p className="text-xs text-red-400 mt-3">Voided: {invoice.voidReason}</p>}
      </Card>

      {/* CUSTOMER: instrucciones de pago si hay balance */}
      {isCustomer && invoice.balanceDue > 0 && invoice.status !== 'void' && paymentSettings && (
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Payment Instructions</div>
          <div className="space-y-3 text-sm">
            {paymentSettings.accepted_payment_methods?.includes('zelle') && paymentSettings.zelle_instructions && (
              <div>
                <div className="text-xs font-semibold">Zelle</div>
                <p className="text-xs text-cool-gray">{paymentSettings.zelle_recipient_name}</p>
                <p className="text-xs text-cool-gray">{paymentSettings.zelle_contact}</p>
                <p className="text-xs text-cool-gray">{paymentSettings.zelle_instructions}</p>
              </div>
            )}
            {paymentSettings.accepted_payment_methods?.includes('bank_transfer') && paymentSettings.bank_transfer_instructions && (
              <div>
                <div className="text-xs font-semibold">Bank Transfer</div>
                <p className="text-xs text-cool-gray">{paymentSettings.bank_transfer_instructions}</p>
              </div>
            )}
            {paymentSettings.accepted_payment_methods?.includes('cash') && paymentSettings.cash_instructions && (
              <div>
                <div className="text-xs font-semibold">Cash</div>
                <p className="text-xs text-cool-gray">{paymentSettings.cash_instructions}</p>
              </div>
            )}
            {paymentSettings.accepted_payment_methods?.includes('check') && paymentSettings.check_instructions && (
              <div>
                <div className="text-xs font-semibold">Check</div>
                <p className="text-xs text-cool-gray">Payable to: {paymentSettings.check_payable_to}</p>
                <p className="text-xs text-cool-gray">{paymentSettings.check_instructions}</p>
              </div>
            )}
          </div>
        </Card>
      )}

      {/* STAFF: emitir, registrar pago, voidar */}
      {isStaff && invoice.status === 'draft' && (
        <Card>
          <form action={issueInvoiceAction.bind(null, invoice.id)}>
            <button type="submit" className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm">
              Issue &amp; Send to Customer
            </button>
          </form>
        </Card>
      )}

      {isStaff && invoice.status !== 'draft' && invoice.status !== 'void' && (
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Customer Communication</div>
          <SendInvoiceEmailButton invoiceId={invoice.id} />
        </Card>
      )}

      {isStaff && invoice.balanceDue > 0 && invoice.status !== 'draft' && invoice.status !== 'void' && (
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Record Payment</div>
          <RecordPaymentForm invoiceId={invoice.id} balanceDue={invoice.balanceDue} />
        </Card>
      )}

      {invoice.payments.length > 0 && (
        <div>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-cool-gray mb-2">Payment History</div>
          <div className="space-y-1">
            {invoice.payments.map((p) => (
              <div key={p.id} className="text-xs flex justify-between">
                <span className="text-cool-gray">
                  {new Date(p.receivedAt).toLocaleDateString()} · {p.method.replace('_', ' ')}
                  {p.reference && ` (${p.reference})`}
                  {p.status === 'reversed' && ' — refunded'}
                </span>
                <span className={p.status === 'reversed' ? 'line-through text-cool-gray' : ''}>${p.amount.toFixed(2)}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {isStaff && invoice.amountPaid === 0 && invoice.status !== 'void' && (
        <Card>
          <VoidInvoiceForm invoiceId={invoice.id} />
        </Card>
      )}

      {invoice.workOrderId && (
        <Link href={`/work-orders/${invoice.workOrderId}`} className="text-[10px] font-mono uppercase text-gold">
          View Work Order →
        </Link>
      )}
    </div>
  );
}
