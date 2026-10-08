-- =====================================================================
-- Orden personalizado de los regalos (arrastrar y soltar en el panel).
-- La invitación, el resumen y la lista de regalos respetan ese orden.
-- =====================================================================

alter table public.regalos add column if not exists orden int not null default 0;

-- Los regalos existentes conservan su orden actual (por fecha de creación)
update public.regalos r
set orden = x.n
from (select id, row_number() over (partition by evento_id order by creado_en) as n from public.regalos) x
where x.id = r.id and r.orden = 0;

create index if not exists idx_regalos_orden on public.regalos(evento_id, orden);


-- Nuevos regalos al final de la lista
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

  if tg_op = 'INSERT' then
    -- Los regalos nuevos van al final de la lista
    select coalesce(max(orden), 0) + 1 into new.orden from public.regalos where evento_id = new.evento_id;
  else
    v_res := public.reservas_regalo(new.id);
    if new.cupo < v_res then
      raise exception 'Ya hay % reservas de este regalo; el cupo no puede ser menor.', v_res using hint = 'VALIDACION';
    end if;
  end if;
  return new;
end;
$$;


-- Guarda el nuevo orden: p_ids es la lista completa de regalos del evento, en el orden deseado
create or replace function public.ordenar_regalos(p_evento_id uuid, p_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.exigir_permiso(p_evento_id, array['regalos']);

  update public.regalos r
  set orden = x.pos
  from unnest(p_ids) with ordinality as x(id, pos)
  where r.id = x.id and r.evento_id = p_evento_id;

  return jsonb_build_object('ordenados', coalesce(array_length(p_ids, 1), 0));
end;
$$;

revoke execute on function public.ordenar_regalos(uuid, uuid[]) from public, anon;
grant  execute on function public.ordenar_regalos(uuid, uuid[]) to authenticated, service_role;


-- Listados ordenados por el campo "orden"
CREATE OR REPLACE FUNCTION public.listar_regalos(p_evento_id uuid) RETURNS jsonb
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
      order by r.orden, r.creado_en)
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
      'regalo',       coalesce((select nombre from public.regalos where id = v_inv.regalo_id), '')
    ),
    'abierta', v_ev.estado = 'activo'
               and not (v_ev.fecha_limite is not null and public.hoy_lima() > v_ev.fecha_limite),
    'regalos', case when v_inv.estado = 'Pendiente' then coalesce((
                 select jsonb_agg(jsonb_build_object('id', r.id, 'nombre', r.nombre) order by r.orden, r.creado_en)
                 from public.regalos r
                 where r.evento_id = v_ev.id and public.reservas_regalo(r.id) < r.cupo
               ), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;
