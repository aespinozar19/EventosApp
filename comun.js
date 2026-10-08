/* Configuración y utilidades compartidas por index.html (invitados) y app.html (panel) */

// ⚙️ Configuración (la publishable key es pública: puede ir en el repositorio)
const APP_CONFIG = {
  SUPABASE_URL: 'https://hpzxgrmwkgltbyhpqmwe.supabase.co',
  SUPABASE_KEY: 'sb_publishable_Lhdj3_Em0v8zntVJP8mYdw_WTWUioZp',   // Project Settings → API Keys → Publishable key
  GOOGLE_CLIENT_ID: '891168012188-64r5h9me5t7nsoit6n4kvb49u93cj55q.apps.googleusercontent.com'
};

// Cada tipo define cómo se ve su invitación
const TIPOS_EVENTO = {
  babyshower: {
    nombre: 'Baby shower', etiqueta: 'Baby shower', emoji: '🍼',
    fuente: 'Baloo 2', gf: 'Baloo+2:wght@700', peso: 700,
    tema: { fondo: '#FBEEF2', tinta: '#4F2437', acento: '#B04469', suave: '#F2D3DE' }
  },
  cumpleanos: {
    nombre: 'Cumpleaños', etiqueta: 'Cumpleaños', emoji: '🎂',
    fuente: 'Bricolage Grotesque', gf: 'Bricolage+Grotesque:opsz,wght@12..96,800', peso: 800,
    tema: { fondo: '#FFF4D1', tinta: '#2B2340', acento: '#C9441D', suave: '#FBE2A0' }
  },
  boda: {
    nombre: 'Boda', etiqueta: 'Boda', emoji: '💍',
    fuente: 'Cormorant Garamond', gf: 'Cormorant+Garamond:wght@600', peso: 600,
    tema: { fondo: '#EEF0EA', tinta: '#27322B', acento: '#80613A', suave: '#D9DFD2' }
  },
  bautizo: {
    nombre: 'Bautizo', etiqueta: 'Bautizo', emoji: '🕊️',
    fuente: 'Cormorant Garamond', gf: 'Cormorant+Garamond:wght@600', peso: 600,
    tema: { fondo: '#ECF3FA', tinta: '#1E3550', acento: '#3A6EA5', suave: '#D3E3F2' }
  },
  pollada: {
    nombre: 'Pollada', etiqueta: 'Pollada', emoji: '🍗',
    fuente: 'Alfa Slab One', gf: 'Alfa+Slab+One', peso: 400,
    tema: { fondo: '#FFE7C2', tinta: '#3A1F0F', acento: '#B5341D', suave: '#F8CF92' }
  },
  otro: {
    nombre: 'Otro evento', etiqueta: 'Estás invitado', emoji: '🎉',
    fuente: 'Bricolage Grotesque', gf: 'Bricolage+Grotesque:opsz,wght@12..96,800', peso: 800,
    tema: { fondo: '#F0EFF7', tinta: '#23213A', acento: '#5B4FC7', suave: '#DDDAF1' }
  }
};

const TIPOS_INVITADO = {
  adultos: { singular: 'adulto', plural: 'adultos' },
  ninos: { singular: 'niño', plural: 'niños' },
  mascotas: { singular: 'mascota', plural: 'mascotas' }
};

const MENSAJE_DEFAULT =
  'Hola {nombre} {emoji}\n\n' +
  'Te invitamos a *{titulo}* el {fecha} a las {hora} en {lugar}.\n\n' +
  'Confirma tu asistencia aquí:\n{link}';


/* ── API (Supabase) ──
 * Mantiene la misma firma que la versión con Apps Script: api(accion, datos)
 * y devuelve los mismos objetos (camelCase), así app.html e index.html casi no cambian.
 * El 3er parámetro (token) ya no se usa: la sesión la guarda supabase-js.
 */

const sb = window.supabase.createClient(APP_CONFIG.SUPABASE_URL, APP_CONFIG.SUPABASE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false }
});

// app.html guarda esto para saber que hay sesión; la sesión real la maneja supabase-js
const SESION_OK = () => ({ token: 'supabase', expira: Date.now() + 30 * 86400000 });

function fallo(codigo, mensaje) {
  const e = new Error(mensaje);
  e.codigo = codigo;
  return e;
}

