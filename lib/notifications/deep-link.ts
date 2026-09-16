export interface NotificationLinkInput {
  relatedEntityType: string | null;
  relatedEntityId: string | null;
}

const SUPPORTED_DEEP_LINK_TYPES: Record<string, (id: string) => string> = {
  work_order: (id) => `/work-orders/${id}`,
  vessel: (id) => `/vessels/${id}`,
  invoice: (id) => `/invoices/${id}`,
  estimate: (id) => `/estimates/${id}`,
  service_request: () => `/service-requests`,
  conversation: (id) => `/communications/${id}`,
  kcc_assistance_request: () => `/kcc-assistance`,
};

export function getNotificationDeepLink(n: NotificationLinkInput): string | null {
  if (!n.relatedEntityType || !n.relatedEntityId) return null;
  const builder = SUPPORTED_DEEP_LINK_TYPES[n.relatedEntityType];
  return builder ? builder(n.relatedEntityId) : null;
}
