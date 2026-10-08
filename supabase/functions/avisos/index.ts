/**
 * Edge Function "avisos": correos automáticos de Anfitrión.
 * La llaman dos Database Webhooks de Supabase:
 *   - perfiles (UPDATE)      → nueva solicitud (a los admins), cuenta aprobada o rechazada (al usuario)
 *   - colaboradores (INSERT) → "te agregaron al equipo de un evento" (al colaborador)
 *
 * Secrets necesarios (Edge Functions → Secrets):
 *   SMTP_USER      anfitrionapp.avisos@gmail.com
 *   SMTP_PASS      contraseña de aplicación de Gmail (16 letras, sin espacios)
 *   APP_URL        https://anfitrion.pages.dev/app
 *   AVISO_SECRETO  una clave larga inventada; la misma va en el header de los webhooks
 */

import { createClient } from 'npm:@supabase/supabase-js@2';
import nodemailer from 'npm:nodemailer@6.9.16';

const APP_URL = (Deno.env.get('APP_URL') || 'https://anfitrion.pages.dev/app').replace(/\/$/, '');
const SMTP_USER = Deno.env.get('SMTP_USER') || '';
const SMTP_PASS = Deno.env.get('SMTP_PASS') || '';
const AVISO_SECRETO = Deno.env.get('AVISO_SECRETO') || '';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false, autoRefreshToken: false }
});

// Gmail por el puerto 465 (Supabase bloquea 25 y 587 en Edge Functions)
const smtp = nodemailer.createTransport({
  host: 'smtp.gmail.com', port: 465, secure: true,
  auth: { user: SMTP_USER, pass: SMTP_PASS }
});

const ROLES: Record<string, string> = {
  coorganizador: 'Coorganizador: puedes hacer todo en el evento, menos gestionar el equipo o eliminarlo.',
  lectura: 'Solo lectura: ves el resumen, los invitados y sus respuestas, sin cambiar nada.',
  registrador: 'Registrador: agregas invitados y ves solo a los que tú registraste.',
  mensajero: 'Mensajero: ves la lista de invitados y envías las invitaciones por WhatsApp.'
};

function esc(v: unknown): string {
  return String(v ?? '').replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' } as Record<string, string>)[c]);
}