// Convierte errores de Supabase / Postgres / Auth al formato que espera la app
function traducirError(error) {
  if (!error) return fallo('INTERNO', 'Ocurrió un error inesperado. Intenta de nuevo.');
  if (error.codigo) return error;

  const msg = String(error.message || '');
  if (/Failed to fetch|NetworkError|Load failed/i.test(msg)) {
    return fallo('RED', 'No hay conexión con el servidor. Revisa tu internet e intenta de nuevo.');
  }

  // Errores lanzados por nuestras funciones SQL: el código viene en "hint"
  if (error.hint && /^[A-Z_]+$/.test(error.hint)) return fallo(error.hint, msg);

  // Errores de Supabase Auth
  const auth = {
    invalid_credentials: ['CREDENCIALES', 'Correo o contraseña incorrectos.'],
    email_not_confirmed: ['NO_VERIFICADO', 'Antes de entrar confirma tu correo con el código que te enviamos.'],
    otp_expired: ['CODIGO_INCORRECTO', 'El código no es correcto o ya venció. Pide uno nuevo.'],
    over_email_send_rate_limit: ['ESPERA', 'Te enviamos un código hace poco. Revisa tu correo (también spam) o espera un minuto.'],
    over_request_rate_limit: ['ESPERA', 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.'],
    user_already_exists: ['YA_EXISTE', 'Ya existe una cuenta con este correo. Inicia sesión o usa "Olvidé mi contraseña".'],
    email_exists: ['YA_EXISTE', 'Ya existe una cuenta con este correo. Inicia sesión o usa "Olvidé mi contraseña".'],
    weak_password: ['VALIDACION', 'La contraseña es muy débil. Usa al menos 8 caracteres.'],
    same_password: ['VALIDACION', 'La contraseña nueva debe ser distinta de la actual.'],
    session_not_found: ['AUTH', 'Tu sesión expiró. Vuelve a iniciar sesión.'],
    refresh_token_not_found: ['AUTH', 'Tu sesión expiró. Vuelve a iniciar sesión.']
  };
  if (error.code && auth[error.code]) return fallo(...auth[error.code]);
  if (/error sending .*email/i.test(msg)) {
    return fallo('CORREO', 'No pudimos enviarte el correo en este momento. Intenta de nuevo en unos minutos.');
  }
  if (/rate limit|only request this after/i.test(msg)) return fallo('ESPERA', auth.over_email_send_rate_limit[1]);

  // Errores de PostgREST / Postgres
  if (error.code === 'PGRST301' || /jwt/i.test(msg)) return fallo('AUTH', 'Tu sesión expiró. Vuelve a iniciar sesión.');
  if (error.code === '42501' || /row-level security|permission denied/i.test(msg)) {
    return fallo('PROHIBIDO', 'No tienes permiso para hacer esto.');
  }
  if (error.code === '23514') return fallo('VALIDACION', 'Revisa los datos: hay un valor fuera de lo permitido.');
  if (error.code === '23505') return fallo('VALIDACION', 'Ese registro ya existe.');
  if (error.code === '23503') return fallo('NO_EXISTE', 'El registro relacionado ya no existe.');

  console.error(error);
  return fallo('INTERNO', msg || 'Ocurrió un error inesperado. Intenta de nuevo.');
}

// snake_case → camelCase, fechas con hora a "yyyy-MM-dd HH:mm" (Lima) y hora "HH:mm:ss" → "HH:mm"
const _fmtLima = new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', hour12: false
});

function salida(v, clave = '') {
  if (Array.isArray(v)) return v.map(x => salida(x));
  if (v && typeof v === 'object') {
    const o = {};
    for (const [k, x] of Object.entries(v)) {
      const c = k.replace(/_([a-z])/g, (_, l) => l.toUpperCase());
      o[c] = salida(x, c);
    }
    return o;
  }
  if (typeof v === 'string') {
    if (clave === 'hora' && /^\d{2}:\d{2}:\d{2}$/.test(v)) return v.slice(0, 5);
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(v)) return _fmtLima.format(new Date(v)).replace(',', '');
  }
  return v;
}

async function rpc(nombre, params) {
  const { data, error } = await sb.rpc(nombre, params);
  if (error) throw traducirError(error);
  return salida(data);
}

async function consulta(promesa) {
  const { data, error } = await promesa;
  if (error) throw traducirError(error);
  return data;
}

