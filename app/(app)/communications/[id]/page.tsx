import { notFound } from 'next/navigation';
import Link from 'next/link';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getConversationDetail } from '@/lib/communications/data';
import { MessageComposer } from '@/components/communications/MessageComposer';
import { RetryMessageButton } from '@/components/communications/RetryMessageButton';
import { Card, PageTitle } from '@/components/ui/primitives';

const STATUS_COLOR: Record<string, string> = {
  draft: 'text-cool-gray',
  sent: 'text-gold',
  delivered: 'text-emerald-400',
  failed: 'text-red-400',
};

export default async function ConversationDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const actorRole = session.memberships.find((m) => m.organization_id === activeOrgId)?.role;
  const isCustomer = actorRole === 'customer';

  const conversation = await getConversationDetail(id);
  if (!conversation) notFound();

  return (
    <div className="max-w-2xl space-y-6">
      <div>
        <PageTitle>{conversation.subject ?? 'Conversation'}</PageTitle>
        <p className="text-xs text-cool-gray mt-1">
          {!isCustomer && conversation.customerName && `${conversation.customerName} · `}
          {conversation.vesselName}
        </p>
        {conversation.workOrderId && !isCustomer && (
          <Link href={`/work-orders/${conversation.workOrderId}`} className="text-[10px] font-mono uppercase text-gold">
            View Work Order →
          </Link>
        )}
      </div>

      <div className="space-y-3">
        {conversation.messages.map((m) => (
          <Card key={m.id} className={m.direction === 'outbound' ? '' : 'border-gold/30'}>
            <div className="flex items-center justify-between mb-2">
              <span className="text-[10px] font-mono uppercase text-cool-gray">
                {m.senderType === 'staff' ? 'Company' : m.senderType === 'customer' ? 'Customer' : 'System'} · {new Date(m.createdAt).toLocaleString()}
              </span>
              <span className={`font-mono text-[9px] uppercase ${STATUS_COLOR[m.status] ?? 'text-cool-gray'}`}>{m.status}</span>
            </div>
            <p className="text-sm whitespace-pre-wrap">{m.bodyOriginal}</p>
            {m.bodyRendered && (
              <div className="mt-2 pt-2 border-t border-white/10">
                <div className="text-[9px] font-mono uppercase text-cool-gray mb-1">
                  Sent as ({m.languageRendered === 'es' ? 'Spanish' : 'English'})
                </div>
                <p className="text-sm whitespace-pre-wrap text-cool-gray">{m.bodyRendered}</p>
              </div>
            )}
            {m.status === 'failed' && m.failureReason && <p className="text-xs text-red-400 mt-2">Failed: {m.failureReason}</p>}
            {!isCustomer && m.status === 'failed' && <RetryMessageButton messageId={m.id} conversationId={conversation.id} />}
          </Card>
        ))}
        {conversation.messages.length === 0 && <p className="text-sm text-cool-gray">No messages yet.</p>}
      </div>

      {!isCustomer && (
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Reply</div>
          <MessageComposer conversationId={conversation.id} />
        </Card>
      )}
    </div>
  );
}
