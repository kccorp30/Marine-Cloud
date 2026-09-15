# Marine Cloud Media Storage — Phase 0

| Aspecto | Detalle |
|---|---|
| Bucket | `vessel-media` |
| Público/privado | **Privado** (`public: false`) |
| Límite de tamaño | 50MB por archivo |
| Separación de dominio | Completamente separado de `lead-media` (bucket del sitio web kccorp.com) — nunca se mezcla media operativa (vessels, work orders) con media de marketing/leads. Confirmado: son buckets distintos, con RLS distinto, en el mismo proyecto Supabase compartido |
| Convención de ruta | `{organization_id}/{resto}` — el primer segmento de la ruta siempre es el UUID de la organización, usado directamente en las políticas RLS vía `storage.foldername(name)[1]` |
| RLS — lectura | Personal de compañía (`company_owner`, `company_admin`, `manager`, `technician`) de esa organización, o `kcc_admin`. **Customer no tiene acceso todavía** |
| RLS — escritura (insert) | Mismo grupo que lectura |
| RLS — borrado | Solo `company_owner`/`company_admin` de esa organización, o `kcc_admin` (más restrictivo que lectura/escritura a propósito) |

## Por qué customer no tiene acceso todavía (decisión Phase 0)

Falta la tabla `media_assets` (diseñada en Architecture v1.0, no creada todavía) con el campo `visibility` (`internal` / `customer_visible` / `kcc_only`) que decidirá exactamente qué ve un customer. Sin esa tabla, dar acceso amplio de storage a customers sería un error de exceso de permisos por adelantado. La decisión conservadora — cero acceso hasta que exista el modelo de visibilidad — es más segura que adivinar.

## Manejo futuro de visibilidad (Phase 1+, no implementado ahora)

Cuando se cree `media_assets`:
- `internal` → solo personal de la compañía + `kcc_admin`
- `customer_visible` → agrega al customer dueño del vessel/work order relacionado
- `kcc_only` → solo `kcc_admin`, ni siquiera el personal de la compañía

Esto se implementará como políticas RLS adicionales sobre `storage.objects` que hagan JOIN contra `media_assets.visibility`, no reemplazando las políticas actuales sino sumándose a ellas.

No se construyó nada de esto en Phase 0 a propósito — es exactamente lo que pediste no adelantar todavía.
