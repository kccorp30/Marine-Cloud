# Phase 7 — Matriz de permisos (Invoicing & Payments)

Todo impuesto server-side (RLS o funciones `SECURITY DEFINER`), nunca solo en la UI. Verificado con tests adversariales reales.

| Acción | company_owner | company_admin | manager | technician | customer | kcc_admin |
|---|---|---|---|---|---|---|
| Ver invoices/pagos del tenant | ✅ | ✅ | ✅ | ❌ | ❌ (solo las propias) | ✅ |
| Crear invoice/deposit invoice | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Emitir (issue) una invoice | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Registrar un pago manual | ✅ | ✅ | ✅ | ❌ | ❌ (nunca su propio pago) | ✅ |
| Reembolsar un pago manual | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Voidar una invoice | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Configurar términos de pago/depósito | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Conectar/desconectar Stripe | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Ver el resumen financiero del work order | ✅ | ✅ | ✅ | ❌ | ✅ (el propio) | ✅ |

## Por qué `manager` sí gestiona lo financiero

Mismo criterio que Phase 5/6: `manager` usa el nivel de "staff operativo" (`is_org_staff()`) que ya rige work orders, estimates, y equipo del día a día. El brief lo permite explícitamente ("manager: financial operations according to tenant policy unless current permissions say otherwise") — no hay ninguna política existente que lo excluya.

## Por qué technician nunca toca dinero

Ninguna función financiera (`record_manual_payment`, `void_invoice`, `refund_manual_payment`, `create_invoice`, `update_payment_settings`) acepta `technician` — todas chequean `is_org_staff()`, que no lo incluye. El technician sí puede, indirectamente, disparar que un work order llegue al estado `invoice` (vía sus transiciones operativas normales), pero nunca crea, edita, ni cobra nada.

## La única acción financiera exclusiva del customer

Ninguna, en esta fase — el pago online vía Stripe (la única acción que el customer *iniciaría* directamente) no está implementado en Phase 7 (ver limitaciones). El customer solo lee su balance y las instrucciones de pago; el registro real de cualquier pago siempre lo hace staff.
