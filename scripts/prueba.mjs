// Prueba de punta a punta contra una API en marcha con los datos de demostración.
// Uso: node scripts/prueba.mjs <video.mp4> <foto.jpg>   (variables: API, CORREO, CLAVE)
import { readFile } from 'node:fs/promises';
import { basename } from 'node:path';
import assert from 'node:assert/strict';

const API = process.env.API ?? 'http://localhost:5080';
const [videoPath, fotoPath] = process.argv.slice(2);
if (!videoPath || !fotoPath) { console.error('Uso: node scripts/prueba.mjs <video> <foto>'); process.exit(2); }
let cookie = '';

async function exec(accion, params, { espera } = {}) {
  const r = await fetch(`${API}/api/exec`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', cookie }, body: JSON.stringify({ accion, params }),
  });
  const sc = r.headers.get('set-cookie'); if (sc) cookie = sc.split(';')[0];
  const j = await r.json();
  if (espera) { assert.equal(r.status, espera, `${accion} debía responder ${espera}: ${JSON.stringify(j)}`); return j; }
  assert.ok(j.ok, `${accion} falló (${r.status}): ${j.error}`);
  return j.resultados;
}

async function subir(tipo, ruta, extra) {
  const datos = await readFile(ruta);
  const [[{ medioId }]] = await exec('medio.crear', { tipo, nombreOriginal: basename(ruta), tamanoBytes: datos.length, ...extra });
  const parte = 8 * 1024 * 1024;
  for (let o = 0; o < datos.length; o += parte) {
    const r = await fetch(`${API}/api/archivo/${medioId}?offset=${o}`, { method: 'PUT', headers: { cookie }, body: datos.subarray(o, o + parte) });
    assert.equal(r.status, 200, `subida parte ${o}: ${await r.text()}`);
  }
  return medioId;
}

async function esperar(fn, que, seg = 120) {
  for (let i = 0; i < seg; i++) { const v = await fn(); if (v) return v; await new Promise(r => setTimeout(r, 1000)); }
  throw new Error(`Tiempo agotado esperando ${que}`);
}
const paso = (t) => console.log('✓', t);

// --- seguridad del despachador
await exec('catalogo.inicial', null, { espera: 401 });
await exec('trabajo.tomar', null, { espera: 404 });                       // las internas no existen para el cliente
await exec('sesion.iniciar', { correo: process.env.CORREO ?? 'admin@soccer.local', clave: process.env.CLAVE ?? 'Admin123!' });
await exec('jugador.listar', { _usuarioId: 1 }, { espera: 400 });
paso('sesión y rechazo de acciones/parámetros no permitidos');

const [temporadas, , tipos] = await exec('catalogo.inicial');
const temporadaId = temporadas[0].temporadaId;
const tipo = (c) => tipos.find(t => t.clave === c).tipoEventoId;
const [jugadores] = await exec('jugador.listar');
const dc = jugadores.find(j => j.posicionClave === 'DC');
const [partidos] = await exec('partido.listar', { temporadaId });
const elite = partidos.find(p => p.nivelRival === 5), liga = partidos.find(p => p.nivelRival === 3);

// --- foto
const fotoId = await subir('FOTO', fotoPath, { titulo: 'Foto de perfil', temporadaId, jugadoresJson: [dc.jugadorId] });
await esperar(async () => (await exec('medio.obtener', { medioId: fotoId }))[0][0].estado === 'LISTO', 'foto lista');
const mini = await fetch(`${API}/api/archivo/${fotoId}?v=mini`, { headers: { cookie } });
assert.equal(mini.headers.get('content-type'), 'image/jpeg');
assert.equal((await fetch(`${API}/api/archivo/${fotoId}?v=mini`)).status, 401, 'sin sesión no se entregan archivos');
paso('foto subida, procesada y protegida');

// --- videos (el mismo archivo como dos partidos distintos)
const v1 = await subir('VIDEO', videoPath, { titulo: 'Halcones vs Academia Élite', temporadaId, partidoId: elite.partidoId });
const v2 = await subir('VIDEO', videoPath, { titulo: 'Halcones vs Atlético Norte', temporadaId, partidoId: liga.partidoId });
const det = await esperar(async () => {
  const d = await exec('medio.obtener', { medioId: v1 });
  const d2 = await exec('medio.obtener', { medioId: v2 });
  if (d[0][0].estado === 'ERROR') throw new Error(d[0][0].errorProceso);
  return d[0][0].estado === 'LISTO' && d2[0][0].estado === 'LISTO' && d;
}, 'videos listos');
assert.ok(det[0][0].duracionSeg > 60);
const candidatos = det[1].filter(c => c.estado === 'CANDIDATO');
assert.ok(candidatos.length >= 2, 'los picos de audio deben generar candidatos');
paso(`videos procesados; candidatos por audio en ${candidatos.map(c => c.segundoEvento + 's').join(', ')}`);

