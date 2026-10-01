# Sitio web editable desde Marine Cloud

El contenido del sitio público KCCORP se edita en **Marine Cloud → KCC Admin → Website**. No hace falta entrar a ningún otro sistema.

## Qué se edita ahí

| Sección | Para qué sirve |
|---|---|
| Ajustes generales | Nombre, titular de la página principal, teléfono, WhatsApp, correo, zonas donde trabajas, cifras de confianza (solo si son reales). |
| Servicios | Lo que vendes. Cada servicio tiene su página: `tusitio.com/services/<slug>`. |
| Landing pages de campañas | Una página por anuncio de Facebook: `tusitio.com/<ruta>`. |
| Proyectos reales | Trabajos terminados con fotos de antes y después. |
| Testimonios | Palabras reales de clientes, con su permiso. |

Además, la portada de **Website** muestra los leads de los últimos 30 días y cuántos vinieron de cada campaña.

## Reglas importantes

- **Todo lo nuevo nace como borrador.** Nada aparece en el sitio hasta que pulses **Publicar**.
- **Guardar ≠ Publicar.** Si algo ya está publicado, al guardar los cambios salen al sitio en segundos.
- **Testimonios:** la base de datos no deja publicar uno sin marcar "El cliente dio permiso".
- **Cifras:** "Años de experiencia" y "Trabajos realizados" solo aparecen si las llenas. Vacío = oculto.
- **Proyectos de ejemplo:** el sitio trae proyectos de muestra marcados "[example, placeholder]". En cuanto publiques **un** proyecto real, desaparecen todos.
- **Servicios:** en cuanto publiques servicios en Marine Cloud, esa es la única lista. Un servicio en borrador no se ve, ni siquiera por enlace directo.

## Puesta en marcha (una sola vez)

1. **Crear las tablas.** En Supabase → proyecto *kccorp-marine-cloud* → **SQL Editor** → **New query**, pega el contenido de `supabase/migrations/20261001000000_website_studio.sql` y pulsa **Run**.
2. **Cargar los textos borrador** (opcional, recomendado). Igual que el paso 1, con `supabase/seed/website-content-drafts.sql`. Crea 5 servicios y 2 landing pages en borrador, en inglés y español.
3. **Conectar app y sitio** (para que los cambios se vean en segundos):
   - Inventa una contraseña larga (por ejemplo, 40 letras y números al azar).
   - En Vercel, proyecto **Marine Cloud** → Settings → Environment Variables:
     - `WEBSITE_URL` = la dirección de tu sitio (ej. `https://kccorp.com`)
     - `WEBSITE_REVALIDATE_SECRET` = la contraseña inventada
   - En Vercel, proyecto **sitio web (kccorp-web)** → Settings → Environment Variables:
     - `REVALIDATE_SECRET` = **la misma** contraseña
     - `NEXT_PUBLIC_META_PIXEL_ID` = el ID de tu Pixel de Facebook (Administrador de eventos de Meta)
   - Vuelve a desplegar ambos proyectos (Deployments → ⋯ → Redeploy).
4. **Revisar y publicar.** En Marine Cloud → Website, corrige los textos que escribió Claude, sube fotos reales y pulsa **Publicar**.

## Usar una landing en un anuncio de Facebook

1. Publica la landing (ej. ruta `offers/marine-electrical`).
2. En el Administrador de anuncios, en "URL del sitio web" pon:
   `https://tusitio.com/offers/marine-electrical?utm_source=facebook&utm_campaign=electrical-oct-2026`
3. Usa en `utm_campaign` el mismo nombre que pusiste en la landing. Así, en Marine Cloud → Website, los leads aparecen agrupados por campaña.
4. Optimiza la campaña con el evento **Lead** (se envía cuando alguien completa el formulario).

## Cómo funciona por dentro

- El sitio lee las tablas `site_*` con la llave pública. La base solo entrega filas con `published = true` (RLS).
- Solo KCC Admin puede escribir (RLS `is_kcc_admin()`) y subir fotos al bucket público `site-media`.
- Al guardar, Marine Cloud llama `POST <sitio>/api/revalidate` con el secreto compartido. Si falla, el sitio se refresca solo cada 5 minutos.
- Si las tablas no existen o la base no responde, el sitio sigue mostrando su contenido incorporado; nunca queda en blanco.
- Prueba de seguridad local: `bash tests/rls/website-studio/run.sh` (21 comprobaciones).
