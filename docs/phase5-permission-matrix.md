# Phase 5 — Matriz de permisos

Todo lo de acá abajo está impuesto server-side (RLS o funciones `SECURITY DEFINER`), nunca solo en la UI. La UI oculta controles como cortesía, pero si alguien manipulara el request directo, el servidor igual lo rechaza — verificado con tests adversariales reales.

| Acción | company_owner | company_admin | manager | technician | customer | kcc_admin |
|---|---|---|---|---|---|---|
| Ver `/company` dashboard | ✅ | ✅ | ✅ | ❌ | ❌ | (tiene el suyo propio en `/dashboard`) |
| Gestionar equipo (invitar/cambiar rol/desactivar) | ✅ (cualquier rol) | ✅ (solo manager/technician) | ❌ | ❌ | ❌ | ✅ |
| Invitar/asignar `kcc_admin` | ❌ (nadie) | ❌ | ❌ | ❌ | ❌ | ❌ (bloqueado incluso para kcc_admin vía estas funciones) |
| Cambiar el propio rol | ❌ (nadie) | ❌ | ❌ | ❌ | ❌ | ✅ (única excepción explícita) |
| Gestionar servicios/catálogo | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Gestionar configuración de la empresa (perfil/settings/ubicaciones) | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Revisar service requests (ver cola) | ✅ | ✅ | ✅ | ❌ | ❌ (solo los propios) | ✅ |
| Aceptar/rechazar/convertir service requests | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Asignar técnicos a work orders | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Gestionar citas (crear/cancelar) | ✅ | ✅ | ✅ | ❌ (solo check-in/out de las propias) | ❌ | ✅ |
| Transicionar work orders | ✅ (según `transition_work_order_transition_rules`) | ✅ | ✅ | ✅ (transiciones de campo) | ✅ (aprobar/cancelar/pagar, según la regla) | ✅ |
| Ver métricas operativas | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |

## Por qué manager no gestiona equipo (pero sí todo lo demás operativo)

`manager` usa el mismo nivel de "staff operativo" (`is_org_staff()`) que ya rige catálogo, citas, y work orders desde Phase 1 — incluye gestionar el perfil/settings/ubicaciones de la empresa, porque esos datos (nombre de contacto, huso horario, moneda) no son más sensibles que lo que ya gestiona todos los días.

**Gestión de equipo es la única excepción deliberada**, con su propia capa de funciones separada de `is_org_staff()`: decidir quién tiene acceso al sistema y con qué rol es un tipo de riesgo distinto (escalación de privilegios), así que quedó restringido a `company_owner`/`company_admin` únicamente, verificado con tests adversariales reales.

## Jerarquía de equipo, en una frase

`company_owner` > `company_admin` > el resto — un `company_admin` nunca puede tocar (invitar, cambiar rol, desactivar) a otro `company_owner` o `company_admin`, ni promover a nadie a esos niveles. Nadie puede tocar su propia fila de membership. La organización nunca puede quedarse sin ningún `company_owner` activo.