async function usuarioActual() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) throw fallo('AUTH', 'Inicia sesión para continuar.');
  return session.user;
}

/* ── Validaciones (mismos mensajes que Code.gs) ── */

function vTxt(v, max, campo, requerido) {
  const s = String(v ?? '').trim();
  if (requerido && !s) throw fallo('VALIDACION', 'Falta ' + campo.toLowerCase() + '.');
  if (s.length > max) throw fallo('VALIDACION', campo + ' admite máximo ' + max + ' caracteres.');
  return s;
}

function vEntero(v, min, max, campo) {
  const n = Number(v);
  if (!Number.isInteger(n) || n < min || n > max) {
    throw fallo('VALIDACION', campo + ' debe ser un número entre ' + min + ' y ' + max + '.');
  }
  return n;
}

function vEmail(v) {
  const e = String(v || '').trim().toLowerCase();
  if (e.length > 120 || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e)) throw fallo('VALIDACION', 'Escribe un correo válido.');
  return e;
}

function vPassword(p) {
  p = String(p || '');
  if (p.length < 8) throw fallo('VALIDACION', 'La contraseña debe tener al menos 8 caracteres.');
  if (p.length > 72) throw fallo('VALIDACION', 'La contraseña es demasiado larga.');
  return p;
}

function vWhatsapp(v) {
  let d = String(v || '').replace(/\D/g, '');
  if (d.length === 9 && d[0] === '9') d = '51' + d;
  if (d && (d.length < 8 || d.length > 15)) throw fallo('VALIDACION', 'El WhatsApp "' + v + '" no parece un número válido.');
  return d;
}

function vMaxPersonas(v) {
  return v === '' || v === null || v === undefined ? null : vEntero(v, 1, 20, 'El máximo de personas');
}

function vRol(rol) {
  if (!['coorganizador', 'lectura', 'registrador', 'mensajero'].includes(rol)) throw fallo('VALIDACION', 'Elige un rol válido.');
  return rol;
}

