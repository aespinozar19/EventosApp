-- =====================================================================
-- Imagen de fondo opcional para la invitación de cada evento.
-- Es una URL pública (https) que el anfitrión pega en Ajustes del evento.
-- =====================================================================

alter table public.eventos
  add column if not exists imagen_fondo text not null default ''
  check (imagen_fondo = '' or (char_length(imagen_fondo) <= 500 and imagen_fondo ~ '^https://[^\s"''()<>\\]+$'));

-- Se puede escribir desde el formulario del evento (mismas reglas RLS que el resto de campos)
grant insert (imagen_fondo), update (imagen_fondo) on public.eventos to authenticated;

-- La invitación pública devuelve la imagen de fondo
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
                 select jsonb_agg(jsonb_build_object('id', r.id, 'nombre', r.nombre) order by r.creado_en)
                 from public.regalos r
                 where r.evento_id = v_ev.id and public.reservas_regalo(r.id) < r.cupo
               ), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;
