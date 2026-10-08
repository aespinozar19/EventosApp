# Anfitrión (EventosApp)

App de invitaciones y confirmación de asistencia (RSVP) para eventos: baby shower, cumpleaños, boda, bautizo, pollada.
Anfitriones crean eventos, envían invitaciones por WhatsApp y ven quién confirma y qué regalo reserva.

## Arquitectura

- **Frontend**: archivos estáticos sin framework ni build, publicados en Cloudflare Pages (`anfitrion.pages.dev`)
  con cada push a `main`.
  - `index.html`: portada (sin código) e invitación pública (`?codigo=XXXXXX`).
  - `app.html`: panel de anfitriones y administración (router por hash `#/...`).
  - `comun.js`: configuración, utilidades y la función `api(accion, datos)`, que traduce cada acción a Supabase
    y devuelve objetos en camelCase.
- **Backend**: Supabase (Postgres, región São Paulo). No hay servidor propio: la lógica vive en funciones SQL (RPC),
  triggers y políticas RLS.
- **Auth**: Supabase Auth con Google (`signInWithIdToken`) y correo + contraseña con código de 6 dígitos.
- **Correo**: SMTP de Gmail configurado en Supabase. Edge Function `supabase/functions/avisos` para avisos por correo.
- **Keep-alive**: `.github/workflows/supabase-keepalive.yml` llama a `public.ping()` cada 3 días.

## Base de datos

- Tablas: `perfiles`, `eventos`, `invitados`, `regalos`, `colaboradores`.
- Estados de invitado: `'Pendiente'`, `'Confirmado'`, `'No asistirá'` (texto exacto, el frontend depende de ellos).
- Roles de evento: `dueno`, `admin`, `coorganizador`, `lectura`, `registrador`, `mensajero` (ver `permisos_rol`).
- Los permisos se verifican con `public.puede(evento_id, permiso)` y `public.exigir_permiso(...)`.
- Escritura directa solo en columnas de formulario (GRANT por columna). Estado, respuestas, dueño y autoría
  cambian únicamente por funciones `security definer`.
- Errores de negocio: `raise exception '<mensaje en español>' using hint = '<CODIGO>'`.
  El frontend usa el hint como `e.codigo`.
- Fechas de negocio en hora de Lima: usar `public.hoy_lima()`.
- Eventos de ejemplo: `eventos.es_demo = true`; no cuentan para la cuota, máximo 10 invitados, sin equipo.

## Reglas para cambios en la base de datos

1. **Nunca edites una migración ya aplicada** (incluida `20261007000000_linea_base.sql`).
   Cada cambio va en una migración nueva: `npx supabase migration new <nombre_descriptivo>`.
2. Usa `create or replace function`, `add column if not exists`, `drop trigger if exists`, para que el script
   sea seguro de reejecutar.
3. Funciones nuevas: `security definer` + `set search_path = ''` + nombres calificados (`public.tabla`, `auth.uid()`).
   Revoca `execute` de `public, anon` y concede solo a los roles necesarios.
4. Tablas nuevas: activa RLS, crea políticas y concede permisos explícitos (el proyecto NO expone tablas
   automáticamente).
5. Si cambias la forma de los datos que devuelve una RPC, revisa su uso en `comun.js` y `app.html`/`index.html`.
6. Nunca incluyas en el repo claves `sb_secret_...`, contraseñas, ni el secreto de los webhooks.
   La `sb_publishable_...` y el Google Client ID de `comun.js` son públicos por diseño.
7. `npx supabase db push` aplica en **producción** (no hay entorno de pruebas). Muestra el SQL y pide
   confirmación antes de ejecutarlo.

## Comandos (Windows / PowerShell: usar `npx.cmd`)

- Ver migraciones locales vs remotas: `npx.cmd supabase migration list`
- Crear migración: `npx.cmd supabase migration new <nombre>`
- Aplicar en producción: `npx.cmd supabase db push`
