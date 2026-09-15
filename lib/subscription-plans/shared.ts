export const CORE_MODULE_KEYS = ['work_orders', 'service_requests', 'estimates', 'tracking', 'warranty', 'communications'] as const;

export interface PlanManagementRow {
  id: string;
  code: string;
  name: string;
  description: string | null;
  status: string;
  currency: string;
  weeklyPrice: number | null;
  monthlyPrice: number | null;
  annualPrice: number | null;
  trialDefaultDays: number | null;
  isPublic: boolean;
  isCustom: boolean;
  activeSubscriptionCount: number;
  entitlements: Record<string, boolean>;
}
