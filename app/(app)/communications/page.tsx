import Link from 'next/link';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getConversationList } from '@/lib/communications/data';
import { Card, PageTitle } from '@/components/ui/primitives';

export default async function CommunicationsPage() {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const conversations = await getConversationList(activeOrgId!);

  return (
    <div className="max-w-3xl space-y-6">
      <div className="flex items-center justify-between">
        <PageTitle>Communications</PageTitle>
        <Link href="/communications/templates" className="text-[10px] font-mono uppercase text-gold">
          Templates →
        </Link>
      </div>

      <div className="space-y-2">
        {conversations.map((c) => (
          <Link key={c.id} href={`/communications/${c.id}`}>
            <Card className="hover:border-gold/40 transition-colors">
              <div className="flex items-center justify-between">
                <div>
                  <div className="text-sm font-semibold">{c.subject ?? 'Conversation'}</div>
                  <div className="text-xs text-cool-gray mt-0.5">
                    {c.customerName} {c.vesselName && `· ${c.vesselName}`}
                  </div>
                  {c.lastMessagePreview && <div className="text-xs text-cool-gray/70 mt-1 truncate">{c.lastMessagePreview}</div>}
                </div>
                <div className="text-right shrink-0 ml-3">
                  {c.lastMessageAt && <div className="text-[10px] text-cool-gray">{new Date(c.lastMessageAt).toLocaleDateString()}</div>}
                  <span className="font-mono text-[9px] uppercase text-cool-gray">{c.status}</span>
                </div>
              </div>
            </Card>
          </Link>
        ))}
        {conversations.length === 0 && <p className="text-sm text-cool-gray">No conversations yet.</p>}
      </div>
    </div>
  );
}
