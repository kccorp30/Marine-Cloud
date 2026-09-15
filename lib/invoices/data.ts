import 'server-only';
import { createClient } from '@/lib/supabase/server';

export interface InvoiceListRow {
  id: string;
  invoiceNumber: string;
  invoiceType: string;
  status: string;
  total: number;
  amountPaid: number;
  balanceDue: number;
  currency: string;
  customerName: string | null;
  vesselName: string | null;
  issueDate: string;
  dueDate: string | null;
}

export interface PaymentDTO {
  id: string;
  amount: number;
  method: string;
  status: string;
  reference: string | null;
  receivedAt: string;
  notes: string | null;
}

export interface InvoiceLineItemDTO {
  id: string;
  lineType: string;
  description: string;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
  customerVisible: boolean;
}

export interface InvoiceDetailDTO {
  id: string;
  invoiceNumber: string;
  invoiceType: string;
  status: string;
  currency: string;
  issueDate: string;
  dueDate: string | null;
  subtotal: number;
  discount: number;
  tax: number;
  total: number;
  amountPaid: number;
  balanceDue: number;
  customerName: string | null;
  vesselName: string | null;
  workOrderId: string | null;
  voidReason: string | null;
  lineItems: InvoiceLineItemDTO[];
  payments: PaymentDTO[];
}

export async function getInvoiceList(organizationId: string, filters?: { status?: string }): Promise<InvoiceListRow[]> {
  const supabase = await createClient();
  let query = supabase
    .from('invoices')
    .select('id, invoice_number, invoice_type, status, total, amount_paid, balance_due, currency, issue_date, due_date, customer:customers(first_name, last_name), vessel:vessels(name)')
    .eq('organization_id', organizationId)
    .order('created_at', { ascending: false });

  if (filters?.status) query = query.eq('status', filters.status);

  const { data } = await query;
  return (data ?? []).map((i: any) => {
    const customer = Array.isArray(i.customer) ? i.customer[0] : i.customer;
    const vessel = Array.isArray(i.vessel) ? i.vessel[0] : i.vessel;
    return {
      id: i.id,
      invoiceNumber: i.invoice_number,
      invoiceType: i.invoice_type,
      status: i.status,
      total: Number(i.total),
      amountPaid: Number(i.amount_paid),
      balanceDue: Number(i.balance_due),
      currency: i.currency,
      customerName: customer ? `${customer.first_name} ${customer.last_name}` : null,
      vesselName: vessel?.name ?? null,
      issueDate: i.issue_date,
      dueDate: i.due_date,
    };
  });
}

export async function getInvoiceDetail(invoiceId: string): Promise<InvoiceDetailDTO | null> {
  const supabase = await createClient();

  const { data: invoice } = await supabase
    .from('invoices')
    .select('id, invoice_number, invoice_type, status, currency, issue_date, due_date, subtotal, discount, tax, total, amount_paid, balance_due, work_order_id, void_reason, customer:customers(first_name, last_name), vessel:vessels(name)')
    .eq('id', invoiceId)
    .maybeSingle();

  if (!invoice) return null;

  const { data: lineItems } = await supabase
    .from('invoice_line_items')
    .select('id, line_type, description, quantity, unit_price, line_total, customer_visible, sort_order')
    .eq('invoice_id', invoiceId)
    .order('sort_order');

  const { data: payments } = await supabase
    .from('payments')
    .select('id, amount, method, status, reference, received_at, notes')
    .eq('invoice_id', invoiceId)
    .order('received_at', { ascending: false });

  const customer = Array.isArray(invoice.customer) ? invoice.customer[0] : invoice.customer;
  const vessel = Array.isArray(invoice.vessel) ? invoice.vessel[0] : invoice.vessel;

  return {
    id: invoice.id,
    invoiceNumber: invoice.invoice_number,
    invoiceType: invoice.invoice_type,
    status: invoice.status,
    currency: invoice.currency,
    issueDate: invoice.issue_date,
    dueDate: invoice.due_date,
    subtotal: Number(invoice.subtotal),
    discount: Number(invoice.discount),
    tax: Number(invoice.tax),
    total: Number(invoice.total),
    amountPaid: Number(invoice.amount_paid),
    balanceDue: Number(invoice.balance_due),
    customerName: customer ? `${customer.first_name} ${customer.last_name}` : null,
    vesselName: vessel?.name ?? null,
    workOrderId: invoice.work_order_id,
    voidReason: invoice.void_reason,
    lineItems: (lineItems ?? []).map((li) => ({
      id: li.id,
      lineType: li.line_type,
      description: li.description,
      quantity: Number(li.quantity),
      unitPrice: Number(li.unit_price),
      lineTotal: Number(li.line_total),
      customerVisible: li.customer_visible,
    })),
    payments: (payments ?? []).map((p) => ({
      id: p.id,
      amount: Number(p.amount),
      method: p.method,
      status: p.status,
      reference: p.reference,
      receivedAt: p.received_at,
      notes: p.notes,
    })),
  };
}

export interface WorkOrderFinancialSummaryDTO {
  authorizedTotal: number;
  invoicedTotal: number;
  paidTotal: number;
  remainingInvoiceable: number;
  depositRequired: boolean;
  depositAmount: number;
  depositSatisfied: boolean;
}

export async function getWorkOrderFinancialSummary(workOrderId: string): Promise<WorkOrderFinancialSummaryDTO | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('get_work_order_financial_summary', { p_work_order_id: workOrderId });
  if (error || !data) return null;
  return {
    authorizedTotal: Number(data.authorized_total),
    invoicedTotal: Number(data.invoiced_total),
    paidTotal: Number(data.paid_total),
    remainingInvoiceable: Number(data.remaining_invoiceable),
    depositRequired: data.deposit_required,
    depositAmount: Number(data.deposit_amount),
    depositSatisfied: data.deposit_satisfied,
  };
}
