# KCC Marine Cloud — GO-LIVE CHECKLIST

**Fecha de verificación:** 2026-09-12
**Alcance:** Flujo E2E crítico corrido con datos reales contra el proyecto Supabase (`zxgeipuzglromtuxhxtb`) que este sandbox tiene configurado.

## ⚠️ Advertencia crítica sobre el alcance de esta verificación

Esta verificación se corrió **directamente contra la base de datos** (RPCs reales, RLS real, datos reales creados y limpiados), **no a través de la interfaz web real** (no hay navegador/UI en este entorno). Esto prueba genuinamente que la lógica de negocio, permisos, y flujo de datos funcionan — pero **no prueba**:
- Que la UI realmente invoque estas RPCs con los parámetros correctos en cada pantalla
- Renderizado real, JavaScript del cliente, o compatibilidad de navegador/móvil
- Que el proyecto Supabase usado aquí sea el mismo proyecto de **producción** real (no tengo forma de confirmar esto desde este entorno)
- Entrega real de email/push (las filas de `notifications` se crean correctamente, pero el envío real no se verificó)
- Configuración de dominio/DNS/hosting de producción
- Backups, monitoreo, o alertas configuradas

**Recomendación real:** antes de dar de alta a una compañía de pago real, alguien debe repetir el flujo crítico manualmente **en la UI real de producción**, con el proyecto Supabase de producción confirmado.

---

## ✅ Verificado con datos reales — funciona

| Paso | RPC/mecanismo | Resultado |
|---|---|---|
| KCC crea compañía con Commercial Setup (plan, complimentary) | `create_organization_with_commercial_setup()` | PASS — atómico, sin org huérfana si falla |
| Alta de owner/técnico/customer | `organization_memberships` | PASS |
| Customer creado | `customers` (RLS) | PASS |
| Vessel creado | `vessels` (RLS) | PASS |
| Customer envía service request | `service_requests` (RLS) | PASS |
| Staff acepta y convierte a work order | `accept_service_request()` + `convert_service_request_to_work_order()` | PASS |
| Ciclo completo de transición de estado | `transition_work_order()` — **11 transiciones reales**, ver hallazgo abajo | PASS |
| Asignación de técnico | `assignments` | PASS |
| Técnico sube foto + nota visible al customer | `media_assets` + `work_notes` | PASS |
| Customer ve su propio work order y nota visible (RLS) | policies de `work_orders`/`work_notes` | PASS |
| Activación de warranty al completar | `activate_warranty()` | PASS |
| Customer ve su propia warranty (RLS) | policy de `warranties` | PASS |
| Notificaciones generadas durante el flujo | `notification_rules` + trigger de `domain_events` | PASS (filas creadas — entrega real no verificada) |

## 🟡 Hallazgo real durante la verificación — no es un bug, es documentación faltante

La cadena real de transición de un work order **no es la que yo asumí al escribir el test la primera vez**. La secuencia real y completa, verificada, es:

```
request_received → triage → estimate → awaiting_approval → scheduled →
technician_assigned → en_route → checked_in → diagnosis → work_in_progress →
quality_control → invoice → payment → completed → (warranty opcional)
```

Dos puntos donde me equivoqué al principio (y que cualquier persona entrenando al staff real probablemente también asumiría mal):
- **`checked_in` va a `diagnosis`, nunca directo a `work_in_progress`.**
- **`invoice` va a `payment`, nunca directo a `completed`.**

Esto **no bloquea el go-live** — el sistema ya lo exige correctamente y las pantallas reales de `/work-orders/[id]` ya muestran solo las transiciones válidas para el rol de quien mira (verificado en fases anteriores). Pero **sí es material de entrenamiento real** que el equipo de KCC necesita antes de operar con una compañía de pago — documentado en `POST-LAUNCH-BACKLOG.md`.

## ❌ No verificado en esta pasada — requiere verificación manual en UI real antes de producción

- Login real (Supabase Auth) con las 4 personas del flujo, en un navegador real
- Subida real de un archivo a Storage (esta prueba insertó una fila de `media_assets` directamente, nunca subió un archivo real)
- Recepción real de una notificación push/email
- Flujo de pago real de customer (invoice → payment aquí solo cambió el status del work order — el módulo de `invoices`/`payments` de Phase 7 en sí no se ejercitó con datos reales en esta pasada)
- Comportamiento en dispositivo móvil real

## Veredicto

**Condicional. No es un "sí" sin reservas.** El núcleo del producto (los 19 pasos del flujo crítico) está genuinamente verificado y funciona con datos reales contra la base real. Pero esta verificación fue a nivel de base de datos, no de UI real, y no puedo confirmar que el proyecto Supabase de este sandbox sea el de producción. Recomiendo un pase manual en la UI real de producción antes de dar de alta a la primera compañía de pago — no como formalidad, sino porque genuinamente no se verificó esa capa en esta pasada.
