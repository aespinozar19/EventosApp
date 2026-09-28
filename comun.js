/* Configuración y utilidades compartidas por index.html (invitados) y app.html (panel) */

// ⚙️ Completa estos dos valores
const APP_CONFIG = {
  API_URL: 'https://script.google.com/macros/s/AKfycbwF7JAmcwfimU-xRaRlez1bXS8E9UDYbnrW6cnxaltO2zVgfuo50Uc3e3y6kAHcobHNUQ/exec',
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


/* ── API ── */

async function api(action, data = {}, token = null) {
  let res;
  try {
    res = await fetch(APP_CONFIG.API_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain;charset=utf-8' },
      body: JSON.stringify({ action, data, token })
    });
  } catch (e) {
    throw new Error('No hay conexión con el servidor. Revisa tu internet e intenta de nuevo.');
  }
  if (!res.ok) throw new Error('El servidor respondió con un error (' + res.status + ').');
  const json = await res.json();
  if (!json.ok) {
    const e = new Error(json.error || 'Error desconocido.');
    e.codigo = json.codigo;
    throw e;
  }
  return json.data;
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
