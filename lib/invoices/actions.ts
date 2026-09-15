'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';

export async function createDepositInvoiceAction(workOrderId: string) {
  const supabase = await createClient();
  const { data: invoiceId, error } = await supabase.rpc('create_deposit_invoice', { p_work_order_id: workOrderId, p_due_date: null });
  if (error || !invoiceId) {
    logger.warn('createDepositInvoiceAction failed', { message: error?.message });
    return;
  }
  redirect(`/invoices/${invoiceId}`);
}

export async function createInvoiceAction(formData: FormData) {
  const workOrderId = formData.get('workOrderId') as string;
  const invoiceType = formData.get('invoiceType') as string;
  const amountRaw = formData.get('amount') as string;
  const supabase = await createClient();
  const { data: invoiceId, error } = await supabase.rpc('create_invoice', {
    p_work_order_id: workOrderId,
    p_invoice_type: invoiceType,
    p_amount: amountRaw ? Number(amountRaw) : null,
    p_due_date: (formData.get('dueDate') as string) || null,
  });
  if (error || !invoiceId) {
    logger.warn('createInvoiceAction failed', { message: error?.message });
    return;
  }
  redirect(`/invoices/${invoiceId}`);
}

export async function issueInvoiceAction(invoiceId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('issue_invoice', { p_invoice_id: invoiceId });
  if (error) logger.warn('issueInvoiceAction failed', { message: error.message });
  revalidatePath(`/invoices/${invoiceId}`);
}

export async function voidInvoiceAction(formData: FormData) {
  const invoiceId = formData.get('invoiceId') as string;
  const reason = formData.get('reason') as string;
  const supabase = await createClient();
  const { error } = await supabase.rpc('void_invoice', { p_invoice_id: invoiceId, p_reason: reason });
  if (error) {
    logger.warn('voidInvoiceAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/invoices/${invoiceId}`);
  return {};
}

export async function recordManualPaymentAction(formData: FormData) {
  const invoiceId = formData.get('invoiceId') as string;
  const supabase = await createClient();
  const { error } = await supabase.rpc('record_manual_payment', {
    p_invoice_id: invoiceId,
    p_amount: Number(formData.get('amount')),
    p_method: formData.get('method') as string,
    p_reference: (formData.get('reference') as string) || null,
    p_received_at: new Date().toISOString(),
    p_notes: (formData.get('notes') as string) || null,
  });
  if (error) {
    logger.warn('recordManualPaymentAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/invoices/${invoiceId}`);
  return {};
}

export async function refundPaymentAction(formData: FormData) {
  const invoiceId = formData.get('invoiceId') as string;
  const paymentId = formData.get('paymentId') as string;
  const supabase = await createClient();
  const { error } = await supabase.rpc('refund_manual_payment', {
    p_payment_id: paymentId,
    p_amount: Number(formData.get('amount')),
    p_reason: formData.get('reason') as string,
  });
  if (error) {
    logger.warn('refundPaymentAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/invoices/${invoiceId}`);
  return {};
}

export async function updatePaymentSettingsAction(formData: FormData) {
  const organizationId = formData.get('organizationId') as string;
  const supabase = await createClient();
  const methods = formData.getAll('acceptedMethods') as string[];
  const { error } = await supabase.rpc('update_payment_settings', {
    p_organization_id: organizationId,
    p_deposit_required: formData.get('depositRequired') === 'on',
    p_deposit_type: formData.get('depositType') as string,
    p_deposit_value: Number(formData.get('depositValue') || 0),
    p_remaining_balance_due: null,
    p_require_deposit_before_start: formData.get('requireDepositBeforeStart') === 'on',
    p_manual_payments_enabled: formData.get('manualPaymentsEnabled') === 'on',
    p_accepted_payment_methods: methods.length > 0 ? methods : null,
    p_zelle_recipient_name: (formData.get('zelleRecipientName') as string) || null,
    p_zelle_contact: (formData.get('zelleContact') as string) || null,
    p_zelle_instructions: (formData.get('zelleInstructions') as string) || null,
    p_bank_transfer_instructions: (formData.get('bankTransferInstructions') as string) || null,
    p_cash_instructions: (formData.get('cashInstructions') as string) || null,
    p_check_payable_to: (formData.get('checkPayableTo') as string) || null,
    p_check_instructions: (formData.get('checkInstructions') as string) || null,
  });
  if (error) logger.warn('updatePaymentSettingsAction failed', { message: error.message });
  revalidatePath('/company-settings');
}
