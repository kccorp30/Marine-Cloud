# KCC Marine Cloud — Cinematic Command Center Pass

This pass builds directly on the latest `astra-owner-fix` source and keeps the production auth/invitation fixes intact.

## Visual system added
- Reusable `CommandPanel`, `MetricCard`, `RadialGauge`, `ProgressMeter`, and `CommandSectionTitle` primitives.
- Animated radial gauges, progress reveals, metric bars, hover illumination, subtle panel sweeps, and live-status treatments.
- Stronger navy/gold/electric-blue/emerald command-center palette.
- More deliberate dense dashboard layouts modeled on the approved KCC references.

## KCC Admin
- Cinematic control-center hero.
- Animated operational KPIs.
- Network status radial gauges driven by real organization states.
- Financial snapshot from existing invoices/payments.
- Recent companies command table.
- Platform event telemetry timeline.
- Visible Luz AI surface linked to the existing communications capability.

## Company
- Command hero and illuminated operational metrics.
- Route / upcoming operations panel.
- Technician command block with real check-in and assignment coverage indicators.
- Commercial decision center and attention queue.
- Visible Luz Assistant surface.

## Technician
- Field-command hero.
- Active/en-route/waiting metrics.
- Premium route/day plan using real assigned work and appointment times.
- Current-vessel hero and readiness meter.
- Visible Luz Assist entry point without claiming unsupported autonomous tools.

## Customer
- Premium cinematic welcome and current-service progress.
- Animated service timeline and progress gauge.
- Vessel command card, real invoice/estimate action center, warranty/support surfaces.
- Visible Luz customer assistant entry point.

## Truthfulness
No fake revenue, weather, ETA, GPS routes, fleet health, technician counts, points, or live status were added. Visual meters are based only on existing real counts/states or omitted when the underlying data does not exist.

## Verification note
Dependency installation in the generation sandbox timed out and left `node_modules` incomplete, so a clean `next build` could not be completed here. Verify with Vercel/CI before production promotion.
