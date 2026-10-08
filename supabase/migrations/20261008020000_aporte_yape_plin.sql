-- =====================================================================
-- Aporte por Yape / Plin como un "regalo" más de la lista.
-- - Se ordena junto con los demás regalos.
-- - No tiene cupo: lo pueden elegir todos los invitados.
-- - Es excluyente con un regalo físico (cada invitado elige un solo regalo).
-- - La invitación muestra número, titular y apps para copiar el número.
-- =====================================================================

alter table public.regalos
  add column if not exists tipo           text not null default 'objeto',
  add column if not exists aporte_numero  text not null default '',
  add column if not exists aporte_titular text not null default '',
  add column if not exists aporte_apps    text not null default '';

alter table public.regalos drop constraint if exists regalos_tipo_check;
alter table public.regalos add constraint regalos_tipo_check check (tipo in ('objeto', 'aporte'));

alter table public.regalos drop constraint if exists regalos_aporte_check;
alter table public.regalos add constraint regalos_aporte_check check (
  tipo = 'objeto'
  or (aporte_numero ~ '^9\d{8}$'
      and char_length(aporte_titular) between 1 and 80
      and aporte_apps in ('yape', 'plin', 'ambos'))
);

grant insert (tipo, aporte_numero, aporte_titular, aporte_apps),
      update (tipo, aporte_numero, aporte_titular, aporte_apps)
  on public.regalos to authenticated;


create or replace function public.validar_regalo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
  if new.tipo = 'aporte' then
    new.aporte_numero  := regexp_replace(new.aporte_numero, '\D', '', 'g');
    new.aporte_titular := btrim(new.aporte_titular);
    new.cupo := 1;   -- el aporte no tiene cupo: no se usa
  else
    new.aporte_numero := ''; new.aporte_titular := ''; new.aporte_apps := '';
  end if;

  if tg_op = 'INSERT' then
    -- Los regalos nuevos van al final de la lista
    select coalesce(max(orden), 0) + 1 into new.orden from public.regalos where evento_id = new.evento_id;
  else
    v_res := public.reservas_regalo(new.id);
    if new.tipo <> 'aporte' and new.cupo < v_res then
      raise exception 'Ya hay % reservas de este regalo; el cupo no puede ser menor.', v_res using hint = 'VALIDACION';
    end if;
  end if;
  return new;
end;
$$;

CREATE OR REPLACE FUNCTION public.responder_invitacion(p_codigo text, p_asiste boolean, p_adultos integer DEFAULT 0, p_ninos integer DEFAULT 0, p_mascotas integer DEFAULT 0, p_regalo_id uuid DEFAULT NULL::uuid) RETURNS jsonb
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
    if v_regalo.tipo <> 'aporte' and public.reservas_regalo(v_regalo.id) >= v_regalo.cupo then
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

CREATE OR REPLACE FUNCTION public.resumen_evento(p_evento_id uuid) RETURNS jsonb
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

CREATE OR REPLACE FUNCTION public.resumen_evento(p_evento_id uuid) RETURNS jsonb
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
               'nombre', r.nombre, 'tipo', r.tipo, 'cupo', r.cupo, 'reservados', public.reservas_regalo(r.id))
             order by r.orden, r.creado_en)
      from public.regalos r where r.evento_id = p_evento_id
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.obtener_invitacion(p_codigo text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
      'es_demo',          v_ev.es_demo,
      'imagen_fondo',     v_ev.imagen_fondo
    ),
    'invitado', jsonb_build_object(
      'nombre',       v_inv.nombre,
      'max_personas', v_inv.max_personas,
      'estado',       v_inv.estado,
      'adultos',      v_inv.adultos,
      'ninos',        v_inv.ninos,
      'mascotas',     v_inv.mascotas,
      'regalo',       coalesce((select nombre from public.regalos where id = v_inv.regalo_id), ''),
      'regalo_aporte', (select case when g.tipo = 'aporte' then jsonb_build_object(
                          'numero', g.aporte_numero, 'titular', g.aporte_titular, 'apps', g.aporte_apps) end
                        from public.regalos g where g.id = v_inv.regalo_id)
    ),
    'abierta', v_ev.estado = 'activo'
               and not (v_ev.fecha_limite is not null and public.hoy_lima() > v_ev.fecha_limite),
    'regalos', case when v_inv.estado = 'Pendiente' then coalesce((
                 select jsonb_agg(jsonb_build_object('id', r.id, 'nombre', r.nombre, 'tipo', r.tipo)
                          || case when r.tipo = 'aporte' then jsonb_build_object(
                               'numero', r.aporte_numero, 'titular', r.aporte_titular, 'apps', r.aporte_apps)
                             else '{}'::jsonb end
                        order by r.orden, r.creado_en)
                 from public.regalos r
                 where r.evento_id = v_ev.id and (r.tipo = 'aporte' or public.reservas_regalo(r.id) < r.cupo)
               ), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;