function fechaLarga(iso: string): string {
  if (!iso) return '';
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d, 12)).toLocaleDateString('es-PE',
    { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
}

function plantilla(titulo: string, parrafos: string[], boton?: { texto: string; url: string }): string {
  return `
  <div style="font-family:Arial,Helvetica,sans-serif;max-width:520px;margin:0 auto;padding:24px;color:#1F2A44">
    <p style="font-weight:800;font-size:18px;margin:0 0 20px">Anfitrión<span style="color:#E0A526">.</span></p>
    <h1 style="font-size:22px;margin:0 0 16px">${titulo}</h1>
    ${parrafos.map(p => `<p style="font-size:15px;line-height:1.5;margin:0 0 12px">${p}</p>`).join('')}
    ${boton ? `<p style="margin:24px 0"><a href="${esc(boton.url)}"
      style="background:#1F2A44;color:#fff;padding:12px 20px;border-radius:10px;text-decoration:none;font-weight:700;display:inline-block">${esc(boton.texto)}</a></p>` : ''}
    <p style="font-size:12px;color:#5E6679;margin-top:28px">Este es un correo automático de Anfitrión. No respondas a este mensaje.</p>
  </div>`;
}

async function enviar(para: string, asunto: string, html: string) {
  await smtp.sendMail({ from: `"Anfitrión" <${SMTP_USER}>`, to: para, subject: asunto, html });
  console.log('Correo enviado:', asunto, '→', para);
}

/* ── Avisos de perfiles ── */

async function avisoPerfil(r: any, o: any) {
  if (!o || r.estado === o.estado) return;   // solo cuando cambia el estado (no por cada inicio de sesión)

  if (r.estado === 'pendiente') {
    const { data: admins, error } = await sb.from('perfiles').select('email')
      .eq('rol', 'admin').eq('estado', 'aprobado').eq('activo', true);
    if (error) throw error;
    const html = plantilla('Nueva solicitud de anfitrión', [
      `<strong>${esc(r.nombre)}</strong> (${esc(r.email)}) quiere organizar eventos.`,
      r.telefono ? `WhatsApp: +${esc(r.telefono)}` : '',
      r.motivo ? `Su mensaje: <em>${esc(r.motivo)}</em>` : ''
    ].filter(Boolean), { texto: 'Revisar solicitud', url: APP_URL + '#/admin' });
    for (const a of admins || []) {
      if (a.email !== r.email) await enviar(a.email, 'Nueva solicitud de anfitrión: ' + (r.nombre || r.email), html);
    }
  }

  if (r.estado === 'aprobado') {
    await enviar(r.email, 'Tu cuenta de anfitrión fue aprobada', plantilla(`¡Listo, ${esc(r.nombre || '')}!`, [
      'Tu cuenta de anfitrión ya está aprobada. Ya puedes crear tu evento, agregar a tus invitados y enviarles la invitación por WhatsApp.',
      `Puedes crear hasta <strong>${r.cuota_eventos}</strong> ${r.cuota_eventos === 1 ? 'evento' : 'eventos'}.`
    ], { texto: 'Crear mi evento', url: APP_URL + '#/nuevo' }));
  }

  if (r.estado === 'rechazado') {
    await enviar(r.email, 'Sobre tu solicitud de anfitrión', plantilla('Tu solicitud no fue aprobada', [
      `Hola ${esc(r.nombre || '')}, por ahora no pudimos aprobar tu cuenta de anfitrión.`,
      r.nota_admin ? `Comentario del administrador: <em>${esc(r.nota_admin)}</em>` : '',
      'Si tu situación cambió, puedes enviar una nueva solicitud desde la app.'
    ].filter(Boolean), { texto: 'Ir a Anfitrión', url: APP_URL }));
  }
}

/* ── Aviso de colaboradores ── */

async function avisoColaborador(r: any) {
  const { data: ev, error } = await sb.from('eventos')
    .select('titulo, fecha, perfiles!eventos_owner_id_fkey(nombre, email)').eq('id', r.evento_id).single();
  if (error) throw error;
  const dueno = (ev as any).perfiles || {};
  const { data: cuenta } = await sb.from('perfiles').select('id').eq('email', r.email).maybeSingle();

  await enviar(r.email, `Te agregaron al equipo de "${ev.titulo}"`, plantilla('Te sumaron a un evento', [
    `<strong>${esc(dueno.nombre || dueno.email)}</strong> te agregó al equipo de <strong>${esc(ev.titulo)}</strong>` +
      (ev.fecha ? `, el ${esc(fechaLarga(ev.fecha))}.` : '.'),
    `Tu rol: ${esc(ROLES[r.rol] || r.rol)}`,
    cuenta
      ? 'Entra con este mismo correo y lo verás en "Compartidos contigo".'
      : `Para verlo, crea tu cuenta con este mismo correo (${esc(r.email)}), con Google o con una contraseña. No necesitas cuenta de anfitrión.`
  ], cuenta ? { texto: 'Ver el evento', url: APP_URL + '#/' } : { texto: 'Crear mi cuenta', url: APP_URL + '#/registro' }));
}

/* ── Entrada ── */

Deno.serve(async req => {
  if (!AVISO_SECRETO || req.headers.get('x-aviso-secreto') !== AVISO_SECRETO) {
    return new Response('No autorizado', { status: 401 });
  }
  try {
    const { type, table, record, old_record } = await req.json();
    if (table === 'perfiles' && type === 'UPDATE') await avisoPerfil(record, old_record);
    if (table === 'colaboradores' && type === 'INSERT') await avisoColaborador(record);
    return Response.json({ ok: true });
  } catch (e) {
    console.error('Error enviando aviso:', e);
    return Response.json({ ok: false, error: String((e as Error)?.message || e) }, { status: 500 });
  }
});
