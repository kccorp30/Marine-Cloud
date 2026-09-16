# Phase 10 — KCC Control Center, Company Network & Compensation

## Paso 0 — qué ya existía y se reusó
`organizations.status`, `organization_settings`, `organization_locations`, `work_orders.kcc_generated`, la policy `kcc_admin_creates_orgs`, y sobre todo **`invite_team_member()`** y **`change_member_role()`** ya existían y cubrían exactamente lo que esta fase pedía. `change_member_role()` se reusa tal cual para asignación de owner/admin — no se construyó una versión competidora. `invite_team_member()` se reusa dentro de `create_organization()` para invitar al owner — nunca se inventaron contraseñas.

## Arquitectura del KCC Control Center
`/dashboard` para `kcc_admin` muestra KPIs reales derivados de la base — nunca mock data. Distingue explícitamente **invoiced vs. paid vs. atribuido a KCC** (nunca la misma cifra). "Requiring attention" se define de forma conservadora y documentada: work orders en `waiting_parts`.

## Lifecycle de organización
`status` en `(active, inactive, suspended)`, CHECK real. **Hallazgo crítico durante la construcción**: `is_org_member()`/`is_org_staff()` nunca consideraban `organizations.status` — suspender una organización no habría tenido ningún efecto real de acceso en ninguna política RLS de todo el proyecto (Phases 0–9 inclusive). Se corrigió extendiendo esas dos funciones base, lo cual cascadea automáticamente a todas las policies existentes sin tocar ninguna individualmente. `kcc_admin` nunca pasa por ese chequeo — retiene acceso administrativo a una organización suspendida. Verificado con datos reales: una organización activa no cambia de comportamiento, una suspendida bloquea acceso operativo normal, los datos históricos se preservan siempre (nunca se borra nada).

## Company Network
`/companies` — lista real con filtros (status, búsqueda por nombre), creación transaccional (organización + settings + ubicación primaria opcional + invitación de owner opcional, todo o nada). `/companies/[organizationId]` — overview, ubicaciones, miembros (con cambio de rol real vía `change_member_role`), compensación, atribución KCC.

## Modelo de compensación
`compensation_agreements` — `percentage` exige `percentage_rate` (sin `fixed_amount`), `fixed` exige `fixed_amount` (sin `percentage_rate`) — CHECK constraint real, no solo validación de aplicación. `numeric` para todo lo monetario, nunca `float`. Un acuerdo nunca se sobreescribe — cambiarlo crea uno nuevo, el viejo queda como historial. Solapamiento de vigencias activas para la misma organización rechazado explícitamente.

## Regla de snapshot de atribución (determinística, documentada)
El acuerdo que aplica a un work order `kcc_generated=true` es el vigente en **`work_orders.created_at`** — nunca el acuerdo "actual" al momento del cálculo. Una vez creada la atribución (`kcc_revenue_attributions`), sus parámetros quedan congelados para siempre, aunque el acuerdo cambie después. `basis_amount` se calcula reusando `get_work_order_authorized_total()` de Phase 7. `status='snapshot'` siempre — **nunca se marca como pagada**, porque Stripe/KCC Ledger todavía no existen; eso es explícitamente una fase futura. Idempotente vía `unique(work_order_id)`.

## RLS
`compensation_agreements` y `kcc_revenue_attributions`: solo `kcc_admin` lee — ni siquiera `company_owner` ve su propio acuerdo de compensación (es información de plataforma). Ninguna mutación directa en ninguna tabla nueva — todo pasa por funciones `SECURITY DEFINER` con su propio chequeo de autorización.

## RPCs
`create_organization`, `set_organization_status`, `create_compensation_agreement`, `deactivate_compensation_agreement`, `attribute_kcc_work` — todos narrows, ninguno acepta JSON arbitrario ni actualiza columnas de confianza directo.

## Domain events
`ORGANIZATION_CREATED`, `ORGANIZATION_ACTIVATED`, `ORGANIZATION_SUSPENDED`, `ORGANIZATION_REACTIVATED`, `COMPENSATION_AGREEMENT_CREATED`, `COMPENSATION_AGREEMENT_CHANGED`, `KCC_WORK_ATTRIBUTED` — inspeccionados los nombres existentes antes de crearlos, ninguno duplicado. Owner/admin assignment usa el evento ya existente `TEAM_MEMBER_ROLE_CHANGED` (de `change_member_role()`) — no se creó `ORGANIZATION_OWNER_ASSIGNED`/`ORGANIZATION_ADMIN_ASSIGNED` por separado, ya que serían un duplicado exacto de ese evento.

