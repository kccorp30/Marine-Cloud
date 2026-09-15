import 'server-only';
import { createClient } from '@/lib/supabase/server';

export interface ConversationListRow {
  id: string;
  subject: string | null;
  status: string;
  customerName: string | null;
  vesselName: string | null;
  lastMessageAt: string | null;
  lastMessagePreview: string | null;
}

export interface MessageDTO {
  id: string;
  senderType: string;
  direction: string;
  channel: string;
  bodyOriginal: string;
  bodyRendered: string | null;
  languageOriginal: string | null;
  languageRendered: string | null;
  status: string;
  createdAt: string;
  sentAt: string | null;
  deliveredAt: string | null;
  failedAt: string | null;
  failureReason: string | null;
}

export interface ConversationDetailDTO {
  id: string;
  subject: string | null;
  status: string;
  customerId: string;
  customerName: string | null;
  customerEmail: string | null;
  vesselName: string | null;
  workOrderId: string | null;
  messages: MessageDTO[];
}

export async function getConversationList(organizationId: string, customerId?: string): Promise<ConversationListRow[]> {
  const supabase = await createClient();
  let query = supabase
    .from('conversations')
    .select('id, subject, status, last_message_at, customer:customers(first_name, last_name), vessel:vessels(name)')
    .eq('organization_id', organizationId)
    .order('last_message_at', { ascending: false, nullsFirst: false });

  if (customerId) query = query.eq('customer_id', customerId);

  const { data } = await query;
  if (!data) return [];

  const conversationIds = data.map((c) => c.id);
  const { data: lastMessages } =
    conversationIds.length > 0
      ? await supabase
          .from('messages')
          .select('conversation_id, body_original, created_at')
          .in('conversation_id', conversationIds)
          .eq('status', 'sent')
          .order('created_at', { ascending: false })
      : { data: [] };

  const previewByConversation = new Map<string, string>();
  for (const m of lastMessages ?? []) {
    if (!previewByConversation.has(m.conversation_id)) {
      previewByConversation.set(m.conversation_id, m.body_original.slice(0, 80));
    }
  }

  return data.map((c: any) => {
    const customer = Array.isArray(c.customer) ? c.customer[0] : c.customer;
    const vessel = Array.isArray(c.vessel) ? c.vessel[0] : c.vessel;
    return {
      id: c.id,
      subject: c.subject,
      status: c.status,
      customerName: customer ? `${customer.first_name} ${customer.last_name}` : null,
      vesselName: vessel?.name ?? null,
      lastMessageAt: c.last_message_at,
      lastMessagePreview: previewByConversation.get(c.id) ?? null,
    };
  });
}

export async function getConversationDetail(conversationId: string): Promise<ConversationDetailDTO | null> {
  const supabase = await createClient();

  const { data: conversation } = await supabase
    .from('conversations')
    .select('id, subject, status, customer_id, work_order_id, customer:customers(first_name, last_name, email), vessel:vessels(name)')
    .eq('id', conversationId)
    .maybeSingle();

  if (!conversation) return null;

  const { data: messages } = await supabase
    .from('messages')
    .select('id, sender_type, direction, channel, body_original, body_rendered, language_original, language_rendered, status, created_at, sent_at, delivered_at, failed_at, failure_reason')
    .eq('conversation_id', conversationId)
    .order('created_at', { ascending: true });

  const customer = Array.isArray(conversation.customer) ? conversation.customer[0] : conversation.customer;
  const vessel = Array.isArray(conversation.vessel) ? conversation.vessel[0] : conversation.vessel;

  return {
    id: conversation.id,
    subject: conversation.subject,
    status: conversation.status,
    customerId: conversation.customer_id,
    customerName: customer ? `${customer.first_name} ${customer.last_name}` : null,
    customerEmail: customer?.email ?? null,
    vesselName: vessel?.name ?? null,
    workOrderId: conversation.work_order_id,
    messages: (messages ?? []).map((m) => ({
      id: m.id,
      senderType: m.sender_type,
      direction: m.direction,
      channel: m.channel,
      bodyOriginal: m.body_original,
      bodyRendered: m.body_rendered,
      languageOriginal: m.language_original,
      languageRendered: m.language_rendered,
      status: m.status,
      createdAt: m.created_at,
      sentAt: m.sent_at,
      deliveredAt: m.delivered_at,
      failedAt: m.failed_at,
      failureReason: m.failure_reason,
    })),
  };
}

export interface TemplateRow {
  id: string;
  name: string;
  category: string;
  language: string;
  subject: string | null;
  body: string;
  isActive: boolean;
}

export async function getTemplates(organizationId: string): Promise<TemplateRow[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from('message_templates')
    .select('id, name, category, language, subject, body, is_active')
    .eq('organization_id', organizationId)
    .order('category');
  return (data ?? []).map((t) => ({
    id: t.id,
    name: t.name,
    category: t.category,
    language: t.language,
    subject: t.subject,
    body: t.body,
    isActive: t.is_active,
  }));
}
