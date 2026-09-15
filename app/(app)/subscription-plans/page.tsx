import { redirect } from 'next/navigation';
import { getSessionContext } from '@/lib/auth/session';
import { getAllPlansForManagement } from '@/lib/subscription-plans/data';
import { PlanCreateForm } from '@/components/subscription-plans/PlanCreateForm';
import { PlanRow } from '@/components/subscription-plans/PlanRow';
import { PageTitle } from '@/components/ui/primitives';

export default async function SubscriptionPlansPage() {
  const session = await getSessionContext();
  if (!session.isKccAdmin) redirect('/dashboard');

  const plans = await getAllPlansForManagement();

  return (
    <div className="max-w-2xl space-y-6">
      <div className="flex items-center justify-between">
        <PageTitle>Subscription Plans</PageTitle>
        <PlanCreateForm />
      </div>

      <div className="space-y-3">
        {plans.map((plan) => (
          <PlanRow key={plan.id} plan={plan} />
        ))}
        {plans.length === 0 && <p className="text-sm text-cool-gray">No plans yet — create one to start assigning commercial subscriptions.</p>}
      </div>
    </div>
  );
}
