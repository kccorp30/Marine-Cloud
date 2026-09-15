# KCC Marine Cloud — Premium UI Pass

This pass applies the approved luxury marine visual language directly to the existing application without changing the core Supabase/RLS/work-order architecture.

## Main visual changes
- Full premium shell: branded sidebar, grouped role navigation, glass top bar, search, profile and language controls.
- Real KCC logo retained as the primary brand asset.
- Shared premium card/input/status/empty-state primitives so existing operational pages inherit the same visual system.
- Marine hero asset added at `public/brand/marine-hero.jpg` and used as an atmospheric, branded background layer.
- Login rebuilt around the approved cinematic marine direction.
- KCC Admin dashboard rebuilt as a control-center layout using only live/available data.
- Company dashboard rebuilt with live operations KPIs, requests, technicians, appointments, commercial summary, alerts and completed work.
- Technician dashboard rebuilt as a field-first daily route/workspace using real assignment data.
- Customer dashboard rebuilt English-first with active service progress, vessel, payments/estimates and secure quick actions.
- Responsive layouts and higher-density desktop presentation; technician/customer remain mobile-friendly.

## Data-truth rule
The visual references are treated as design targets only. This pass does not hard-code mock revenue, ETA, health score, weather, points, live tracking or other data that the current backend does not actually supply.

## Verification note
A local TypeScript/build verification could not be completed in the artifact environment because dependency installation did not finish and the partial `node_modules` tree lacked type definitions. Deploy/CI should run `npm ci`, `npx tsc --noEmit`, `npm test`, and `npm run build` before production promotion.
