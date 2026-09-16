# Phase 4B — Limitaciones conocidas

## Adjuntos de foto/video en Service Requests — NO implementado

El customer todavía no puede adjuntar fotos ni video al enviar un pedido de servicio (`/request-service`).

**Por qué:** `media_assets.work_order_id` es `NOT NULL`, y toda la RLS/acciones de Phase 2 (subida de fotos por técnicos, confirmación de upload, políticas de storage) están construidas asumiendo que ese campo siempre está presente. Extender la tabla para aceptar también `service_request_id` de forma segura — nullable + constraint que exija exactamente uno de los dos, más revisar cada policy que lo referencia — es un esfuerzo separado, no algo para sumar de paso en un pase de hardening.

**No se construyó ningún sistema de adjuntos alternativo** para esta fase, tal como se pidió explícitamente.

Cuando se aborde: el punto de entrada más simple sería extender `media_assets` con `service_request_id uuid references service_requests(id)`, un check constraint `(work_order_id is not null) != (service_request_id is not null)` (mutuamente excluyente), y una policy de lectura/escritura específica para que el customer suba a su propio pedido mientras siga en `submitted`/`under_review`.
