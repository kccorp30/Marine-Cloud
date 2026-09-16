import { notFound } from 'next/navigation';
import Link from 'next/link';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getConversationDetail } from '@/lib/communications/data';
import { MessageComposer } from '@/components/communications/MessageComposer';
import { customerReplyAction, convertConversationToServiceRequestAction } from '@/lib/communications/actions';
import { ActionForm } from '@/components/ui/ActionForm';
import { RetryMessageButton } from '@/components/communications/RetryMessageButton';
import { Card, PageTitle } from '@/components/ui/primitives';
import { listEntityMedia } from '@/lib/media/entity-media';
import { EntityMediaGallery } from '@/components/media/EntityMediaGallery';
import { uploadConversationMediaAction } from '@/lib/media/actions';
import { MediaActionForm } from '@/components/media/MediaActionForm';
import { MultiImagePicker } from '@/components/media/MultiImagePicker';

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
  const attachments = await listEntityMedia('conversation', id);

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
        {conversation.serviceRequestId && !isCustomer && (
          <Link href="/service-requests" className="text-[10px] font-mono uppercase text-cyan-200 ml-3">
            Service Request Created ✓
          </Link>
        )}
      </div>


      {!isCustomer && !conversation.serviceRequestId && (
        <Card className="!rounded-2xl border-cyan-300/15">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div><p className="command-kicker">LUZ · NEXT STEP</p><h2 className="text-lg font-semibold mt-1">Turn this conversation into service</h2><p className="text-xs text-cool-gray mt-2 max-w-xl">If this needs a technician or estimate, create the service request here without retyping the customer or vessel.</p></div>
            <ActionForm action={convertConversationToServiceRequestAction} className="flex items-center gap-2">
              <input type="hidden" name="conversationId" value={conversation.id} />
              <button className="command-button" type="submit">Create service request →</button>
            </ActionForm>
          </div>
        </Card>
      )}

      <EntityMediaGallery items={attachments} title={isCustomer ? 'Photos shared with the team' : 'Customer & team photos'} />

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


      <Card className="!rounded-2xl">
        <div className="flex items-center gap-3 mb-4"><span className="support-thread-icon">＋</span><div><div className="text-sm font-semibold">Add visual context</div><div className="text-xs text-cool-gray mt-1">Share photos without leaving this support thread.</div></div></div>
        <MediaActionForm action={uploadConversationMediaAction} resetOnSuccess className="space-y-3">
          <input type="hidden" name="conversationId" value={conversation.id} />
          <MultiImagePicker label="Attach photos" hint="Up to 5 images · optimized before upload" />
          <input name="caption" maxLength={180} placeholder="Optional caption" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-xl px-4 py-3" />
          <button className="command-button" type="submit">Upload photos →</button>
        </MediaActionForm>
      </Card>

      {isCustomer ? (
        <Card className="!rounded-2xl">
          <div className="flex items-center gap-3 mb-4"><span className="support-thread-icon">✦</span><div><div className="text-sm font-semibold">Reply to your team</div><div className="text-xs text-cool-gray mt-1">Your reply stays in this secure conversation and alerts the company.</div></div></div>
          <ActionForm action={customerReplyAction} resetOnSuccess className="space-y-3">
            <input type="hidden" name="conversationId" value={conversation.id} />
            <textarea name="body" rows={5} required maxLength={5000} placeholder="Write your message…" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-xl px-4 py-3" />
            <button className="command-button" type="submit">Send message →</button>
          </ActionForm>
        </Card>
      ) : (
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Reply</div>
          <MessageComposer conversationId={conversation.id} />
        </Card>
      )}
    </div>
  );
}
