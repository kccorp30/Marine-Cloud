# Phase 8 — Matriz de permisos (Communications)

Todo impuesto server-side (RLS o funciones `SECURITY DEFINER`), nunca solo en la UI. Verificado con tests adversariales reales.

| Acción | company_owner | company_admin | manager | technician | customer | kcc_admin |
|---|---|---|---|---|---|---|
| Ver conversaciones/mensajes del tenant | ✅ | ✅ | ✅ | ❌ | ❌ (solo las propias) | ✅ |
| Crear conversación | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Enviar mensaje interno/operativo | ✅ | ✅ | ✅ | ❌ (solo vía `send_appointment_email` si está asignado) | ❌ | ✅ |
| Enviar email de estimate/invoice/payment receipt (**comercial**) | ✅ | ✅ | ✅ | ❌ nunca | ❌ | ✅ |
| Enviar confirmación de cita | ✅ | ✅ | ✅ | ✅ (solo si asignado a ese work order) | ❌ | ✅ |
| Crear/editar templates | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Configurar identidad de email (nombre, reply-to, firma) | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Verificar estado real del proveedor de email (`sender_email`/`verification_status`) | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (único actor autoritativo) |

## Por qué el technician tiene un permiso, no cero

El brief es explícito: "technician may send operational messages only if explicitly permitted; must not send commercial invoices/estimates". La única función de envío abierta a technician es `send_appointment_email()`, y solo cuando está realmente asignado al work order de esa cita (`is_assigned_to_work_order()`) — nunca un envío comercial, nunca a un work order ajeno.

## Por qué `is_commercial_sender()` es una función separada

`send_estimate_email`, `send_invoice_email`, y `send_payment_receipt_email` comparten el mismo chequeo (`is_commercial_sender`) en vez de repetir la lista de roles en cada una — un solo lugar donde ese límite se define y se prueba, igual que `is_org_staff()` en las fases anteriores.

## La identidad de email sigue el mismo patrón que Stripe (Phase 7)

`sender_email`/`verification_status`/`enabled` son autoritativos — nunca algo que el staff de una empresa pueda autoafirmar, para que ningún tenant pueda hacerse pasar por otro. Solo `kcc_admin` los toca, vía `set_email_provider_state()`. El staff sí controla `sender_name`/`reply_to_email`/`signature_text` — esos son de marca, no de identidad verificada.
