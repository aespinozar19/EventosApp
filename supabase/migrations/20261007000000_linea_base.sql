-- =====================================================================
-- AnfitrionApp · Línea base del esquema (estado de producción)
--
-- Equivale a aplicar, en orden, las migraciones 0001 a 0004:
--   0001 esquema inicial · 0002 respuesta marca enviado
--   0003 recordatorios   · 0004 evento de ejemplo
--
-- Generado con pg_dump (--schema=public --no-owner --schema-only) y probado
-- restaurándolo en una base vacía. A partir de aquí, cada cambio va en una
-- migración NUEVA; este archivo no se edita.
-- =====================================================================

--
-- PostgreSQL database dump
--

-- Dumped from database version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: admin_actualizar_usuario(uuid, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_actualizar_usuario(p_usuario_id uuid, p_cuota integer DEFAULT NULL::integer, p_activo boolean DEFAULT NULL::boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.exigir_admin();

  if p_cuota is not null and (p_cuota < 0 or p_cuota > 100) then
    raise exception 'El cupo de eventos debe ser un número entre 0 y 100.' using hint = 'VALIDACION';
  end if;
  if p_usuario_id = auth.uid() and p_activo is false then
    raise exception 'No puedes desactivar tu propia cuenta.' using hint = 'VALIDACION';
  end if;

  update public.perfiles
  set cuota_eventos = coalesce(p_cuota, cuota_eventos),
      activo        = coalesce(p_activo, activo)
  where id = p_usuario_id;

  if not found then
    raise exception 'Usuario no encontrado.' using hint = 'NO_EXISTE';
  end if;
  return public.perfil_publico(p_usuario_id);
end;
$$;

--
-- Name: admin_eventos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_eventos() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.exigir_admin();
  return coalesce((
    select jsonb_agg(
      to_jsonb(e) || jsonb_build_object(
        'owner_email', p.email,
        'total_invitaciones', (select count(*) from public.invitados i where i.evento_id = e.id))
      order by e.creado_en desc)
    from public.eventos e join public.perfiles p on p.id = e.owner_id
  ), '[]'::jsonb);
end;
$$;

--
-- Name: admin_revisar_usuario(uuid, text, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_revisar_usuario(p_usuario_id uuid, p_decision text, p_cuota integer DEFAULT NULL::integer, p_nota text DEFAULT ''::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.exigir_admin();

  if p_decision not in ('aprobar', 'rechazar') then
    raise exception 'Decisión no válida.' using hint = 'VALIDACION';
  end if;
  if p_usuario_id = auth.uid() then
    raise exception 'No puedes revisar tu propia cuenta.' using hint = 'VALIDACION';
  end if;
  if p_cuota is not null and (p_cuota < 0 or p_cuota > 100) then
    raise exception 'El cupo de eventos debe ser un número entre 0 y 100.' using hint = 'VALIDACION';
  end if;

  if p_decision = 'aprobar' then
    update public.perfiles
    set estado = 'aprobado', activo = true, nota_admin = '',
        cuota_eventos = coalesce(p_cuota, cuota_eventos),
        revisado_por = auth.uid(), fecha_revision = now()
    where id = p_usuario_id;
  else
    update public.perfiles
    set estado = 'rechazado', nota_admin = left(btrim(coalesce(p_nota, '')), 300),
        revisado_por = auth.uid(), fecha_revision = now()
    where id = p_usuario_id;
  end if;

  if not found then
    raise exception 'Usuario no encontrado.' using hint = 'NO_EXISTE';
  end if;
  return public.perfil_publico(p_usuario_id);
end;
$$;

--
-- Name: admin_usuarios(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_usuarios() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.exigir_admin();
  return coalesce((
    select jsonb_agg(public.perfil_publico(p.id)
      order by
        case p.estado when 'pendiente' then 0 when 'aprobado' then 1 when 'registrado' then 2 else 3 end,
        coalesce(p.fecha_solicitud, p.ultimo_acceso) desc nulls last)
    from public.perfiles p
  ), '[]'::jsonb);
end;
$$;

--
-- Name: crear_evento_demo(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crear_evento_demo(p_owner uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_nombre text;
  v_fecha  date := public.hoy_lima() + 30;
  v_ev     uuid;
  r_juego  uuid;
  r_libro  uuid;
  r_tarjeta uuid;
begin
  if exists (select 1 from public.eventos where owner_id = p_owner and es_demo) then
    return null;
  end if;
  select nullif(nombre, '') into v_nombre from public.perfiles where id = p_owner;

  insert into public.eventos (owner_id, es_demo, tipo, titulo, anfitriones, fecha, hora, lugar, direccion,
                              fecha_limite, tipos_permitidos, max_personas_default)
  values (p_owner, true, 'cumpleanos', 'Cumpleaños de ejemplo', coalesce(v_nombre, 'Tu nombre'),
          v_fecha, '16:00', 'Casa de la familia', 'Av. Ejemplo 123, Lima',
          v_fecha - 7, array['adultos', 'ninos'], 3)
  returning id into v_ev;

  insert into public.regalos (evento_id, nombre, cupo) values (v_ev, 'Juego de mesa', 1)       returning id into r_juego;
  insert into public.regalos (evento_id, nombre, cupo) values (v_ev, 'Libro de cuentos', 2)    returning id into r_libro;
  insert into public.regalos (evento_id, nombre, cupo) values (v_ev, 'Tarjeta de regalo', 5)   returning id into r_tarjeta;

  insert into public.invitados
    (evento_id, nombre, max_personas, enviado, fecha_envio, estado, adultos, ninos, regalo_id,
     fecha_respuesta, recordatorios, ultimo_recordatorio, creado_por)
  values
    (v_ev, 'Familia Pérez',   4, true,  now() - interval '3 days', 'Confirmado',  2, 1, r_juego,   now() - interval '2 days', 0, null, p_owner),
    (v_ev, 'Tía Rosa',        1, true,  now() - interval '3 days', 'Confirmado',  1, 0, r_libro,   now() - interval '1 day',  0, null, p_owner),
    (v_ev, 'Primo Luis',      2, true,  now() - interval '3 days', 'No asistirá', 0, 0, r_tarjeta, now() - interval '1 day',  0, null, p_owner),
    (v_ev, 'Abuela Carmen',   2, true,  now() - interval '3 days', 'Pendiente',   0, 0, null,      null,                      1, now() - interval '1 day', p_owner),
    (v_ev, 'Vecinos García',  3, false, null,                      'Pendiente',   0, 0, null,      null,                      0, null, p_owner);

  return v_ev;
end;
$$;

--
-- Name: crear_perfil_nuevo_usuario(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crear_perfil_nuevo_usuario() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  insert into public.perfiles (id, email, nombre)
  values (
    new.id,
    lower(new.email),
    left(coalesce(
      nullif(new.raw_user_meta_data ->> 'nombre', ''),
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      nullif(new.raw_user_meta_data ->> 'name', ''),
      split_part(new.email, '@', 1)
    ), 80)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

--
-- Name: demo_al_crear_perfil(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.demo_al_crear_perfil() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  begin
    perform public.crear_evento_demo(new.id);
  exception when others then
    raise warning 'No se pudo crear el evento de ejemplo para %: %', new.email, sqlerrm;
  end;
  return new;
end;
$$;

--
-- Name: es_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.es_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1 from public.perfiles
    where id = auth.uid() and rol = 'admin' and estado = 'aprobado' and activo
  );
$$;

--
-- Name: exigir_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exigir_admin() RETURNS void
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.es_admin() then
    raise exception 'Solo el administrador puede hacer esto.' using hint = 'PROHIBIDO';
  end if;
end;
$$;

--
-- Name: exigir_permiso(uuid, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exigir_permiso(p_evento_id uuid, p_permisos text[]) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_rol text := public.rol_en_evento(p_evento_id);
begin
  if v_rol is null then
    raise exception 'No tienes acceso a este evento.' using hint = 'PROHIBIDO';
  end if;
  if not (public.permisos_rol(v_rol) && p_permisos) then
    raise exception 'Tu rol en este evento no permite hacer esto.' using hint = 'PROHIBIDO';
  end if;
  return v_rol;
end;
$$;

--
-- Name: generar_codigo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generar_codigo() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  abc constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  c text;
begin
  loop
    c := '';
    for k in 1..6 loop
      c := c || substr(abc, 1 + floor(random() * 32)::int, 1);
    end loop;
    exit when not exists (select 1 from public.invitados where codigo = c);
  end loop;
  return c;
end;
$$;

--
-- Name: hoy_lima(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.hoy_lima() RETURNS date
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select (now() at time zone 'America/Lima')::date;
$$;

--
-- Name: limitar_evento_demo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.limitar_evento_demo() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not exists (select 1 from public.eventos where id = new.evento_id and es_demo) then
    return new;
  end if;

  if tg_table_name = 'colaboradores' then
    raise exception 'En el evento de ejemplo no se puede invitar a un equipo. Hazlo en tu propio evento.'
      using hint = 'DEMO';
  end if;

  if (select count(*) from public.invitados where evento_id = new.evento_id) >= 10 then
    raise exception 'El evento de ejemplo admite hasta 10 invitados. Crea tu propio evento para invitar a más personas.'
      using hint = 'DEMO';
  end if;
  return new;
end;
$$;

--
-- Name: listar_equipo(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.listar_equipo(p_evento_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_dueno jsonb;
begin
  perform public.exigir_permiso(p_evento_id, array['equipo']);

  select jsonb_build_object('email', p.email, 'nombre', p.nombre) into v_dueno
  from public.eventos e join public.perfiles p on p.id = e.owner_id
  where e.id = p_evento_id;

  return jsonb_build_object(
    'dueno', v_dueno,
    'colaboradores', coalesce((
      select jsonb_agg(
        to_jsonb(c) || jsonb_build_object(
          'nombre',       coalesce(p.nombre, ''),
          'tiene_cuenta', p.id is not null)
        order by c.creado_en)
      from public.colaboradores c
      left join public.perfiles p on p.email = c.email
      where c.evento_id = p_evento_id
    ), '[]'::jsonb)
  );
end;
$$;

--
-- Name: listar_invitados(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.listar_invitados(p_evento_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_rol    text := public.exigir_permiso(p_evento_id, array['ver_invitados', 'ver_invitados_propios']);
  v_todos  boolean := 'ver_invitados' = any(public.permisos_rol(v_rol));
begin
  return coalesce((
    select jsonb_agg(
      to_jsonb(i)
      || jsonb_build_object(
           'regalo_nombre', coalesce(r.nombre, ''),
           'creado_por',    coalesce(pc.email, po.email))
      order by i.creado_en desc)
    from public.invitados i
    join public.eventos e   on e.id = i.evento_id
    join public.perfiles po on po.id = e.owner_id
    left join public.perfiles pc on pc.id = i.creado_por
    left join public.regalos r   on r.id = i.regalo_id
    where i.evento_id = p_evento_id
      and (v_todos or coalesce(i.creado_por, e.owner_id) = auth.uid())
  ), '[]'::jsonb);
end;
$$;

--
-- Name: listar_regalos(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.listar_regalos(p_evento_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.exigir_permiso(p_evento_id, array['ver_resumen', 'regalos']);

  return coalesce((
    select jsonb_agg(
      to_jsonb(r)
      || jsonb_build_object(
           'reservados',    coalesce(array_length(x.nombres, 1), 0),
           'reservado_por', to_jsonb(coalesce(x.nombres, array[]::text[])))
      order by r.creado_en)
    from public.regalos r
    left join lateral (
      select array_agg(i.nombre order by i.fecha_respuesta) as nombres
      from public.invitados i
      where i.regalo_id = r.id and i.estado <> 'Pendiente'
    ) x on true
    where r.evento_id = p_evento_id
  ), '[]'::jsonb);
end;
$$;

--
-- Name: marcar_enviado(uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marcar_enviado(p_invitado_id uuid, p_enviado boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_evento uuid;
begin
  select evento_id into v_evento from public.invitados where id = p_invitado_id for update;
  if not found then
    raise exception 'Ese invitado ya no existe.' using hint = 'NO_EXISTE';
  end if;
  perform public.exigir_permiso(v_evento, array['enviar']);

  update public.invitados
  set enviado = coalesce(p_enviado, false),
      fecha_envio = case when p_enviado then now() end
  where id = p_invitado_id;

  return jsonb_build_object('enviado', coalesce(p_enviado, false));
end;
$$;

--
-- Name: marcar_recordado(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marcar_recordado(p_invitado_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_evento uuid;
  v_inv    public.invitados;
begin
  select evento_id into v_evento from public.invitados where id = p_invitado_id for update;
  if not found then
    raise exception 'Ese invitado ya no existe.' using hint = 'NO_EXISTE';
  end if;
  perform public.exigir_permiso(v_evento, array['enviar']);

  update public.invitados
  set recordatorios       = recordatorios + 1,
      ultimo_recordatorio = now()
  where id = p_invitado_id
  returning * into v_inv;

  return jsonb_build_object(
    'recordatorios',       v_inv.recordatorios,
    'ultimo_recordatorio', v_inv.ultimo_recordatorio
  );
end;
$$;

--
-- Name: me(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.me() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v       public.perfiles;
  v_admin boolean;
begin
  update public.perfiles set ultimo_acceso = now()
  where id = auth.uid()
  returning * into v;

  if not found then
    raise exception 'No encontramos tu cuenta. Vuelve a iniciar sesión.' using hint = 'AUTH';
  end if;
  if not v.activo then
    raise exception 'Tu cuenta está suspendida. Comunícate con el administrador.' using hint = 'INACTIVO';
  end if;

  v_admin := v.rol = 'admin' and v.estado = 'aprobado';

  return jsonb_build_object(
    'email',                  v.email,
    'nombre',                 v.nombre,
    'estado',                 v.estado,
    'rol',                    case when v_admin then 'admin' else 'organizador' end,
    'cuota_eventos',          v.cuota_eventos,
    'eventos_usados',         (select count(*) from public.eventos where owner_id = v.id and not es_demo),
    'nota_admin',             case when v.estado = 'rechazado' then v.nota_admin else '' end,
    'tiene_password',         exists (select 1 from auth.users u
                                      where u.id = v.id and coalesce(u.encrypted_password, '') <> ''),
    'google_vinculado',       exists (select 1 from auth.identities i
                                      where i.user_id = v.id and i.provider = 'google'),
    'solicitudes_pendientes', case when v_admin
                                then (select count(*) from public.perfiles where estado = 'pendiente') else 0 end
  );
end;
$$;

--
-- Name: mi_email(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mi_email() RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select lower(coalesce(auth.jwt() ->> 'email', ''));
$$;

--
-- Name: mis_eventos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mis_eventos() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v         public.perfiles;
  v_email   text := public.mi_email();
  v_propios jsonb;
  v_n       int;
  v_comp    jsonb;
begin
  select * into v from public.perfiles where id = auth.uid();
  if not found or not v.activo then
    raise exception 'Inicia sesión para continuar.' using hint = 'AUTH';
  end if;

  select coalesce(jsonb_agg(
      to_jsonb(e)
      || jsonb_build_object(
           'rol', 'dueno',
           'owner_email', v.email,
           'total_invitaciones', (select count(*) from public.invitados i where i.evento_id = e.id),
           'confirmados', (select count(*) from public.invitados i where i.evento_id = e.id and i.estado = 'Confirmado'))
      order by e.es_demo, e.fecha), '[]'::jsonb)
  into v_propios
  from public.eventos e
  where e.owner_id = v.id;

  select count(*) into v_n from public.eventos where owner_id = v.id and not es_demo;

  select coalesce(jsonb_agg(
      to_jsonb(e)
      || jsonb_build_object('rol', c.rol, 'owner_email', p.email)
      || case when 'ver_resumen' = any(public.permisos_rol(c.rol)) then jsonb_build_object(
           'total_invitaciones', (select count(*) from public.invitados i where i.evento_id = e.id),
           'confirmados', (select count(*) from public.invitados i where i.evento_id = e.id and i.estado = 'Confirmado'))
         else '{}'::jsonb end
      order by e.fecha), '[]'::jsonb)
  into v_comp
  from public.colaboradores c
  join public.eventos e  on e.id = c.evento_id
  join public.perfiles p on p.id = e.owner_id
  where c.email = v_email and e.owner_id <> v.id;

  return jsonb_build_object(
    'estado',        v.estado,
    'cuota_eventos', v.cuota_eventos,
    'eventos_usados', v_n,
    'puede_crear',   v.estado = 'aprobado' and v_n < v.cuota_eventos,
    'propios',       v_propios,
    'compartidos',   v_comp
  );
end;
$$;

--
-- Name: normalizar_whatsapp(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalizar_whatsapp(p text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
declare
  d text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
begin
  if length(d) = 9 and left(d, 1) = '9' then
    d := '51' || d;
  end if;
  if d <> '' and (length(d) < 8 or length(d) > 15) then
    raise exception 'El WhatsApp "%" no parece un número válido.', p using hint = 'VALIDACION';
  end if;
  return d;
end;
$$;

--
-- Name: obtener_evento(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.obtener_evento(p_evento_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_rol text := public.rol_en_evento(p_evento_id);
  v_ev  jsonb;
begin
  if v_rol is null then
    raise exception 'El evento no existe o no tienes acceso.' using hint = 'PROHIBIDO';
  end if;

  select to_jsonb(e) || jsonb_build_object('owner_email', p.email) into v_ev
  from public.eventos e join public.perfiles p on p.id = e.owner_id
  where e.id = p_evento_id;

  return v_ev || jsonb_build_object('rol', v_rol, 'permisos', to_jsonb(public.permisos_rol(v_rol)));
end;
$$;

--
-- Name: obtener_invitacion(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.obtener_invitacion(p_codigo text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare
  c     text := upper(btrim(coalesce(p_codigo, '')));
  v_inv public.invitados;
  v_ev  public.eventos;
begin
  if c !~ '^[A-Z0-9]{4,12}$' then
    raise exception 'El enlace de invitación no es válido.' using hint = 'CODIGO';
  end if;

  select * into v_inv from public.invitados where codigo = c;
  if not found then
    raise exception 'No encontramos esta invitación. Revisa el enlace que te enviaron.' using hint = 'CODIGO';
  end if;

  select * into v_ev from public.eventos where id = v_inv.evento_id;

  return jsonb_build_object(
    'evento', jsonb_build_object(
      'tipo',             v_ev.tipo,
      'titulo',           v_ev.titulo,
      'anfitriones',      v_ev.anfitriones,
      'fecha',            v_ev.fecha,
      'hora',             to_char(v_ev.hora, 'HH24:MI'),
      'lugar',            v_ev.lugar,
      'direccion',        v_ev.direccion,
      'link_maps',        v_ev.link_maps,
      'fecha_limite',     v_ev.fecha_limite,
      'tipos_permitidos', to_jsonb(v_ev.tipos_permitidos),
      'es_demo',          v_ev.es_demo
    ),
    'invitado', jsonb_build_object(
      'nombre',       v_inv.nombre,
      'max_personas', v_inv.max_personas,
      'estado',       v_inv.estado,
      'adultos',      v_inv.adultos,
      'ninos',        v_inv.ninos,
      'mascotas',     v_inv.mascotas,
      'regalo',       coalesce((select nombre from public.regalos where id = v_inv.regalo_id), '')
    ),
    'abierta', v_ev.estado = 'activo'
               and not (v_ev.fecha_limite is not null and public.hoy_lima() > v_ev.fecha_limite),
    'regalos', case when v_inv.estado = 'Pendiente' then coalesce((
                 select jsonb_agg(jsonb_build_object('id', r.id, 'nombre', r.nombre) order by r.creado_en)
                 from public.regalos r
                 where r.evento_id = v_ev.id and public.reservas_regalo(r.id) < r.cupo
               ), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$_$;

--
-- Name: perfil_publico(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.perfil_publico(p_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select to_jsonb(p) || jsonb_build_object(
    'eventos_usados',   (select count(*) from public.eventos e where e.owner_id = p.id and not e.es_demo),
    'tiene_password',   exists (select 1 from auth.users u where u.id = p.id and coalesce(u.encrypted_password, '') <> ''),
    'google_vinculado', exists (select 1 from auth.identities i where i.user_id = p.id and i.provider = 'google'))
  from public.perfiles p
  where p.id = p_id;
$$;

--
-- Name: permisos_rol(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.permisos_rol(p_rol text) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select case p_rol
    when 'dueno'         then array['ver_resumen','ver_invitados','editar_invitados','eliminar_invitados','enviar','regalos','editar_evento','equipo','eliminar_evento']
    when 'admin'         then array['ver_resumen','ver_invitados','editar_invitados','eliminar_invitados','enviar','regalos','editar_evento','equipo','eliminar_evento']
    when 'coorganizador' then array['ver_resumen','ver_invitados','editar_invitados','eliminar_invitados','enviar','regalos','editar_evento']
    when 'lectura'       then array['ver_resumen','ver_invitados']
    when 'registrador'   then array['ver_invitados_propios','editar_invitados']
    when 'mensajero'     then array['ver_invitados','enviar']
    else array[]::text[]
  end;
$$;

--
-- Name: ping(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ping() RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select now()::text;
$$;

--
-- Name: preparar_invitado(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.preparar_invitado() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  new.nombre   := btrim(new.nombre);
  new.whatsapp := public.normalizar_whatsapp(new.whatsapp);

  if new.max_personas is null then
    select max_personas_default into new.max_personas from public.eventos where id = new.evento_id;
  end if;

  if tg_op = 'INSERT' then
    new.creado_por      := coalesce(auth.uid(), new.creado_por);
    new.actualizado_por := coalesce(auth.uid(), new.actualizado_por, new.creado_por);
  else
    if new.max_personas < new.adultos + new.ninos + new.mascotas then
      raise exception '% ya confirmó % personas; el máximo no puede ser menor.',
        new.nombre, new.adultos + new.ninos + new.mascotas using hint = 'VALIDACION';
    end if;
    new.actualizado_por := coalesce(auth.uid(), new.actualizado_por);
  end if;

  return new;
end;
$$;

--
-- Name: puede(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.puede(p_evento_id uuid, p_permiso text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select p_permiso = any(public.permisos_rol(public.rol_en_evento(p_evento_id)));
$$;

--
-- Name: reiniciar_respuesta(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reiniciar_respuesta(p_invitado_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_evento uuid;
  v_inv    public.invitados;
begin
  select evento_id into v_evento from public.invitados where id = p_invitado_id for update;
  if not found then
    raise exception 'Ese invitado ya no existe.' using hint = 'NO_EXISTE';
  end if;
  perform public.exigir_permiso(v_evento, array['editar_evento']);

  update public.invitados
  set estado = 'Pendiente', adultos = 0, ninos = 0, mascotas = 0, regalo_id = null, fecha_respuesta = null
  where id = p_invitado_id
  returning * into v_inv;

  return to_jsonb(v_inv) || jsonb_build_object('regalo_nombre', '');
end;
$$;

--
-- Name: reservas_regalo(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reservas_regalo(p_regalo_id uuid) RETURNS integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select count(*)::int from public.invitados
  where regalo_id = p_regalo_id and estado <> 'Pendiente';
$$;

--
-- Name: responder_invitacion(text, boolean, integer, integer, integer, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.responder_invitacion(p_codigo text, p_asiste boolean, p_adultos integer DEFAULT 0, p_ninos integer DEFAULT 0, p_mascotas integer DEFAULT 0, p_regalo_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare
  c        text := upper(btrim(coalesce(p_codigo, '')));
  v_inv    public.invitados;
  v_ev     public.eventos;
  v_regalo public.regalos;
  a int := 0;
  n int := 0;
  m int := 0;
begin
  if c !~ '^[A-Z0-9]{4,12}$' then
    raise exception 'El enlace de invitación no es válido.' using hint = 'CODIGO';
  end if;

  select * into v_inv from public.invitados where codigo = c for update;
  if not found then
    raise exception 'No encontramos esta invitación. Revisa el enlace que te enviaron.' using hint = 'CODIGO';
  end if;

  select * into v_ev from public.eventos where id = v_inv.evento_id;

  if v_ev.estado <> 'activo' then
    raise exception 'Los anfitriones ya cerraron las confirmaciones.' using hint = 'CERRADO';
  end if;
  if v_ev.fecha_limite is not null and public.hoy_lima() > v_ev.fecha_limite then
    raise exception 'La fecha límite para confirmar ya pasó. Comunícate directamente con los anfitriones.'
      using hint = 'CERRADO';
  end if;
  if v_inv.estado <> 'Pendiente' then
    raise exception 'Esta invitación ya fue respondida.' using hint = 'RESPONDIDA';
  end if;

  if coalesce(p_asiste, false) then
    a := coalesce(p_adultos, 0);
    n := case when 'ninos'    = any(v_ev.tipos_permitidos) then coalesce(p_ninos, 0)    else 0 end;
    m := case when 'mascotas' = any(v_ev.tipos_permitidos) then coalesce(p_mascotas, 0) else 0 end;

    if a < 0 or n < 0 or m < 0 or a > 20 or n > 20 or m > 20 then
      raise exception 'Las cantidades deben estar entre 0 y 20.' using hint = 'VALIDACION';
    end if;
    if a < 1 then
      raise exception 'Debe asistir al menos un adulto.' using hint = 'VALIDACION';
    end if;
    if a + n + m > v_inv.max_personas then
      raise exception 'Tu invitación es para máximo % %.', v_inv.max_personas,
        case when v_inv.max_personas = 1 then 'persona' else 'personas' end using hint = 'VALIDACION';
    end if;
  end if;

  if p_regalo_id is not null then
    select * into v_regalo from public.regalos
    where id = p_regalo_id and evento_id = v_ev.id
    for update;

    if not found then
      raise exception 'Ese regalo ya no está en la lista. Elige otro.' using hint = 'REGALO_LLENO';
    end if;
    if public.reservas_regalo(v_regalo.id) >= v_regalo.cupo then
      raise exception 'Alguien acaba de reservar "%". Elige otro regalo.', v_regalo.nombre using hint = 'REGALO_LLENO';
    end if;
  end if;

  update public.invitados
  set estado          = case when coalesce(p_asiste, false) then 'Confirmado' else 'No asistirá' end,
      adultos         = a,
      ninos           = n,
      mascotas        = m,
      regalo_id       = p_regalo_id,
      fecha_respuesta = now(),
      -- Si respondió, la invitación le llegó: se marca como enviada aunque el anfitrión no lo haya hecho
      enviado         = true,
      fecha_envio     = coalesce(fecha_envio, now())
  where id = v_inv.id;

  return jsonb_build_object(
    'estado', case when coalesce(p_asiste, false) then 'Confirmado' else 'No asistirá' end,
    'total',  a + n + m
  );
end;
$_$;

--
-- Name: resumen_evento(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resumen_evento(p_evento_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_res jsonb;
begin
  perform public.exigir_permiso(p_evento_id, array['ver_resumen']);

  select jsonb_build_object(
    'invitaciones',  count(*),
    'enviadas',      count(*) filter (where enviado),
    'confirmados',   count(*) filter (where estado = 'Confirmado'),
    'no_asisten',    count(*) filter (where estado = 'No asistirá'),
    'sin_respuesta', count(*) filter (where estado = 'Pendiente'),
    'adultos',       coalesce(sum(adultos)  filter (where estado = 'Confirmado'), 0),
    'ninos',         coalesce(sum(ninos)    filter (where estado = 'Confirmado'), 0),
    'mascotas',      coalesce(sum(mascotas) filter (where estado = 'Confirmado'), 0),
    'cupo_maximo',   coalesce(sum(max_personas), 0)
  ) into v_res
  from public.invitados
  where evento_id = p_evento_id;

  return v_res || jsonb_build_object(
    'evento',  public.obtener_evento(p_evento_id),
    'regalos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'nombre', r.nombre, 'cupo', r.cupo, 'reservados', public.reservas_regalo(r.id))
             order by r.creado_en)
      from public.regalos r where r.evento_id = p_evento_id
    ), '[]'::jsonb)
  );
end;
$$;

--
-- Name: rol_en_evento(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rol_en_evento(p_evento_id uuid) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_owner uuid;
  v_rol   text;
begin
  if auth.uid() is null or not public.usuario_activo() then
    return null;
  end if;

  select owner_id into v_owner from public.eventos where id = p_evento_id;
  if not found then
    return null;
  end if;

  if v_owner = auth.uid() then return 'dueno'; end if;
  if public.es_admin()     then return 'admin'; end if;

  select rol into v_rol
  from public.colaboradores
  where evento_id = p_evento_id and email = public.mi_email();

  return v_rol;
end;
$$;

--
-- Name: solicitar_acceso(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.solicitar_acceso(p_nombre text, p_telefono text, p_motivo text DEFAULT ''::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v     public.perfiles;
  v_tel text;
begin
  select * into v from public.perfiles where id = auth.uid() for update;
  if not found then
    raise exception 'Inicia sesión para continuar.' using hint = 'AUTH';
  end if;
  if v.estado = 'aprobado' then
    raise exception 'Tu cuenta de anfitrión ya está aprobada.' using hint = 'YA_APROBADO';
  end if;
  if v.estado = 'pendiente' then
    raise exception 'Ya enviaste tu solicitud y está en revisión.' using hint = 'PENDIENTE';
  end if;

  p_nombre := btrim(coalesce(p_nombre, ''));
  p_motivo := btrim(coalesce(p_motivo, ''));
  if p_nombre = '' then
    raise exception 'Falta tu nombre.' using hint = 'VALIDACION';
  end if;
  if char_length(p_nombre) > 80 then
    raise exception 'Tu nombre admite máximo 80 caracteres.' using hint = 'VALIDACION';
  end if;
  if char_length(p_motivo) > 500 then
    raise exception 'El mensaje admite máximo 500 caracteres.' using hint = 'VALIDACION';
  end if;

  v_tel := public.normalizar_whatsapp(p_telefono);
  if v_tel = '' then
    raise exception 'Indica tu número de WhatsApp para poder contactarte.' using hint = 'VALIDACION';
  end if;

  update public.perfiles
  set nombre = p_nombre, telefono = v_tel, motivo = p_motivo, estado = 'pendiente',
      fecha_solicitud = now(), nota_admin = '', revisado_por = null, fecha_revision = null
  where id = v.id;

  return jsonb_build_object('estado', 'pendiente');
end;
$$;

--
-- Name: usuario_activo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.usuario_activo() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.perfiles where id = auth.uid() and activo);
$$;

--
-- Name: validar_colaborador(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_colaborador() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_owner_email text;
begin
  new.email := lower(btrim(new.email));

  if tg_op = 'INSERT' then
    new.invitado_por := coalesce(auth.uid(), new.invitado_por);

    select p.email into v_owner_email
    from public.eventos e join public.perfiles p on p.id = e.owner_id
    where e.id = new.evento_id;

    if new.email = v_owner_email then
      raise exception 'Esa persona ya es la dueña del evento.' using hint = 'VALIDACION';
    end if;
    if exists (select 1 from public.colaboradores where evento_id = new.evento_id and email = new.email) then
      raise exception '% ya forma parte del equipo. Cambia su rol en la lista.', new.email using hint = 'VALIDACION';
    end if;
    if (select count(*) from public.colaboradores where evento_id = new.evento_id) >= 20 then
      raise exception 'Un evento admite hasta 20 colaboradores.' using hint = 'VALIDACION';
    end if;
  end if;

  return new;
end;
$$;

--
-- Name: validar_evento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_evento() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_perfil public.perfiles;
  v_total  int;
begin
  new.titulo      := btrim(new.titulo);
  new.lugar       := btrim(new.lugar);
  new.anfitriones := btrim(new.anfitriones);
  new.direccion   := btrim(new.direccion);
  new.link_maps   := btrim(new.link_maps);

  if tg_op = 'INSERT' and auth.uid() is not null and not new.es_demo then
    new.owner_id := auth.uid();
    select * into v_perfil from public.perfiles where id = new.owner_id;

    if not found or v_perfil.estado <> 'aprobado' then
      raise exception 'Para crear eventos necesitas una cuenta de anfitrión aprobada.' using hint = 'NO_ANFITRION';
    end if;

    select count(*) into v_total from public.eventos where owner_id = new.owner_id and not es_demo;
    if v_total >= v_perfil.cuota_eventos then
      raise exception 'Ya usaste tus % evento(s) disponibles. Pide al administrador que amplíe tu cupo.',
        v_perfil.cuota_eventos using hint = 'CUOTA';
    end if;
  end if;

  return new;
end;
$$;

--
-- Name: validar_regalo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_regalo() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_res int;
begin
  if tg_op = 'DELETE' then
    -- Si se está borrando el evento completo, se permite
    if not exists (select 1 from public.eventos where id = old.evento_id) then
      return old;
    end if;
    if public.reservas_regalo(old.id) > 0 then
      raise exception 'Alguien ya reservó este regalo. Borra primero su respuesta si quieres quitarlo.'
        using hint = 'VALIDACION';
    end if;
    return old;
  end if;

  new.nombre := btrim(new.nombre);
  if tg_op = 'UPDATE' then
    v_res := public.reservas_regalo(new.id);
    if new.cupo < v_res then
      raise exception 'Ya hay % reservas de este regalo; el cupo no puede ser menor.', v_res using hint = 'VALIDACION';
    end if;
  end if;
  return new;
end;
$$;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: colaboradores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.colaboradores (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    evento_id uuid NOT NULL,
    email text NOT NULL,
    rol text NOT NULL,
    invitado_por uuid,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT colaboradores_email_check CHECK (((char_length(email) <= 120) AND (email ~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$'::text))),
    CONSTRAINT colaboradores_rol_check CHECK ((rol = ANY (ARRAY['coorganizador'::text, 'lectura'::text, 'registrador'::text, 'mensajero'::text])))
);

--
-- Name: eventos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eventos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid DEFAULT auth.uid() NOT NULL,
    tipo text NOT NULL,
    titulo text NOT NULL,
    anfitriones text DEFAULT ''::text NOT NULL,
    fecha date NOT NULL,
    hora time without time zone NOT NULL,
    lugar text NOT NULL,
    direccion text DEFAULT ''::text NOT NULL,
    link_maps text DEFAULT ''::text NOT NULL,
    fecha_limite date,
    tipos_permitidos text[] DEFAULT ARRAY['adultos'::text] NOT NULL,
    max_personas_default integer DEFAULT 2 NOT NULL,
    mensaje_invitacion text DEFAULT ''::text NOT NULL,
    estado text DEFAULT 'activo'::text NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    es_demo boolean DEFAULT false NOT NULL,
    CONSTRAINT eventos_anfitriones_check CHECK ((char_length(anfitriones) <= 120)),
    CONSTRAINT eventos_check CHECK (((fecha_limite IS NULL) OR (fecha_limite <= fecha))),
    CONSTRAINT eventos_direccion_check CHECK ((char_length(direccion) <= 200)),
    CONSTRAINT eventos_estado_check CHECK ((estado = ANY (ARRAY['activo'::text, 'cerrado'::text]))),
    CONSTRAINT eventos_link_maps_check CHECK (((link_maps = ''::text) OR ((link_maps ~* '^https://'::text) AND (char_length(link_maps) <= 500)))),
    CONSTRAINT eventos_lugar_check CHECK (((char_length(btrim(lugar)) >= 1) AND (char_length(btrim(lugar)) <= 120))),
    CONSTRAINT eventos_max_personas_default_check CHECK (((max_personas_default >= 1) AND (max_personas_default <= 20))),
    CONSTRAINT eventos_mensaje_invitacion_check CHECK ((char_length(mensaje_invitacion) <= 1000)),
    CONSTRAINT eventos_tipo_check CHECK ((tipo = ANY (ARRAY['babyshower'::text, 'cumpleanos'::text, 'boda'::text, 'bautizo'::text, 'pollada'::text, 'otro'::text]))),
    CONSTRAINT eventos_tipos_permitidos_check CHECK (((tipos_permitidos <@ ARRAY['adultos'::text, 'ninos'::text, 'mascotas'::text]) AND ('adultos'::text = ANY (tipos_permitidos)))),
    CONSTRAINT eventos_titulo_check CHECK (((char_length(btrim(titulo)) >= 1) AND (char_length(btrim(titulo)) <= 80)))
);

--
-- Name: invitados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitados (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    evento_id uuid NOT NULL,
    codigo text DEFAULT public.generar_codigo() NOT NULL,
    nombre text NOT NULL,
    whatsapp text DEFAULT ''::text NOT NULL,
    max_personas integer NOT NULL,
    enviado boolean DEFAULT false NOT NULL,
    fecha_envio timestamp with time zone,
    estado text DEFAULT 'Pendiente'::text NOT NULL,
    adultos integer DEFAULT 0 NOT NULL,
    ninos integer DEFAULT 0 NOT NULL,
    mascotas integer DEFAULT 0 NOT NULL,
    regalo_id uuid,
    fecha_respuesta timestamp with time zone,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    creado_por uuid,
    actualizado_por uuid,
    recordatorios integer DEFAULT 0 NOT NULL,
    ultimo_recordatorio timestamp with time zone,
    CONSTRAINT invitados_adultos_check CHECK (((adultos >= 0) AND (adultos <= 20))),
    CONSTRAINT invitados_codigo_check CHECK ((codigo ~ '^[A-Z0-9]{4,12}$'::text)),
    CONSTRAINT invitados_estado_check CHECK ((estado = ANY (ARRAY['Pendiente'::text, 'Confirmado'::text, 'No asistirá'::text]))),
    CONSTRAINT invitados_mascotas_check CHECK (((mascotas >= 0) AND (mascotas <= 20))),
    CONSTRAINT invitados_max_personas_check CHECK (((max_personas >= 1) AND (max_personas <= 20))),
    CONSTRAINT invitados_ninos_check CHECK (((ninos >= 0) AND (ninos <= 20))),
    CONSTRAINT invitados_nombre_check CHECK (((char_length(btrim(nombre)) >= 1) AND (char_length(btrim(nombre)) <= 80))),
    CONSTRAINT invitados_recordatorios_check CHECK ((recordatorios >= 0)),
    CONSTRAINT invitados_whatsapp_check CHECK (((whatsapp = ''::text) OR (whatsapp ~ '^\d{8,15}$'::text)))
);

--
-- Name: perfiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.perfiles (
    id uuid NOT NULL,
    email text NOT NULL,
    nombre text DEFAULT ''::text NOT NULL,
    rol text DEFAULT 'organizador'::text NOT NULL,
    cuota_eventos integer DEFAULT 1 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    estado text DEFAULT 'registrado'::text NOT NULL,
    telefono text DEFAULT ''::text NOT NULL,
    motivo text DEFAULT ''::text NOT NULL,
    fecha_solicitud timestamp with time zone,
    nota_admin text DEFAULT ''::text NOT NULL,
    revisado_por uuid,
    fecha_revision timestamp with time zone,
    ultimo_acceso timestamp with time zone,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT perfiles_cuota_eventos_check CHECK (((cuota_eventos >= 0) AND (cuota_eventos <= 100))),
    CONSTRAINT perfiles_estado_check CHECK ((estado = ANY (ARRAY['registrado'::text, 'pendiente'::text, 'aprobado'::text, 'rechazado'::text]))),
    CONSTRAINT perfiles_motivo_check CHECK ((char_length(motivo) <= 500)),
    CONSTRAINT perfiles_nombre_check CHECK ((char_length(nombre) <= 80)),
    CONSTRAINT perfiles_nota_admin_check CHECK ((char_length(nota_admin) <= 300)),
    CONSTRAINT perfiles_rol_check CHECK ((rol = ANY (ARRAY['admin'::text, 'organizador'::text])))
);

--
-- Name: regalos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.regalos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    evento_id uuid NOT NULL,
    nombre text NOT NULL,
    cupo integer DEFAULT 1 NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT regalos_cupo_check CHECK (((cupo >= 1) AND (cupo <= 100))),
    CONSTRAINT regalos_nombre_check CHECK (((char_length(btrim(nombre)) >= 1) AND (char_length(btrim(nombre)) <= 80)))
);

--
-- Name: colaboradores colaboradores_evento_id_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaboradores
    ADD CONSTRAINT colaboradores_evento_id_email_key UNIQUE (evento_id, email);

--
-- Name: colaboradores colaboradores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaboradores
    ADD CONSTRAINT colaboradores_pkey PRIMARY KEY (id);

--
-- Name: eventos eventos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eventos
    ADD CONSTRAINT eventos_pkey PRIMARY KEY (id);

--
-- Name: invitados invitados_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitados
    ADD CONSTRAINT invitados_codigo_key UNIQUE (codigo);

--
-- Name: invitados invitados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitados
    ADD CONSTRAINT invitados_pkey PRIMARY KEY (id);

--
-- Name: perfiles perfiles_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfiles
    ADD CONSTRAINT perfiles_email_key UNIQUE (email);

--
-- Name: perfiles perfiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfiles
    ADD CONSTRAINT perfiles_pkey PRIMARY KEY (id);

--
-- Name: regalos regalos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.regalos
    ADD CONSTRAINT regalos_pkey PRIMARY KEY (id);

--
-- Name: idx_colaboradores_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_colaboradores_email ON public.colaboradores USING btree (email);

--
-- Name: idx_colaboradores_evento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_colaboradores_evento ON public.colaboradores USING btree (evento_id);

--
-- Name: idx_eventos_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_eventos_owner ON public.eventos USING btree (owner_id);

--
-- Name: idx_invitados_evento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invitados_evento ON public.invitados USING btree (evento_id);

--
-- Name: idx_invitados_regalo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invitados_regalo ON public.invitados USING btree (regalo_id);

--
-- Name: idx_regalos_evento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_regalos_evento ON public.regalos USING btree (evento_id);

--
-- Name: colaboradores antes_de_guardar_colaborador; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER antes_de_guardar_colaborador BEFORE INSERT OR UPDATE ON public.colaboradores FOR EACH ROW EXECUTE FUNCTION public.validar_colaborador();

--
-- Name: eventos antes_de_guardar_evento; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER antes_de_guardar_evento BEFORE INSERT OR UPDATE ON public.eventos FOR EACH ROW EXECUTE FUNCTION public.validar_evento();

--
-- Name: invitados antes_de_guardar_invitado; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER antes_de_guardar_invitado BEFORE INSERT OR UPDATE ON public.invitados FOR EACH ROW EXECUTE FUNCTION public.preparar_invitado();

--
-- Name: regalos antes_de_guardar_regalo; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER antes_de_guardar_regalo BEFORE INSERT OR DELETE OR UPDATE ON public.regalos FOR EACH ROW EXECUTE FUNCTION public.validar_regalo();

--
-- Name: perfiles demo_al_registrarse; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER demo_al_registrarse AFTER INSERT ON public.perfiles FOR EACH ROW EXECUTE FUNCTION public.demo_al_crear_perfil();

--
-- Name: colaboradores limite_demo_colaboradores; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER limite_demo_colaboradores BEFORE INSERT ON public.colaboradores FOR EACH ROW EXECUTE FUNCTION public.limitar_evento_demo();

--
-- Name: invitados limite_demo_invitados; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER limite_demo_invitados BEFORE INSERT ON public.invitados FOR EACH ROW EXECUTE FUNCTION public.limitar_evento_demo();

--
-- Name: colaboradores colaboradores_evento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaboradores
    ADD CONSTRAINT colaboradores_evento_id_fkey FOREIGN KEY (evento_id) REFERENCES public.eventos(id) ON DELETE CASCADE;

--
-- Name: colaboradores colaboradores_invitado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colaboradores
    ADD CONSTRAINT colaboradores_invitado_por_fkey FOREIGN KEY (invitado_por) REFERENCES public.perfiles(id) ON DELETE SET NULL;

--
-- Name: eventos eventos_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eventos
    ADD CONSTRAINT eventos_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.perfiles(id) ON DELETE CASCADE;

--
-- Name: invitados invitados_actualizado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitados
    ADD CONSTRAINT invitados_actualizado_por_fkey FOREIGN KEY (actualizado_por) REFERENCES public.perfiles(id) ON DELETE SET NULL;

--
-- Name: invitados invitados_creado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitados
    ADD CONSTRAINT invitados_creado_por_fkey FOREIGN KEY (creado_por) REFERENCES public.perfiles(id) ON DELETE SET NULL;

--
-- Name: invitados invitados_evento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitados
    ADD CONSTRAINT invitados_evento_id_fkey FOREIGN KEY (evento_id) REFERENCES public.eventos(id) ON DELETE CASCADE;

--
-- Name: invitados invitados_regalo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitados
    ADD CONSTRAINT invitados_regalo_id_fkey FOREIGN KEY (regalo_id) REFERENCES public.regalos(id) ON DELETE SET NULL;

--
-- Name: perfiles perfiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfiles
    ADD CONSTRAINT perfiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

--
-- Name: perfiles perfiles_revisado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfiles
    ADD CONSTRAINT perfiles_revisado_por_fkey FOREIGN KEY (revisado_por) REFERENCES public.perfiles(id) ON DELETE SET NULL;

--
-- Name: regalos regalos_evento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.regalos
    ADD CONSTRAINT regalos_evento_id_fkey FOREIGN KEY (evento_id) REFERENCES public.eventos(id) ON DELETE CASCADE;

--
-- Name: colaboradores; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.colaboradores ENABLE ROW LEVEL SECURITY;

--
-- Name: colaboradores colaboradores_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaboradores_delete ON public.colaboradores FOR DELETE TO authenticated USING ((public.puede(evento_id, 'equipo'::text) OR (email = ( SELECT public.mi_email() AS mi_email))));

--
-- Name: colaboradores colaboradores_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaboradores_insert ON public.colaboradores FOR INSERT TO authenticated WITH CHECK (public.puede(evento_id, 'equipo'::text));

--
-- Name: colaboradores colaboradores_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaboradores_select ON public.colaboradores FOR SELECT TO authenticated USING ((public.puede(evento_id, 'equipo'::text) OR (email = ( SELECT public.mi_email() AS mi_email))));

--
-- Name: colaboradores colaboradores_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colaboradores_update ON public.colaboradores FOR UPDATE TO authenticated USING (public.puede(evento_id, 'equipo'::text)) WITH CHECK (public.puede(evento_id, 'equipo'::text));

--
-- Name: eventos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: eventos eventos_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY eventos_delete ON public.eventos FOR DELETE TO authenticated USING (public.puede(id, 'eliminar_evento'::text));

--
-- Name: eventos eventos_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY eventos_insert ON public.eventos FOR INSERT TO authenticated WITH CHECK (((owner_id = ( SELECT auth.uid() AS uid)) AND ( SELECT public.usuario_activo() AS usuario_activo)));

--
-- Name: eventos eventos_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY eventos_select ON public.eventos FOR SELECT TO authenticated USING ((((owner_id = ( SELECT auth.uid() AS uid)) AND ( SELECT public.usuario_activo() AS usuario_activo)) OR (public.rol_en_evento(id) IS NOT NULL)));

--
-- Name: eventos eventos_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY eventos_update ON public.eventos FOR UPDATE TO authenticated USING (public.puede(id, 'editar_evento'::text)) WITH CHECK (public.puede(id, 'editar_evento'::text));

--
-- Name: invitados; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invitados ENABLE ROW LEVEL SECURITY;

--
-- Name: invitados invitados_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invitados_delete ON public.invitados FOR DELETE TO authenticated USING (public.puede(evento_id, 'eliminar_invitados'::text));

--
-- Name: invitados invitados_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invitados_insert ON public.invitados FOR INSERT TO authenticated WITH CHECK (public.puede(evento_id, 'editar_invitados'::text));

--
-- Name: invitados invitados_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invitados_select ON public.invitados FOR SELECT TO authenticated USING ((public.puede(evento_id, 'ver_invitados'::text) OR (public.puede(evento_id, 'ver_invitados_propios'::text) AND (creado_por = ( SELECT auth.uid() AS uid)))));

--
-- Name: invitados invitados_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invitados_update ON public.invitados FOR UPDATE TO authenticated USING ((public.puede(evento_id, 'editar_invitados'::text) AND (public.puede(evento_id, 'ver_invitados'::text) OR (creado_por = ( SELECT auth.uid() AS uid))))) WITH CHECK (public.puede(evento_id, 'editar_invitados'::text));

--
-- Name: perfiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.perfiles ENABLE ROW LEVEL SECURITY;

--
-- Name: perfiles perfiles_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY perfiles_select ON public.perfiles FOR SELECT TO authenticated USING (((id = ( SELECT auth.uid() AS uid)) OR ( SELECT public.es_admin() AS es_admin)));

--
-- Name: regalos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.regalos ENABLE ROW LEVEL SECURITY;

--
-- Name: regalos regalos_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY regalos_delete ON public.regalos FOR DELETE TO authenticated USING (public.puede(evento_id, 'regalos'::text));

--
-- Name: regalos regalos_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY regalos_insert ON public.regalos FOR INSERT TO authenticated WITH CHECK (public.puede(evento_id, 'regalos'::text));

--
-- Name: regalos regalos_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY regalos_select ON public.regalos FOR SELECT TO authenticated USING ((public.rol_en_evento(evento_id) IS NOT NULL));

--
-- Name: regalos regalos_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY regalos_update ON public.regalos FOR UPDATE TO authenticated USING (public.puede(evento_id, 'regalos'::text)) WITH CHECK (public.puede(evento_id, 'regalos'::text));

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;

--
-- Name: FUNCTION admin_actualizar_usuario(p_usuario_id uuid, p_cuota integer, p_activo boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_actualizar_usuario(p_usuario_id uuid, p_cuota integer, p_activo boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_actualizar_usuario(p_usuario_id uuid, p_cuota integer, p_activo boolean) TO authenticated;
GRANT ALL ON FUNCTION public.admin_actualizar_usuario(p_usuario_id uuid, p_cuota integer, p_activo boolean) TO service_role;

--
-- Name: FUNCTION admin_eventos(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_eventos() FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_eventos() TO authenticated;
GRANT ALL ON FUNCTION public.admin_eventos() TO service_role;

--
-- Name: FUNCTION admin_revisar_usuario(p_usuario_id uuid, p_decision text, p_cuota integer, p_nota text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_revisar_usuario(p_usuario_id uuid, p_decision text, p_cuota integer, p_nota text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_revisar_usuario(p_usuario_id uuid, p_decision text, p_cuota integer, p_nota text) TO authenticated;
GRANT ALL ON FUNCTION public.admin_revisar_usuario(p_usuario_id uuid, p_decision text, p_cuota integer, p_nota text) TO service_role;

--
-- Name: FUNCTION admin_usuarios(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_usuarios() FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_usuarios() TO authenticated;
GRANT ALL ON FUNCTION public.admin_usuarios() TO service_role;

--
-- Name: FUNCTION crear_evento_demo(p_owner uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.crear_evento_demo(p_owner uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.crear_evento_demo(p_owner uuid) TO service_role;

--
-- Name: FUNCTION crear_perfil_nuevo_usuario(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.crear_perfil_nuevo_usuario() FROM PUBLIC;
GRANT ALL ON FUNCTION public.crear_perfil_nuevo_usuario() TO service_role;

--
-- Name: FUNCTION es_admin(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.es_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION public.es_admin() TO authenticated;
GRANT ALL ON FUNCTION public.es_admin() TO service_role;

--
-- Name: FUNCTION exigir_admin(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.exigir_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION public.exigir_admin() TO service_role;

--
-- Name: FUNCTION exigir_permiso(p_evento_id uuid, p_permisos text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.exigir_permiso(p_evento_id uuid, p_permisos text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.exigir_permiso(p_evento_id uuid, p_permisos text[]) TO service_role;

--
-- Name: FUNCTION generar_codigo(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.generar_codigo() FROM PUBLIC;
GRANT ALL ON FUNCTION public.generar_codigo() TO authenticated;
GRANT ALL ON FUNCTION public.generar_codigo() TO service_role;

--
-- Name: FUNCTION hoy_lima(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.hoy_lima() FROM PUBLIC;
GRANT ALL ON FUNCTION public.hoy_lima() TO service_role;

--
-- Name: FUNCTION listar_equipo(p_evento_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.listar_equipo(p_evento_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.listar_equipo(p_evento_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.listar_equipo(p_evento_id uuid) TO service_role;

--
-- Name: FUNCTION listar_invitados(p_evento_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.listar_invitados(p_evento_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.listar_invitados(p_evento_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.listar_invitados(p_evento_id uuid) TO service_role;

--
-- Name: FUNCTION listar_regalos(p_evento_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.listar_regalos(p_evento_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.listar_regalos(p_evento_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.listar_regalos(p_evento_id uuid) TO service_role;

--
-- Name: FUNCTION marcar_enviado(p_invitado_id uuid, p_enviado boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.marcar_enviado(p_invitado_id uuid, p_enviado boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.marcar_enviado(p_invitado_id uuid, p_enviado boolean) TO authenticated;
GRANT ALL ON FUNCTION public.marcar_enviado(p_invitado_id uuid, p_enviado boolean) TO service_role;

--
-- Name: FUNCTION marcar_recordado(p_invitado_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.marcar_recordado(p_invitado_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.marcar_recordado(p_invitado_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.marcar_recordado(p_invitado_id uuid) TO service_role;

--
-- Name: FUNCTION me(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.me() FROM PUBLIC;
GRANT ALL ON FUNCTION public.me() TO authenticated;
GRANT ALL ON FUNCTION public.me() TO service_role;

--
-- Name: FUNCTION mi_email(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.mi_email() FROM PUBLIC;
GRANT ALL ON FUNCTION public.mi_email() TO authenticated;
GRANT ALL ON FUNCTION public.mi_email() TO service_role;

--
-- Name: FUNCTION mis_eventos(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.mis_eventos() FROM PUBLIC;
GRANT ALL ON FUNCTION public.mis_eventos() TO authenticated;
GRANT ALL ON FUNCTION public.mis_eventos() TO service_role;

--
-- Name: FUNCTION normalizar_whatsapp(p text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.normalizar_whatsapp(p text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.normalizar_whatsapp(p text) TO authenticated;
GRANT ALL ON FUNCTION public.normalizar_whatsapp(p text) TO service_role;

--
-- Name: FUNCTION obtener_evento(p_evento_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.obtener_evento(p_evento_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.obtener_evento(p_evento_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.obtener_evento(p_evento_id uuid) TO service_role;

--
-- Name: FUNCTION obtener_invitacion(p_codigo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.obtener_invitacion(p_codigo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.obtener_invitacion(p_codigo text) TO anon;
GRANT ALL ON FUNCTION public.obtener_invitacion(p_codigo text) TO authenticated;
GRANT ALL ON FUNCTION public.obtener_invitacion(p_codigo text) TO service_role;

--
-- Name: FUNCTION perfil_publico(p_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.perfil_publico(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.perfil_publico(p_id uuid) TO service_role;

--
-- Name: FUNCTION permisos_rol(p_rol text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.permisos_rol(p_rol text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.permisos_rol(p_rol text) TO authenticated;
GRANT ALL ON FUNCTION public.permisos_rol(p_rol text) TO service_role;

--
-- Name: FUNCTION ping(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ping() FROM PUBLIC;
GRANT ALL ON FUNCTION public.ping() TO anon;
GRANT ALL ON FUNCTION public.ping() TO authenticated;
GRANT ALL ON FUNCTION public.ping() TO service_role;

--
-- Name: FUNCTION preparar_invitado(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.preparar_invitado() FROM PUBLIC;
GRANT ALL ON FUNCTION public.preparar_invitado() TO service_role;

--
-- Name: FUNCTION puede(p_evento_id uuid, p_permiso text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.puede(p_evento_id uuid, p_permiso text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.puede(p_evento_id uuid, p_permiso text) TO authenticated;
GRANT ALL ON FUNCTION public.puede(p_evento_id uuid, p_permiso text) TO service_role;

--
-- Name: FUNCTION reiniciar_respuesta(p_invitado_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reiniciar_respuesta(p_invitado_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reiniciar_respuesta(p_invitado_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.reiniciar_respuesta(p_invitado_id uuid) TO service_role;

--
-- Name: FUNCTION reservas_regalo(p_regalo_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reservas_regalo(p_regalo_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reservas_regalo(p_regalo_id uuid) TO service_role;

--
-- Name: FUNCTION responder_invitacion(p_codigo text, p_asiste boolean, p_adultos integer, p_ninos integer, p_mascotas integer, p_regalo_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.responder_invitacion(p_codigo text, p_asiste boolean, p_adultos integer, p_ninos integer, p_mascotas integer, p_regalo_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.responder_invitacion(p_codigo text, p_asiste boolean, p_adultos integer, p_ninos integer, p_mascotas integer, p_regalo_id uuid) TO anon;
GRANT ALL ON FUNCTION public.responder_invitacion(p_codigo text, p_asiste boolean, p_adultos integer, p_ninos integer, p_mascotas integer, p_regalo_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.responder_invitacion(p_codigo text, p_asiste boolean, p_adultos integer, p_ninos integer, p_mascotas integer, p_regalo_id uuid) TO service_role;

--
-- Name: FUNCTION resumen_evento(p_evento_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.resumen_evento(p_evento_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.resumen_evento(p_evento_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.resumen_evento(p_evento_id uuid) TO service_role;

--
-- Name: FUNCTION rol_en_evento(p_evento_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.rol_en_evento(p_evento_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.rol_en_evento(p_evento_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.rol_en_evento(p_evento_id uuid) TO service_role;

--
-- Name: FUNCTION solicitar_acceso(p_nombre text, p_telefono text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.solicitar_acceso(p_nombre text, p_telefono text, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.solicitar_acceso(p_nombre text, p_telefono text, p_motivo text) TO authenticated;
GRANT ALL ON FUNCTION public.solicitar_acceso(p_nombre text, p_telefono text, p_motivo text) TO service_role;

--
-- Name: FUNCTION usuario_activo(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.usuario_activo() FROM PUBLIC;
GRANT ALL ON FUNCTION public.usuario_activo() TO authenticated;
GRANT ALL ON FUNCTION public.usuario_activo() TO service_role;

--
-- Name: FUNCTION validar_colaborador(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.validar_colaborador() FROM PUBLIC;
GRANT ALL ON FUNCTION public.validar_colaborador() TO service_role;

--
-- Name: FUNCTION validar_evento(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.validar_evento() FROM PUBLIC;
GRANT ALL ON FUNCTION public.validar_evento() TO service_role;

--
-- Name: FUNCTION validar_regalo(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.validar_regalo() FROM PUBLIC;
GRANT ALL ON FUNCTION public.validar_regalo() TO service_role;

--
-- Name: TABLE colaboradores; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.colaboradores TO service_role;
GRANT SELECT,DELETE ON TABLE public.colaboradores TO authenticated;

--
-- Name: COLUMN colaboradores.evento_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(evento_id) ON TABLE public.colaboradores TO authenticated;

--
-- Name: COLUMN colaboradores.email; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(email) ON TABLE public.colaboradores TO authenticated;

--
-- Name: COLUMN colaboradores.rol; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(rol),UPDATE(rol) ON TABLE public.colaboradores TO authenticated;

--
-- Name: TABLE eventos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.eventos TO service_role;
GRANT SELECT,DELETE ON TABLE public.eventos TO authenticated;

--
-- Name: COLUMN eventos.tipo; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(tipo),UPDATE(tipo) ON TABLE public.eventos TO authenticated;

--
-- Name: COLUMN eventos.titulo; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(titulo),UPDATE(titulo) ON TABLE public.eventos TO authenticated;

--
-- Name: COLUMN eventos.anfitriones; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(anfitriones),UPDATE(anfitriones) ON TABLE public.eventos TO authenticated;

--
-- Name: COLUMN eventos.fecha; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(fecha),UPDATE(fecha) ON TABLE public.eventos TO authenticated;

--
-- Name: COLUMN eventos.hora; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(hora),UPDATE(hora) ON TABLE public.eventos TO authenticated;

--
-- Name: COLUMN eventos.lugar; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(lugar),UPDATE(lugar) ON TABLE public.eventos TO authenticated;

--
-- Name: COLUMN eventos.direccion; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(direccion),UPDATE(direccion) ON TABLE public.eventos TO authenticated;

--
-- Name: COLUMN eventos.link_maps; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(link_maps),UPDATE(link_maps) ON TABLE public.eventos TO authenticated;

--
-- Name: COLUMN eventos.fecha_limite; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(fecha_limite),UPDATE(fecha_limite) ON TABLE public.eventos TO authenticated;

--
-- Name: COLUMN eventos.tipos_permitidos; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(tipos_permitidos),UPDATE(tipos_permitidos) ON TABLE public.eventos TO authenticated;

--
-- Name: COLUMN eventos.max_personas_default; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(max_personas_default),UPDATE(max_personas_default) ON TABLE public.eventos TO authenticated;

--
-- Name: COLUMN eventos.mensaje_invitacion; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(mensaje_invitacion),UPDATE(mensaje_invitacion) ON TABLE public.eventos TO authenticated;

--
-- Name: COLUMN eventos.estado; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(estado) ON TABLE public.eventos TO authenticated;

--
-- Name: TABLE invitados; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.invitados TO service_role;
GRANT SELECT,DELETE ON TABLE public.invitados TO authenticated;

--
-- Name: COLUMN invitados.evento_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(evento_id) ON TABLE public.invitados TO authenticated;

--
-- Name: COLUMN invitados.nombre; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(nombre),UPDATE(nombre) ON TABLE public.invitados TO authenticated;

--
-- Name: COLUMN invitados.whatsapp; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(whatsapp),UPDATE(whatsapp) ON TABLE public.invitados TO authenticated;

--
-- Name: COLUMN invitados.max_personas; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(max_personas),UPDATE(max_personas) ON TABLE public.invitados TO authenticated;

--
-- Name: TABLE perfiles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.perfiles TO service_role;
GRANT SELECT ON TABLE public.perfiles TO authenticated;

--
-- Name: TABLE regalos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.regalos TO service_role;
GRANT SELECT,DELETE ON TABLE public.regalos TO authenticated;

--
-- Name: COLUMN regalos.evento_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(evento_id) ON TABLE public.regalos TO authenticated;

--
-- Name: COLUMN regalos.nombre; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(nombre),UPDATE(nombre) ON TABLE public.regalos TO authenticated;

--
-- Name: COLUMN regalos.cupo; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(cupo),UPDATE(cupo) ON TABLE public.regalos TO authenticated;

--
-- PostgreSQL database dump complete
--

-- =====================================================================
-- Fuera del esquema public: trigger que crea el perfil al registrarse
-- (pg_dump --schema=public no lo incluye porque vive en auth.users)
-- =====================================================================
DROP TRIGGER IF EXISTS al_crear_usuario ON auth.users;
CREATE TRIGGER al_crear_usuario
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.crear_perfil_nuevo_usuario();
