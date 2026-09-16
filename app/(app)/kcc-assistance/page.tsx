import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getOpenAssistanceRequests, getResolvedAssistanceRequests, getMyAssistanceRequests } from '@/lib/kcc-assistance/data';
import { AssistanceRequestCard } from '@/components/kcc-assistance/AssistanceRequestCard';
import { AssistanceRealtimeListener } from '@/components/kcc-assistance/AssistanceRealtimeListener';
import { PageTitle } from '@/components/ui/primitives';

export default async function KccAssistancePage() {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);

  if (session.isKccAdmin) {
    const [open, resolved] = await Promise.all([getOpenAssistanceRequests(), getResolvedAssistanceRequests()]);
    return (
      <div className="max-w-2xl space-y-6">
        <AssistanceRealtimeListener mode="admin" />
        <PageTitle>KCC Assistance</PageTitle>

        <div>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Open &amp; In Progress</div>
          <div className="space-y-2">
            {open.map((r) => (
              <AssistanceRequestCard key={r.id} request={r} isAdmin />
            ))}
            {open.length === 0 && <p className="text-sm text-cool-gray">No open requests.</p>}
          </div>
        </div>

        <div>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">History</div>
          <div className="space-y-2">
            {resolved.map((r) => (
              <AssistanceRequestCard key={r.id} request={r} isAdmin />
            ))}
            {resolved.length === 0 && <p className="text-sm text-cool-gray">No resolved requests yet.</p>}
          </div>
        </div>
      </div>
    );
  }

  // Técnico: su propio historial de pedidos. El botón para pedir
  // asistencia vive en el detalle del work order asignado.
  const myRequests = await getMyAssistanceRequests();
  return (
    <div className="max-w-2xl space-y-6">
      <AssistanceRealtimeListener mode="technician" technicianId={session.userId} />
      <PageTitle>My Assistance Requests</PageTitle>
      <div className="space-y-2">
        {myRequests.map((r) => (
          <AssistanceRequestCard key={r.id} request={r} isAdmin={false} />
        ))}
        {myRequests.length === 0 && <p className="text-sm text-cool-gray">You haven't requested assistance yet.</p>}
      </div>
    </div>
  );
}
