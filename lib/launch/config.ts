// Commercial enrollment is paused for the operational launch. This only
// controls presentation; database authorization and entitlements remain intact.
export const BILLING_PAUSED =
  process.env.NEXT_PUBLIC_PLATFORM_BILLING_ENABLED !== "true";
