# Anfitrión (EventosApp)

App de invitaciones y confirmación de asistencia (RSVP) para eventos: baby shower, cumpleaños, boda, bautizo, pollada.
Los anfitriones crean eventos, envían invitaciones por WhatsApp y ven quién confirma y qué regalo eligió.
Interfaz y mensajes en español (Perú). Zona horaria de negocio: America/Lima.

## Arquitectura

- **Frontend**: archivos estáticos sin framework ni build, publicados en Cloudflare Pages (`anfitrion.pages.dev`)
  con cada push a `main`. Cloudflare quita el `.html` de las URLs (`/app.html` → `/app`).
  - `index.html`: portada (sin código) e invitación pública (`?codigo=XXXXXX`).
  - `app.html`: panel de anfitriones y administración (router por hash `#/...`).
  - `comun.js`: configuración, utilidades compartidas y la función `api(accion, datos)`, que traduce cada acción
    a Supabase y devuelve objetos en camelCase (`salida()` convierte snake_case → camelCase y formatea fechas).
  - Librerías por CDN (jsdelivr): `@supabase/supabase-js@2`, `sortablejs@1.15` (solo en `app.html`).
- **Backend**: Supabase (Postgres, región São Paulo). No hay servidor propio: la lógica vive en funciones SQL (RPC),
  triggers y políticas RLS.
- **Auth**: Supabase Auth con Google (`signInWithIdToken`, botón de Google Identity Services) y correo + contraseña
  con código de 6 dígitos (plantillas con `{{ .Token }}`).
- **Correo**: SMTP de Gmail (`anfitrionapp.avisos@gmail.com`) configurado en Supabase. Edge Function
  `supabase/functions/avisos` preparada para avisos por correo (pendiente de desplegar).
- **Keep-alive**: `.github/workflows/supabase-keepalive.yml` llama a `public.ping()` cada 3 días.

## Base de datos

Tablas: `perfiles`, `eventos`, `invitados`, `regalos`, `colaboradores`.

- Estados de invitado: `'Pendiente'`, `'Confirmado'`, `'No asistirá'` (texto exacto: el frontend depende de ellos).
- Roles de evento: `dueno`, `admin`, `coorganizador`, `lectura`, `registrador`, `mensajero` (ver `permisos_rol`).
  Permisos con `public.puede(evento_id, permiso)` y `public.exigir_permiso(...)`.
- Escritura directa solo en columnas de formulario (GRANT por columna). Estado, respuestas, dueño, autoría y orden
  cambian únicamente por funciones `security definer`.
- Errores de negocio: `raise exception '<mensaje en español>' using hint = '<CODIGO>'`.
  `comun.js` usa el hint como `e.codigo` (p. ej. `CERRADO`, `RESPONDIDA`, `REGALO_LLENO`, `VALIDACION`, `DEMO`).
- Fechas de negocio en hora de Lima: `public.hoy_lima()`.

Funcionalidades con reglas propias:

- **Evento de ejemplo**: `eventos.es_demo = true`. Se crea al registrarse (trigger en `perfiles`), no cuenta para
  la cuota, máximo 10 invitados, sin equipo. El usuario lo borra cuando quiere.
- **Recordatorios**: `invitados.recordatorios` y `ultimo_recordatorio`, vía `marcar_recordado()`.
  Una respuesta marca automáticamente la invitación como enviada.
- **Imagen de fondo**: `eventos.imagen_fondo` (URL `https://`, opcional). `urlImagenDirecta()` en `comun.js`
  convierte enlaces de Google Drive a `https://lh3.googleusercontent.com/d/<ID>`.
  En la invitación, con imagen se aplica `body.con-fondo`: sin tarjeta blanca, velo oscuro y texto blanco.
- **Orden de regalos**: `regalos.orden`. Los nuevos van al final (trigger `validar_regalo`).
  Se reordena con `ordenar_regalos(evento_id, ids[])` (arrastrar ⠿, flechas del teclado, botones ⤒ ⤓).
  Todos los listados ordenan por `orden, creado_en`.
