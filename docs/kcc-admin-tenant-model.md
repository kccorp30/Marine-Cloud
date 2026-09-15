# KCC Admin Tenant Model — Clarification

## Respuesta directa: SÍ

`kcc_admin` **siempre** está representado como una membership activa en alguna organización — hoy, en la práctica, una organización interna dedicada (`KCCORP (Internal)`, creada manualmente en el paso de setup). Esto es un **invariante explícito**, no una suposición ambigua.

## Por qué (razonamiento)

`organization_memberships.organization_id` es `NOT NULL` — cada fila de membership pertenece a una organización, sin excepción. Se evaluaron dos caminos:

1. **Hacer `organization_id` nullable** para permitir memberships "sin organización" específicamente para `kcc_admin` — descartado. Complica cada query y cada constraint futura que asuma `organization_id` presente (incluyendo el propio trigger genérico de auditoría, que ya tuvo que manejar el caso especial de `organizations` sin esa columna — ver `015_fix_audit_trigger_generic.sql`). Nullable "solo para un caso" es la clase de excepción que genera bugs sutiles más adelante.

2. **Organización interna dedicada** (la elegida) — `kcc_admin` tiene su membership en una organización que no es un tenant "real" de negocio, es un ancla técnica. El privilegio de `kcc_admin` es **global**, no depende de CUÁL organización sea esa — `is_kcc_admin()` verifica únicamente `role = 'kcc_admin' and status = 'active'` en cualquier fila, sin filtrar por `organization_id`. La organización elegida es funcionalmente irrelevante para los permisos; solo satisface la constraint.

## Consecuencia práctica en el shell (ajuste aplicado)

Antes de esta verificación, un `kcc_admin` con una sola membership (el caso típico) veía en el nav el nombre de la organización interna ("KCCORP (Internal) · kcc_admin") como si fuera su compañía — ambiguo, podía leerse como "opera dentro de esa compañía" cuando en realidad opera en contexto de red completa. Corregido: cuando `isKccAdmin` es true, el shell ahora muestra **"KCC Admin — Network Access"** en vez del nombre de la organización interna, sin importar cuántas memberships tenga. Ver cambio en `components/layout/AppNav.tsx`.

## Qué NO cambia

Esto no es nueva funcionalidad de producto — es una corrección de claridad de UI sobre lo que ya existía, exactamente lo que pediste verificar en este punto.
