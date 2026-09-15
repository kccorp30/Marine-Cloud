# KCC Marine Cloud — POST-LAUNCH BACKLOG

Generado tras la verificación E2E de go-live. Priorizado por severidad real, no por orden de aparición.

## P1 — Antes de escalar más allá de la primera compañía piloto

1. **Documentación de entrenamiento del flujo real de estados.** La cadena real de `transition_work_order()` (`checked_in→diagnosis→work_in_progress`, `invoice→payment→completed`) no está documentada en ningún lugar visible para el staff de KCC o de la compañía — solo vive en `work_order_transition_rules`. Sin esto, es fácil que alguien del staff asuma un atajo que no existe y se confunda con el error de permisos/transición real. Recomiendo un diagrama de una página, no un cambio de código.
2. **Verificación manual en UI real de producción.** Esta pasada verificó el flujo a nivel de base de datos (RPCs + RLS reales), nunca a través del navegador real. Alguien debe repetir los 19 pasos críticos manualmente en la UI de producción antes de la primera compañía de pago.
3. **Confirmar que el proyecto Supabase usado en este sandbox es efectivamente el de producción**, o documentar la diferencia si no lo es. Este entorno no tiene forma de verificarlo por sí mismo.
4. **Verificar entrega real de notificaciones** (push/email) — las filas de `notifications` se generan correctamente, pero el canal de entrega real (proveedor de email, push de móvil) no se ejercitó con datos reales en esta pasada.

## P2 — Real pero no bloqueante para el piloto

5. **Módulo de `invoices`/`payments` de customer (Phase 7) no se ejercitó de punta a punta en esta pasada** — el work order pasó por el status `invoice`/`payment` correctamente, pero no se creó un invoice real ni se registró un payment real de customer en este flujo específico. Dado que Phase 7 ya tiene su propia verificación histórica documentada, este es un gap de esta pasada puntual, no necesariamente del producto.
6. **UI de billing de KCC (Phase 15)** — el motor financiero de suscripción (`platform_billing_charges`/`platform_payments`) está construido y verificado a nivel de RPC, pero sin pantalla — KCC todavía necesitaría SQL directo para operar cobros de sus compañías clientas. No bloquea operar la primera compañía piloto en modo complimentary (como se probó en este pase), pero sí bloquea cobrar a esa compañía cuando el piloto termine.
7. **Scheduler automático de generación de cargos y recordatorios de vencimiento** (Phase 15) — no implementado; la generación de cargos es manual/on-demand por ahora.

## P3 — Housekeeping real, sin urgencia

8. **Subida real de archivos a Storage nunca se probó en esta pasada** (se insertó la fila de `media_assets` directamente vía SQL, sin pasar por el flujo real de subida) — dado que Storage ya se verificó en fases anteriores del proyecto, este es un gap puntual de esta pasada, no evidencia de un problema nuevo.
9. **Comportamiento en dispositivo móvil real** — no verificable desde este entorno.

## Nota sobre lo que NO se encontró

No se encontró ningún bloqueador P0 real durante esta verificación — ningún paso del flujo crítico falló por un bug genuino del producto. Los dos "fallos" que aparecieron durante la verificación (transiciones de estado que rechazaron mi primer intento) fueron errores de mi propio guión de prueba al asumir atajos que el sistema correctamente no permite — no bugs del producto. Esto se confirmó revisando `work_order_transition_rules` directamente antes de reintentar.