## UI / rutas
`/dashboard` (real para kcc_admin), `/companies` (red real), `/companies/[organizationId]` (detalle completo).

## Tests
`tests/rls/phase10-kcc-control-tests.sql` — **21/21 PASS**, corridos en vivo de punta a punta desde el archivo guardado.

## Regresión
Phase 3B, 4B, 5, 6, 7, 8, 9, y `transition_work_order` — **8/8 PASS**.

## Bugs reales encontrados y corregidos durante la construcción
1. `is_org_member()`/`is_org_staff()` no consideraban `organizations.status` — corregido, cascada automática, verificado.
2. Dos errores propios de sintaxis TypeScript/anclaje de `str_replace` atrapados por el build antes de darlos por buenos.

## Explícitamente NO implementado en esta fase (diferido)
- Stripe Connect (flujo real de proveedor)
- KCC Ledger / settlement real de comisiones
- Conversión de leads del sitio web → Marine Cloud
- GPS en vivo
- QC, Warranty, Vessel Passport
- Luz

`kcc_revenue_attributions.status` nunca es `'finalized'` en esta fase — ese estado queda reservado para cuando exista un flujo de settlement real.

---

## Hardening final (migraciones 143–154)

### Resolución histórica de compensación (143–144)
`active` ahora significa "operativo hoy", **nunca** borra aplicabilidad histórica. La resolución para atribución usa **solo** el rango `effective_from`/`effective_until`. **EXCLUDE constraint real con `btree_gist`** (`excl_compensation_agreements_no_overlap`) impide solapamiento a nivel de base para TODO acuerdo de una organización, activo o inactivo. Al crear un acuerdo que reemplaza uno abierto, el anterior se cierra automáticamente en `nuevo.effective_from - 1 día` y pasa a `active=false` — nunca queda una vigencia ambigua.

### Camino único de escritura para `kcc_generated` (145–146, 151)
Ni siquiera `kcc_admin` puede setear `kcc_generated=true` con un INSERT/UPDATE directo — el trigger guard solo deja pasar el cambio si un flag *local a la transacción* (`app.kcc_generated_via_trusted_rpc`) está activo, y **solo** `set_work_order_kcc_generated()` lo activa. Este RPC crea el flag y la atribución en la misma transacción; si no hay acuerdo vigente, ambos revierten juntos. Invariante real: **`kcc_generated=true` nunca puede existir sin una fila en `kcc_revenue_attributions`**.

### Auditoría de suspensión completa (147, 152)
Además de `is_org_member()`/`is_org_staff()` (fix anterior) y `is_assigned_to_work_order()`/`is_customer_of_work_order()`/`is_own_customer_record()` (fix anterior), se auditaron **todas** las policies RLS del proyecto con `auth.uid()` crudo. Se encontraron y corrigieron 9 policies con una rama OR sin pasar por los helpers ya corregidos: `assignments`, `check_ins`, `customer_relationships`, `customers`, `measurements`, `technician_relationships` (x2), `time_entries` (x2), `work_notes`. Las policies de storage `vessel-media` ya usaban exclusivamente los helpers corregidos — sin cambios necesarios. `organization_memberships` y `profiles`: excepción intencional documentada — un usuario siempre ve su propia membresía/perfil, no es acceso operativo, es identidad básica.

**Matriz de suspensión (verificada con datos reales para cada rol):**

| Rol | Acceso durante suspensión |
|---|---|
| kcc_admin | Retiene acceso administrativo completo |
| company_owner/admin/manager | Bloqueado |
| technician asignado | Bloqueado |
| customer | Bloqueado |

### Gestión de ubicaciones (150, 153–154)
Índice único parcial real (`uq_organization_locations_one_primary`) — invariante de una sola primaria a nivel de base. `edit_location()`/`deactivate_location()` reusan `organization_locations.deleted_at` (soft-delete ya existente) — nunca hard-delete. La primaria no puede desactivarse sin designar atómicamente una nueva. `kcc_admin` ve ubicaciones desactivadas (auditoría), staff normal no.

### Auditoría de owner/admin
Confirmado con datos reales: `trg_audit_organization_memberships` (trigger genérico ya existente) audita todo cambio de rol con actor/antes/después/organización/timestamp — no se duplicó nada.

### Migraciones agregadas en este hardening
143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154.
