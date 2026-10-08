# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
- **Keep-alive**: `.github/workflows/supabase-keepalive.yml` llama a `public.ping()` cada 3 días
  (usa los secrets `SUPABASE_URL` y `SUPABASE_KEY` del repo; no borres ni renombres `ping()`).
- No hay build, linter ni tests. Las páginas cargan `supabase-js` desde jsDelivr y `comun.js` como script global
  (sin módulos), y apuntan directamente al proyecto de producción.
- Archivos heredados: `index.ts` en la raíz es una copia de `supabase/functions/avisos/index.ts` (la fuente real),
  y `appsscript.json` viene de la versión anterior con Google Apps Script. Ninguno de los dos se usa.

## Capa `api()` en `comun.js`

- `api(accion, datos)` busca la acción en el mapa `ACCIONES`. Cada acción llama a una RPC (`rpc(...)`) o hace una
  consulta directa (`consulta(sb.from(...))`). Si la acción no está en la lista `PUBLICAS`, primero exige sesión.
  Una acción nueva que deba funcionar sin sesión (por ejemplo, desde la invitación pública) hay que añadirla a `PUBLICAS`.
- `salida()` convierte las claves de snake_case a camelCase, los timestamps a `"yyyy-MM-dd HH:mm"` en hora de Lima
  y `hora` a `"HH:mm"`. `rpc()` la aplica sola; con `consulta()` hay que llamarla a mano.
- `traducirError()` pasa los errores de Postgres, PostgREST y Auth a `{codigo, message}`. Solo toma el `hint` SQL como
  código si cumple `^[A-Z_]+$`, así que los hints nuevos deben ir en MAYÚSCULAS_CON_GUION_BAJO.
- La configuración por tipo de evento (fuente, colores, emoji) está en `TIPOS_EVENTO`. Un tipo nuevo también debe
  estar permitido en la BD.

## Permisos en el frontend

La RPC del evento devuelve `rol` y `permisos` (el arreglo de `public.permisos_rol(rol)`). `app.html` muestra u oculta
cada acción con `ev.permisos.includes('<permiso>')`. Si agregas o cambias un permiso, actualiza `permisos_rol` en una
migración nueva y revisa esas llamadas en `app.html`. Las descripciones de los roles también están repetidas en
`ROLES` de la Edge Function `avisos`.

## Edge Function `avisos`

Dos Database Webhooks la llaman: `perfiles` UPDATE (solicitud de cuenta, aprobada o rechazada) y `colaboradores`
INSERT (te sumaron al equipo). Valida el header `x-aviso-secreto` contra el secret `AVISO_SECRETO`. Envía por Gmail
en el puerto 465, porque Supabase bloquea 25 y 587. Sus secrets (`SMTP_USER`, `SMTP_PASS`, `APP_URL`, `AVISO_SECRETO`)
están en Supabase, no en el repo.

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
- Publicar la Edge Function (también es producción, pide confirmación): `npx.cmd supabase functions deploy avisos`
- Frontend: no hay que compilar nada. Se publica al hacer push a `main`.
