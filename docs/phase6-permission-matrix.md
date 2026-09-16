# Phase 6 — Matriz de permisos (Estimates & Change Orders)

Todo impuesto server-side (RLS o funciones `SECURITY DEFINER`), nunca solo en la UI. Verificado con tests adversariales reales.

| Acción | company_owner | company_admin | manager | technician | customer | kcc_admin |
|---|---|---|---|---|---|---|
| Ver estimates/change orders del tenant | ✅ | ✅ | ✅ | ❌ | ❌ (solo las propias) | ✅ |
| Crear estimate (draft) | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Editar líneas/detalles de un draft | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Enviar estimate al customer | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Revisar (crear nueva versión) | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Cancelar estimate | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Crear/enviar change order | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Aprobar/rechazar (propia, versión actual, no vencida, no superseded) | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ (no es su rol) |
| Convertir estimate aprobada en work order | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Ver el total autorizado agregado (original + change orders) | ✅ | ✅ | ✅ | ❌ | ✅ (de sus propios) | ✅ |

## Por qué `manager` sí puede crear/enviar estimates y change orders

Mismo criterio que el resto de Phase 5: `manager` usa el nivel de "staff operativo" (`is_org_staff()`) que ya rige work orders, catálogo, y equipo del día a día. El brief lo pide explícitamente ("manager: create/edit/send estimates... unless existing role policy says otherwise") — no hay ninguna política existente que lo excluya, así que queda incluido.

## Por qué technician nunca gestiona comercial

Decisión explícita del brief, reforzada en el diseño: `create_change_order()`/`create_draft_estimate()`/`send_estimate()` chequean `is_org_staff()`, que **no incluye** `technician`. Un técnico puede ver operativamente lo que su rol ya le permite (asignaciones, work orders propios) pero nunca crea, edita, envía, ni aprueba nada comercial — verificado con un test adversarial real (técnico bloqueado de crear change order).

## La aprobación es la única acción exclusiva del customer

Nadie más —ni siquiera `company_owner`— puede aprobar/rechazar una estimate en nombre del customer. Esto es intencional: la aprobación es la manifestación de consentimiento comercial del propio cliente, no una acción administrativa. `approve_estimate()`/`decline_estimate()` verifican `is_own_customer_record()` exclusivamente, sin ninguna puerta de staff/kcc_admin.