const rango = await fetch(`${API}/api/archivo/${v1}`, { headers: { cookie, Range: 'bytes=1000-1999' } });
assert.equal(rango.status, 206); assert.equal((await rango.arrayBuffer()).byteLength, 1000);
paso('video servido con Range');

// --- jugadas
await exec('medio.actualizar', { medioId: v1, titulo: 'Halcones vs Academia Élite', partidoId: elite.partidoId, segundoInicioPartido: 2 });
const clip = (medioId, clave, seg, extra = {}) =>
  exec('clip.guardar', { medioId, jugadorId: dc.jugadorId, tipoEventoId: tipo(clave), segundoEvento: seg, ...extra }).then(r => r[0][0]);
// confirmar un candidato automático como gol decisivo ante el rival élite
const golElite = (await exec('clip.guardar', { clipId: candidatos[0].clipId, jugadorId: dc.jugadorId, tipoEventoId: tipo('GOL'),
  segundoEvento: candidatos[0].segundoEvento, calidad: 5, esDecisiva: true, pie: 'I', marcaX: 40, marcaY: 55 }))[0][0];
const golLiga = await clip(v2, 'GOL', 21, { calidad: 3, pie: 'D' });
const gol2 = await clip(v2, 'GOL', 46, { calidad: 3, pie: 'D' });
const gol3 = await clip(v2, 'GOL', 60, { calidad: 3 });
const desmarque = await clip(v1, 'DESMARQUE', 33, { calidad: 4, marcaX: 60, marcaY: 40 });
const presion = await clip(v1, 'PRESION', 55, { calidad: 4 });
const fallida = await clip(v2, 'TIRO_PUERTA', 10, { calidad: 2, resultado: 'F' });
assert.ok(golElite.puntajeReclutamiento > golLiga.puntajeReclutamiento + 15, 'rival élite + decisiva + pie débil + calidad deben pesar');
await exec('clip.guardar', { medioId: v1, jugadorId: dc.jugadorId, tipoEventoId: tipo('GOL'), segundoEvento: 9999 }, { espera: 400 });
paso(`puntaje: gol decisivo ante élite ${golElite.puntajeReclutamiento} vs gol de liga ${golLiga.puntajeReclutamiento}`);

// --- interacción y ranking
await exec('clip.interaccion', { clipId: golLiga.clipId, tipo: 'VISTA' });
const [[mg]] = await exec('clip.meGusta', { clipId: golLiga.clipId });
assert.equal(mg.meGusta, 1);
const [top] = await exec('highlight.top', { temporadaId, modo: 'RECLUTAMIENTO' });
assert.equal(top[0].clipId, golElite.clipId);
paso('ranking de highlights');

// --- roles: un espectador ve y reacciona, pero no modifica
const correoEsp = `espectador${Date.now()}@example.com`;
await exec('usuario.guardar', { correo: correoEsp, nombre: 'Espectador de prueba', rol: 1, clave: 'Espectador1!' });
const admin = cookie; cookie = '';
await exec('sesion.iniciar', { correo: correoEsp, clave: 'Espectador1!' });
await exec('highlight.top', { temporadaId });
await exec('clip.guardar', { medioId: v1, jugadorId: dc.jugadorId, tipoEventoId: tipo('GOL'), segundoEvento: 5 }, { espera: 403 });
await exec('usuario.listar', null, { espera: 403 });
assert.equal((await fetch(`${API}/api/archivo/${v1}?offset=0`, { method: 'PUT', headers: { cookie }, body: 'x' })).status, 403);
await exec('sesion.cerrar'); await exec('highlight.top', { temporadaId }, { espera: 401 });   // la sesión cerrada ya no sirve
cookie = admin;
paso('permisos por rol y cierre de sesión');

// --- reel de reclutamiento
const [[{ reelId }]] = await exec('reel.generar', { jugadorId: dc.jugadorId, temporadaId, duracionObjetivoSeg: 90 });
let [reel, clips, obs] = await exec('reel.obtener', { reelId });
const orden = clips.map(c => c.tipoEvento);
assert.equal(clips[0].clipId, golElite.clipId, 'el reel abre con la mejor jugada');
assert.ok(!clips.some(c => c.clipId === fallida.clipId), 'las fallidas de baja calidad quedan fuera');
const iDesm = clips.findIndex(c => c.clipId === desmarque.clipId), iGol3 = clips.findIndex(c => c.clipId === gol3.clipId);
assert.ok(iDesm >= 0 && (iGol3 < 0 || iDesm < iGol3), 'la variedad debe adelantar al desmarque sobre el tercer gol repetido');
assert.ok(obs.some(o => /pie no dominante|contacto|nivel alto|Falta evidencia|Solo hay/.test(o.mensaje)));
paso(`reel generado: ${orden.join(' → ')}`);
console.log('   observaciones:\n' + obs.map(o => `     [${o.severidad}] ${o.mensaje}`).join('\n'));

