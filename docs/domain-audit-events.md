# domain_events & audit_events — Phase 0

Ambas tablas existen en la base en vivo Y están representadas en `migrations/010_domain_and_audit_events.sql`.

## domain_events

| Aspecto | Detalle |
|---|---|
| Propósito | Acontecimientos operativos (ej. `WORK_ORDER_CREATED`) — fase actual: solo infraestructura, sin eventos de negocio todavía (llegan en Phase 1+) |
| Columnas | `id, organization_id, event_type, entity_type, entity_id, payload (jsonb), actor_profile_id (nullable), occurred_at` |
| Índices | `(organization_id, occurred_at desc)`, `(entity_type, entity_id)`, `(event_type)` |
| Límite de tenant | `organization_id` — obligatorio, cada evento pertenece a una organización |
| RLS | Habilitado. SELECT: miembros activos de la organización + `kcc_admin`. **Sin policy de INSERT** — la tabla nunca acepta insert directo del cliente |
| Escritores permitidos | Únicamente `log_domain_event()` (`SECURITY DEFINER`), y solo si quien llama es miembro activo de esa organización o `kcc_admin` (verificado en migración 016) |

## audit_events

| Aspecto | Detalle |
|---|---|
| Propósito | Cambios sensibles — compliance, no operación |
| Columnas | `id, organization_id (nullable — null = acción cross-tenant de KCC), actor_profile_id, entity_type, entity_id, action, before (jsonb), after (jsonb), occurred_at` |
| Índices | `(organization_id, occurred_at desc)`, `(entity_type, entity_id)` |
| Límite de tenant | `organization_id` nullable a propósito — una acción de KCC Admin que no pertenece a ninguna compañía específica (ej. una decisión de red) se audita con `organization_id = null`, visible solo para `kcc_admin` |
| RLS | Habilitado. SELECT: `kcc_admin` ve todo; `company_owner`/`company_admin` ven solo lo de su propia organización. **Sin policy de INSERT** |
| Escritores permitidos | `log_audit_event()` (`SECURITY DEFINER`) — si `organization_id` es null, solo `kcc_admin` puede escribir; si tiene organización, requiere ser staff de esa organización o `kcc_admin` |
| Inmutabilidad | **Sin políticas de UPDATE ni DELETE en absoluto** — ni siquiera `kcc_admin` puede modificar un registro de auditoría ya escrito desde la aplicación. Esto es intencional: un audit log que se puede editar no sirve como audit log |
| Trigger genérico | `trg_audit_row_change()` — reusable por cualquier tabla futura. Ya aplicado a `organization_memberships` (cambio de `role`/`status`) y `organizations` (cambio de `status`). Corregido en migración 015 para funcionar con tablas que no tienen columna `organization_id` propia (como `organizations` mismo) |

## Verificado con pruebas reales (no solo diseño)

- Insert directo a `domain_events` bloqueado (TEST 10 de la suite)
- `log_domain_event()` funciona para la organización propia, falla explícitamente para una ajena (TEST 11)
- El trigger de auditoría genera registros reales al cambiar `status` en `organizations` (confirmado en vivo durante Phase 0)