- **Aporte por Yape / Plin**: es un regalo más con `regalos.tipo = 'aporte'` (los físicos son `'objeto'`), con
  `aporte_numero` (9 dígitos, empieza con 9), `aporte_titular` y `aporte_apps` (`yape` | `plin` | `ambos`).
  No tiene cupo (se ignora `cupo`) y es excluyente con un regalo físico (cada invitado elige un solo `regalo_id`).
  La invitación muestra número, titular y botón "Copiar número".
- **Selector de regalos en la invitación**: placeholder oculto "Elige un regalo", luego los regalos en orden y al
  final "Aún no decido" (valor `sin-regalo`, que se envía como sin regalo).

## Migraciones

En `supabase/migrations/` (ya aplicadas en producción, en este orden):

1. `20261007000000_linea_base.sql`: esquema completo (equivale a las antiguas 0001–0004).
2. `20261008000000_imagen_fondo_evento.sql`
3. `20261008010000_orden_regalos.sql`
4. `20261008020000_aporte_yape_plin.sql`

Al reemplazar una función existente, parte de su **última versión** (la migración más reciente que la redefine),
no de la línea base.

## Reglas para cambios en la base de datos

1. **Nunca edites una migración ya aplicada.** Cada cambio va en una migración nueva:
   `npx supabase migration new <nombre_descriptivo>`.
2. Usa `create or replace function`, `add column if not exists`, `drop trigger if exists`,
   `drop constraint if exists`, para que el script sea seguro de reejecutar.
3. Funciones nuevas: `security definer` + `set search_path = ''` + nombres calificados (`public.tabla`, `auth.uid()`).
   Revoca `execute` de `public, anon` y concede solo a los roles necesarios.
4. Tablas o columnas nuevas: RLS activo, políticas y GRANT explícitos (el proyecto NO expone tablas
   automáticamente). Columnas editables desde el navegador: `grant insert (col), update (col) ... to authenticated`.
5. Si cambias la forma de los datos que devuelve una RPC, revisa su uso en `comun.js`, `app.html` e `index.html`.
6. `npx supabase db push` aplica en **producción** (no hay entorno de pruebas). Muestra el SQL y pide
   confirmación antes de ejecutarlo.
7. **Orden de despliegue**: primero la migración (`db push`), después el frontend (commit + push). Si la web nueva
   llega antes que la columna, guardar falla.

## Reglas para el frontend

1. **`comun.js` debe conservar la publishable key real** en `APP_CONFIG.SUPABASE_KEY`
   (`sb_publishable_...`). Nunca la reemplaces por un texto de ejemplo: todo el login fallaría con
   `401 UNAUTHORIZED_INVALID_API_KEY`.
2. Toda llamada a datos pasa por `api()` en `comun.js`; las pantallas no usan `sb` directamente.
3. Escapa todo texto de usuario con `esc()` antes de insertarlo en HTML.
4. Diseña para celular primero: revisa a 390 px de ancho (en `app.html` hay reglas `@media (max-width: 600px)`
   y `720px`). La invitación se abre casi siempre desde WhatsApp en el celular.
5. Accesibilidad: botones con `aria-label` cuando solo tienen ícono, foco visible, alternativa de teclado
   para el arrastre, y respetar `prefers-reduced-motion`.
6. Nunca incluyas en el repo claves `sb_secret_...`, contraseñas ni el secreto de los webhooks.
   La publishable key y el Google Client ID son públicos por diseño.

## Comandos

En PowerShell, si los scripts están bloqueados, usa `npx.cmd` en lugar de `npx`.

- Ver migraciones locales vs remotas: `npx supabase migration list`
- Crear migración: `npx supabase migration new <nombre>`
- Aplicar en producción: `npx supabase db push`

## Pendientes conocidos

- Desplegar la Edge Function `avisos` (secretos + webhooks). Gmail ya bloqueó la cuenta de envío una vez:
  considerar Brevo (o Resend con dominio propio).
- Backups automáticos de la BD (el plan gratuito de Supabase no los incluye).
- Con dominio propio: pases QR, Ley 29733 de protección de datos, recordatorios automáticos.