function datosEvento(d) {
  if (!TIPOS_EVENTO[d.tipo]) throw fallo('VALIDACION', 'Elige un tipo de evento.');
  const esFecha = s => /^\d{4}-\d{2}-\d{2}$/.test(s);
  const fecha = String(d.fecha || '');
  if (!esFecha(fecha)) throw fallo('VALIDACION', 'Indica la fecha del evento.');
  const hora = String(d.hora || '');
  if (!/^\d{2}:\d{2}/.test(hora)) throw fallo('VALIDACION', 'Indica la hora del evento.');
  const fechaLimite = String(d.fechaLimite || '');
  if (fechaLimite && (!esFecha(fechaLimite) || fechaLimite > fecha)) {
    throw fallo('VALIDACION', 'La fecha límite para confirmar debe ser anterior o igual a la fecha del evento.');
  }
  const linkMaps = vTxt(d.linkMaps, 500, 'El enlace del mapa');
  if (linkMaps && !/^https:\/\//i.test(linkMaps)) throw fallo('VALIDACION', 'El enlace del mapa debe empezar con https://');
  const imagenFondo = urlImagenDirecta(vTxt(d.imagenFondo, 500, 'El enlace de la imagen'));
  if (imagenFondo && !/^https:\/\/[^\s"'()<>\\]+$/i.test(imagenFondo)) {
    throw fallo('VALIDACION', 'La imagen de fondo debe ser un enlace público que empiece con https://');
  }
  const pedidos = Array.isArray(d.tiposPermitidos) ? d.tiposPermitidos : [];

  return {
    tipo: d.tipo,
    titulo: vTxt(d.titulo, 80, 'El título', true),
    anfitriones: vTxt(d.anfitriones, 120, 'Anfitriones'),
    fecha,
    hora: hora.slice(0, 5),
    lugar: vTxt(d.lugar, 120, 'El lugar', true),
    direccion: vTxt(d.direccion, 200, 'La dirección'),
    link_maps: linkMaps,
    imagen_fondo: imagenFondo,
    fecha_limite: fechaLimite || null,
    tipos_permitidos: ['adultos', 'ninos', 'mascotas'].filter(t => t === 'adultos' || pedidos.includes(t)),
    max_personas_default: vEntero(d.maxPersonasDefault, 1, 20, 'El máximo de personas'),
    mensaje_invitacion: vTxt(d.mensajeInvitacion, 1000, 'El mensaje')
  };
}

// Buscan un registro recién guardado en el formato que devuelve la lista completa
async function invitadoSalida(eventoId, id) {
  return (await rpc('listar_invitados', { p_evento_id: eventoId })).find(x => x.id === id);
}
async function regaloSalida(eventoId, id) {
  return (await rpc('listar_regalos', { p_evento_id: eventoId })).find(x => x.id === id);
}
async function colaboradorSalida(eventoId, filtro) {
  return (await rpc('listar_equipo', { p_evento_id: eventoId })).colaboradores.find(filtro);
}
async function idUsuario(email) {
  const u = await consulta(sb.from('perfiles').select('id').eq('email', String(email || '').toLowerCase()).maybeSingle());
  if (!u) throw fallo('NO_EXISTE', 'Usuario no encontrado.');
  return u.id;
}

/* ── Acciones ── */

const ACCIONES = {

  /* Invitación pública (index.html) */
  invitacion: d => rpc('obtener_invitacion', { p_codigo: d.codigo }),

  responder: d => rpc('responder_invitacion', {
    p_codigo: d.codigo,
    p_asiste: d.asiste === true,
    p_adultos: Number(d.adultos || 0),
    p_ninos: Number(d.ninos || 0),
    p_mascotas: Number(d.mascotas || 0),
    p_regalo_id: d.regaloId || null
  }),

  /* Acceso */
  async loginGoogle(d) {
    const { error } = await sb.auth.signInWithIdToken({ provider: 'google', token: d.idToken });
    if (error) throw traducirError(error);
    return SESION_OK();
  },

  async loginPassword(d) {
    const email = vEmail(d.email);
    const { error } = await sb.auth.signInWithPassword({ email, password: String(d.password || '') });
    if (error) {
      const e = traducirError(error);
      if (e.codigo === 'NO_VERIFICADO') await sb.auth.resend({ type: 'signup', email }).catch(() => {});
      throw e;
    }
    return SESION_OK();
  },

  async registrarCuenta(d) {
    const email = vEmail(d.email);
    const nombre = vTxt(d.nombre, 80, 'Tu nombre', true);
    const { data, error } = await sb.auth.signUp({ email, password: vPassword(d.password), options: { data: { nombre } } });
    if (error) throw traducirError(error);
    // Si el correo ya tiene cuenta confirmada, Supabase responde sin identidades
    if (data.user && Array.isArray(data.user.identities) && data.user.identities.length === 0) {
      throw fallo('YA_EXISTE', 'Ya existe una cuenta con este correo. Inicia sesión, entra con Google o usa "Olvidé mi contraseña".');
    }
    return { email };
  },

  async verificarCorreo(d) {
    const { error } = await sb.auth.verifyOtp({ email: vEmail(d.email), token: String(d.codigo || '').trim(), type: 'signup' });
    if (error) throw traducirError(error);
    return SESION_OK();
  },

  async reenviarCodigo(d) {
    const { error } = await sb.auth.resend({ type: 'signup', email: vEmail(d.email) });
    if (error) throw traducirError(error);
    return { enviado: true };
  },

  async solicitarReset(d) {
    const { error } = await sb.auth.resetPasswordForEmail(vEmail(d.email));
    if (error) {
      const e = traducirError(error);
      if (e.codigo === 'ESPERA') throw e;   // el resto se ignora para no revelar si la cuenta existe
    }
    return { enviado: true };
  },

  async restablecerPassword(d) {
    const password = vPassword(d.password);
    const { error } = await sb.auth.verifyOtp({ email: vEmail(d.email), token: String(d.codigo || '').trim(), type: 'recovery' });
    if (error) throw traducirError(error);
    const r = await sb.auth.updateUser({ password });
    if (r.error) throw traducirError(r.error);
    await sb.auth.signOut({ scope: 'others' }).catch(() => {});
    return SESION_OK();
  },

  async cerrarSesion() {
    await sb.auth.signOut({ scope: 'local' });
    return { cerrada: true };
  },

  async cambiarPassword(d) {
    const user = await usuarioActual();
    const nueva = vPassword(d.nueva);
    const me = await rpc('me');
    if (me.tienePassword) {
      const r = await sb.auth.signInWithPassword({ email: user.email, password: String(d.actual || '') });
      if (r.error) throw fallo('CREDENCIALES', 'La contraseña actual no es correcta.');
    }
    const { error } = await sb.auth.updateUser({ password: nueva });
    if (error) throw traducirError(error);
    await sb.auth.signOut({ scope: 'others' }).catch(() => {});
    return { tienePassword: true };
  },

  /* Cuenta */
  me: () => rpc('me'),

  solicitarAcceso: d => rpc('solicitar_acceso', {
    p_nombre: d.nombre, p_telefono: d.telefono, p_motivo: d.motivo || ''
  }),

  /* Eventos */
  misEventos: () => rpc('mis_eventos'),

  evento: d => rpc('obtener_evento', { p_evento_id: d.eventoId }),

  async guardarEvento(d) {
    const datos = datosEvento(d);
    let id = d.id;
    if (id) {
      datos.estado = d.estado === 'cerrado' ? 'cerrado' : 'activo';
      const filas = await consulta(sb.from('eventos').update(datos).eq('id', id).select('id'));
      if (!filas.length) throw fallo('PROHIBIDO', 'Tu rol en este evento no permite hacer esto.');
    } else {
      id = (await consulta(sb.from('eventos').insert(datos).select('id').single())).id;
    }
    return rpc('obtener_evento', { p_evento_id: id });
  },

  async eliminarEvento(d) {
    const filas = await consulta(sb.from('eventos').delete().eq('id', d.id).select('id'));
    if (!filas.length) throw fallo('PROHIBIDO', 'Tu rol en este evento no permite hacer esto.');
    return { eliminado: true };
  },

  /* Invitados */
  listarInvitados: d => rpc('listar_invitados', { p_evento_id: d.eventoId }),

  async guardarInvitado(d) {
    const datos = {
      nombre: vTxt(d.nombre, 80, 'El nombre', true),
      whatsapp: vWhatsapp(d.whatsapp),
      max_personas: vMaxPersonas(d.maxPersonas)
    };
    let id = d.id;
    if (id) {
      const filas = await consulta(sb.from('invitados').update(datos).eq('id', id).eq('evento_id', d.eventoId).select('id'));
      if (!filas.length) throw fallo('PROHIBIDO', 'Solo puedes editar a los invitados que tú registraste.');
    } else {
      id = (await consulta(sb.from('invitados').insert({ evento_id: d.eventoId, ...datos }).select('id').single())).id;
    }
    return invitadoSalida(d.eventoId, id);
  },

  async importarInvitados(d) {
    const filas = d.filas;
    if (!Array.isArray(filas) || !filas.length) throw fallo('VALIDACION', 'No hay filas para importar.');
    if (filas.length > 500) throw fallo('VALIDACION', 'Importa como máximo 500 invitados a la vez.');
    const nuevos = filas.map((f, k) => {
      try {
        return {
          evento_id: d.eventoId,
          nombre: vTxt(f.nombre, 80, 'El nombre', true),
          whatsapp: vWhatsapp(f.whatsapp),
          max_personas: vMaxPersonas(f.maxPersonas)
        };
      } catch (e) {
        throw fallo(e.codigo, 'Fila ' + (k + 1) + ': ' + e.message);
      }
    });
    await consulta(sb.from('invitados').insert(nuevos));
    return { importados: nuevos.length };
  },

  async eliminarInvitado(d) {
    const filas = await consulta(sb.from('invitados').delete().eq('id', d.id).eq('evento_id', d.eventoId).select('id'));
    if (!filas.length) throw fallo('PROHIBIDO', 'Tu rol en este evento no permite hacer esto.');
    return { eliminado: true };
  },

  marcarEnviado: d => rpc('marcar_enviado', { p_invitado_id: d.id, p_enviado: d.enviado === true }),

  reiniciarRespuesta: d => rpc('reiniciar_respuesta', { p_invitado_id: d.id }),

  marcarRecordado: d => rpc('marcar_recordado', { p_invitado_id: d.id }),

  /* Regalos */
  listarRegalos: d => rpc('listar_regalos', { p_evento_id: d.eventoId }),

  async guardarRegalo(d) {
    const datos = {
      nombre: vTxt(d.nombre, 80, 'El nombre del regalo', true),
      cupo: vEntero(d.cupo, 1, 100, 'El cupo')
    };
    let id = d.id;
    if (id) {
      const filas = await consulta(sb.from('regalos').update(datos).eq('id', id).eq('evento_id', d.eventoId).select('id'));
      if (!filas.length) throw fallo('NO_EXISTE', 'Ese regalo ya no existe.');
    } else {
      id = (await consulta(sb.from('regalos').insert({ evento_id: d.eventoId, ...datos }).select('id').single())).id;
    }
    return regaloSalida(d.eventoId, id);
  },

  async eliminarRegalo(d) {
    const filas = await consulta(sb.from('regalos').delete().eq('id', d.id).eq('evento_id', d.eventoId).select('id'));
    if (!filas.length) throw fallo('NO_EXISTE', 'Ese regalo ya no existe.');
    return { eliminado: true };
  },

  /* Resumen */
  resumen: d => rpc('resumen_evento', { p_evento_id: d.eventoId }),

  /* Equipo */
  listarEquipo: d => rpc('listar_equipo', { p_evento_id: d.eventoId }),

  async invitarColaborador(d) {
    const email = vEmail(d.email);
    await consulta(sb.from('colaboradores').insert({ evento_id: d.eventoId, email, rol: vRol(d.rol) }));
    return colaboradorSalida(d.eventoId, c => c.email === email);
  },

  async cambiarRolColaborador(d) {
    const filas = await consulta(sb.from('colaboradores').update({ rol: vRol(d.rol) })
      .eq('id', d.id).eq('evento_id', d.eventoId).select('id'));
    if (!filas.length) throw fallo('NO_EXISTE', 'Esa persona ya no está en el equipo.');
    return colaboradorSalida(d.eventoId, c => c.id === d.id);
  },

  async quitarColaborador(d) {
    const filas = await consulta(sb.from('colaboradores').delete().eq('id', d.id).eq('evento_id', d.eventoId).select('id'));
    if (!filas.length) throw fallo('NO_EXISTE', 'Esa persona ya no está en el equipo.');
    return { eliminado: true };
  },

  async salirDeEvento(d) {
    const user = await usuarioActual();
    const filas = await consulta(sb.from('colaboradores').delete()
      .eq('evento_id', d.eventoId).eq('email', user.email.toLowerCase()).select('id'));
    if (!filas.length) throw fallo('NO_EXISTE', 'No formas parte del equipo de este evento.');
    return { eliminado: true };
  },

  /* Administración */
  adminUsuarios: () => rpc('admin_usuarios'),

  adminEventos: () => rpc('admin_eventos'),

  async adminRevisarUsuario(d) {
    return rpc('admin_revisar_usuario', {
      p_usuario_id: await idUsuario(d.email),
      p_decision: d.decision,
      p_cuota: d.cuotaEventos ?? null,
      p_nota: d.nota || ''
    });
  },

  async adminActualizarUsuario(d) {
    return rpc('admin_actualizar_usuario', {
      p_usuario_id: await idUsuario(d.email),
      p_cuota: d.cuotaEventos ?? null,
      p_activo: d.activo ?? null
    });
  }
};

const PUBLICAS = ['invitacion', 'responder', 'loginGoogle', 'loginPassword', 'registrarCuenta',
  'verificarCorreo', 'reenviarCodigo', 'solicitarReset', 'restablecerPassword', 'cerrarSesion'];

async function api(action, data = {}) {
  const fn = ACCIONES[action];
  if (!fn) throw fallo('ACCION', 'Acción desconocida.');
  try {
    if (!PUBLICAS.includes(action)) await usuarioActual();
    return await fn(data || {});
  } catch (e) {
    throw traducirError(e);
  }
}


/* ── Texto ── */

function esc(v) {
  return String(v ?? '').replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function cap(s) {
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : '';
}

function fechaLarga(iso) {
  if (!iso) return '';
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('es-PE',
    { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
}

// Enlace que abre Google Calendar con el evento ya llenado (el usuario solo presiona "Guardar").
// La fecha y hora del evento están en hora de Lima; se envían en UTC. Duración por defecto: 3 horas.
function enlaceGoogleCalendar(ev, detalles = '') {
  const inicio = new Date(`${ev.fecha}T${String(ev.hora || '00:00').slice(0, 5)}:00-05:00`);
  const fin = new Date(inicio.getTime() + 3 * 3600 * 1000);
  const utc = d => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
  const lugar = [ev.lugar, ev.direccion].filter(Boolean).join(', ');
  const texto = [
    ev.anfitriones ? 'Anfitriones: ' + ev.anfitriones : '',
    ev.linkMaps ? 'Cómo llegar: ' + ev.linkMaps : '',
    detalles
  ].filter(Boolean).join('\n');
  const p = new URLSearchParams({
    action: 'TEMPLATE',
    text: ev.titulo,
    dates: utc(inicio) + '/' + utc(fin),
    location: lugar,
    details: texto,
    ctz: 'America/Lima'
  });
  return 'https://calendar.google.com/calendar/render?' + p.toString();
}

function horaCorta(hhmm) {
  if (!hhmm) return '';
  const [h, m] = hhmm.split(':').map(Number);
  return ((h % 12) || 12) + ':' + String(m).padStart(2, '0') + (h >= 12 ? ' p. m.' : ' a. m.');
}

function cantidad(n, tipo) {
  const t = TIPOS_INVITADO[tipo];
  return n + ' ' + (n === 1 ? t.singular : t.plural);
}

function listaNatural(a) {
  if (a.length < 2) return a[0] || '';
  return a.slice(0, -1).join(', ') + ' y ' + a[a.length - 1];
}

function detallePersonas(o, tipos) {
  return listaNatural(tipos.filter(t => o[t] > 0).map(t => cantidad(o[t], t)));
}

function formatoTel(d) {
  if (!d) return '';
  if (d.length === 11 && d.startsWith('51')) return '+51 ' + d.slice(2, 5) + ' ' + d.slice(5, 8) + ' ' + d.slice(8);
  return '+' + d;
}


/* ── Invitaciones ── */

function tipoEvento(t) {
  return TIPOS_EVENTO[t] || TIPOS_EVENTO.otro;
}

function linkInvitacion(codigo) {
  return new URL('index.html?codigo=' + encodeURIComponent(codigo), location.href).href;
}

function armarMensaje(ev, inv) {
  const plantilla = ev.mensajeInvitacion || MENSAJE_DEFAULT;
  const valores = {
    nombre: inv.nombre,
    titulo: ev.titulo,
    fecha: fechaLarga(ev.fecha),
    hora: horaCorta(ev.hora),
    lugar: ev.lugar,
    emoji: tipoEvento(ev.tipo).emoji,
    link: linkInvitacion(inv.codigo)
  };
  return plantilla.replace(/\{(\w+)\}/g, (todo, k) => (k in valores ? valores[k] : todo));
}

// Mensaje de recordatorio para quienes recibieron la invitación y aún no responden
function armarRecordatorio(ev, inv) {
  const limite = ev.fechaLimite ? ' Puedes confirmar hasta el ' + fechaLarga(ev.fechaLimite) + '.' : '';
  return 'Hola ' + inv.nombre + ' ' + tipoEvento(ev.tipo).emoji + '\n\n' +
    'Te recordamos nuestra invitación a *' + ev.titulo + '* el ' + fechaLarga(ev.fecha) +
    ' a las ' + horaCorta(ev.hora) + '. ¿Nos cuentas si podrás venir?' + limite + '\n\n' +
    'Responde aquí:\n' + linkInvitacion(inv.codigo);
}

// Convierte enlaces de Google Drive para compartir en un enlace directo a la imagen.
// Ej.: https://drive.google.com/file/d/ID/view?usp=sharing → https://lh3.googleusercontent.com/d/ID
function urlImagenDirecta(url) {
  const u = String(url || '').trim();
  const m = u.match(/^https:\/\/drive\.google\.com\/(?:file\/d\/([\w-]{10,})|(?:open|uc|thumbnail)\?(?:[^#]*&)?id=([\w-]{10,}))/i);
  return m ? 'https://lh3.googleusercontent.com/d/' + (m[1] || m[2]) : u;
}

function linkWhatsApp(numero, texto) {
  return numero ? 'https://wa.me/' + numero + '?text=' + encodeURIComponent(texto) : '';
}

function cargarFuente(gf) {
  if (document.querySelector('link[data-gf="' + gf + '"]')) return;
  const l = document.createElement('link');
  l.rel = 'stylesheet';
  l.dataset.gf = gf;
  l.href = 'https://fonts.googleapis.com/css2?family=' + gf + '&display=swap';
  document.head.appendChild(l);
}