await exec('reel.enlaceCrear', { reelId, destinatario: 'Visor de prueba' }, { espera: 409 });   // no se comparte sin renderizar
await exec('reel.renderizar', { reelId });
reel = await esperar(async () => {
  const [[r]] = await exec('reel.obtener', { reelId });
  if (r.estado === 'ERROR') throw new Error(r.errorProceso);
  return r.estado === 'LISTO' && r;
}, 'reel renderizado', 180);
paso(`reel renderizado (${reel.duracionSeg}s)`);

// --- criterio de visoría
assert.equal(golElite.puntajeReclutamiento, golElite.tecnico, 'el puntaje de reclutamiento es solo el valor técnico');
const por = jugadores.find(j => j.posicionClave === 'POR');
const [, coberturaPor, , diagPor] = await exec('jugador.obtener', { jugadorId: por.jugadorId });
assert.ok(!diagPor.some(d => /Penal/.test(d.mensaje)), 'a un portero no se le exige un penal atajado');
assert.ok(coberturaPor.some(c => c.nombre.startsWith('Saque') && c.esClave), 'la distribución sí es clave en un portero');
paso('criterio: reclutamiento 100 % técnico; penal atajado no es exigible');

// --- menores: sin consentimiento del tutor no hay enlace
const negado = await exec('reel.enlaceCrear', { reelId, destinatario: 'Visor de prueba' }, { espera: 409 });
assert.match(negado.error, /consentimiento/);
const [[{ consentimientoId }]] = await exec('consentimiento.guardar', { jugadorId: dc.jugadorId, tutorNombre: 'Laura Soto', parentesco: 'Madre', fecha: '2026-09-01' });
const [[{ token: tokenPublico, enlaceId }]] = await exec('reel.enlaceCrear', { reelId, destinatario: 'Visor de prueba', dias: 7 });
const [[{ token: token2 }]] = await exec('reel.enlaceCrear', { reelId, destinatario: 'Universidad de prueba' });
paso('consentimiento del tutor exigido para compartir el reel de un menor');

const sesion = cookie; cookie = '';                                        // como un visor sin cuenta
const [pub, pubClips] = await exec('reel.publico', { token: tokenPublico });
const p = pub[0];
assert.equal(p.jugador, `${dc.nombre} ${dc.apellidos}`);
assert.equal(p.anioNacimiento, 2009);
assert.ok(!('fechaNacimiento' in p) && !('correoContacto' in p) && !('telefonoContacto' in p), 'no se expone fecha de nacimiento ni contacto del menor');
assert.equal(p.correoPersonal, null, 'el contacto personal no aparece sin autorización expresa');
assert.match(p.contactoCorreo, /halconesfc/, 'se muestra el contacto del club');
assert.ok(pubClips.every(c => c.medioId === null), 'el enlace no expone los videos fuente');
const vid = await fetch(`${API}/api/archivo/reel/${reelId}?k=${tokenPublico}`, { headers: { Range: 'bytes=0-99' } });
assert.equal(vid.status, 206);
assert.match(vid.headers.get('x-robots-tag') ?? '', /noindex/);
assert.equal((await fetch(`${API}/api/archivo/reel/${reelId}?k=otro`)).status, 401);
assert.equal((await fetch(`${API}/api/archivo/${v1}?k=${tokenPublico}`)).status, 401);
await exec('reel.publico', { token: 'noexiste' }, { espera: 404 });
paso('enlace: solo el reel, año de nacimiento y contacto del club');

cookie = sesion;
let [, , , enlaces] = await exec('reel.obtener', { reelId });
assert.equal(enlaces.find(e => e.enlaceId === enlaceId).vistas, 1, 'cada apertura queda registrada');
await exec('reel.enlaceRevocar', { enlaceId });
cookie = '';
await exec('reel.publico', { token: tokenPublico }, { espera: 404 });      // el retirado ya no abre…
await exec('reel.publico', { token: token2 });                             // …y el otro destinatario no se ve afectado
cookie = sesion;
await exec('consentimiento.revocar', { consentimientoId });
cookie = '';
await exec('reel.publico', { token: token2 }, { espera: 404 });            // al revocar el tutor, todo deja de abrir
assert.equal((await fetch(`${API}/api/archivo/reel/${reelId}?k=${token2}`)).status, 401);
cookie = sesion;
await exec('consentimiento.guardar', { jugadorId: dc.jugadorId, tutorNombre: 'Laura Soto', parentesco: 'Madre', fecha: '2026-09-02', permiteContacto: true });
cookie = '';
const [[conContacto]] = await exec('reel.publico', { token: token2 });
assert.equal(conContacto.correoPersonal, 'diego.ramirez@example.com', 'con autorización de contacto sí aparece');
cookie = sesion;
paso('enlaces por destinatario: registro de vistas, retiro individual y revocación del tutor');

console.log(`\nTodo correcto. reelId=${reelId} token=${token2} jugadorId=${dc.jugadorId} video=${v1}`);
