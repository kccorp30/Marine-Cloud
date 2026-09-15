import Link from 'next/link';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getConversationList } from '@/lib/communications/data';
import { Card, PageTitle } from '@/components/ui/primitives';

export default async function CustomerMessagesPage() {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);

  const supabase = await createClient();
  const { data: customer } = await supabase.from('customers').select('id').eq('profile_id', session.userId).eq('organization_id', activeOrgId).maybeSingle();

  const conversations = customer ? await getConversationList(activeOrgId!, customer.id) : [];

  return (
    <div className="max-w-2xl space-y-6">
      <PageTitle>Messages</PageTitle>

      <div className="space-y-2">
        {conversations.map((c) => (
          <Link key={c.id} href={`/communications/${c.id}`}>
            <Card className="hover:border-gold/40 transition-colors">
              <div className="flex items-center justify-between">
                <div>
                  <div className="text-sm font-semibold">{c.subject ?? 'Conversation'}</div>
                  {c.vesselName && <div className="text-xs text-cool-gray mt-0.5">{c.vesselName}</div>}
                  {c.lastMessagePreview && <div className="text-xs text-cool-gray/70 mt-1 truncate">{c.lastMessagePreview}</div>}
                </div>
                {c.lastMessageAt && <div className="text-[10px] text-cool-gray shrink-0 ml-3">{new Date(c.lastMessageAt).toLocaleDateString()}</div>}
              </div>
            </Card>
          </Link>
        ))}
        {conversations.length === 0 && <p className="text-sm text-cool-gray">No messages yet.</p>}
      </div>
    </div>
  );
}
