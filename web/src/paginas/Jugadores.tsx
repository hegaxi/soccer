import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { exec, fecha, PIES, seg, urlMedio } from '../api';
import { useApp } from '../contexto';
import ClipPlayer from '../componentes/ClipPlayer';
import { Campo, Componentes, Estrellas, Formulario, Modal, Observaciones, useCarga } from '../componentes/comunes';

export function camposJugador(cat: any): Campo[] {
  const pos = cat.posiciones.map((p: any) => ({ v: p.posicionId, e: p.nombre }));
  return [
    { n: 'nombre', e: 'Nombre', req: true }, { n: 'apellidos', e: 'Apellidos', req: true },
    { n: 'posicionId', e: 'Posición', t: 'select', op: pos, req: true }, { n: 'posicionSecundariaId', e: 'Posición secundaria', t: 'select', op: pos },
    { n: 'pieDominante', e: 'Pie dominante', t: 'select', op: [{ v: 'D', e: 'Derecho' }, { v: 'I', e: 'Izquierdo' }, { v: 'A', e: 'Ambidiestro' }], req: true },
    { n: 'dorsal', e: 'Dorsal', t: 'number' }, { n: 'fechaNacimiento', e: 'Fecha de nacimiento', t: 'date' },
    { n: 'estaturaCm', e: 'Estatura (cm)', t: 'number' }, { n: 'pesoKg', e: 'Peso (kg)', t: 'number' },
    { n: 'equipoId', e: 'Equipo', t: 'select', op: cat.equipos.map((e: any) => ({ v: e.equipoId, e: e.nombre })) },
    { n: 'anioGraduacion', e: 'Año de graduación (Class of)', t: 'number', ayuda: 'Solo para reclutamiento universitario' }, { n: 'promedioAcademico', e: 'Promedio académico', t: 'number', paso: '0.01' },
    { n: 'correoContacto', e: 'Correo del jugador o tutor', t: 'email', ayuda: 'A los visores se les muestra el contacto del club; este solo con autorización' }, { n: 'telefonoContacto', e: 'Teléfono del jugador o tutor' },
    { n: 'bio', e: 'Descripción para visores', t: 'area' }, { n: 'activo', e: 'Activo en el plantel', t: 'check' },
  ];
}
export const jugadorVacio = { nombre: '', apellidos: '', posicionId: null, posicionSecundariaId: null, pieDominante: 'D', dorsal: null, fechaNacimiento: '',
  estaturaCm: null, pesoKg: null, equipoId: null, anioGraduacion: null, promedioAcademico: null, correoContacto: '', telefonoContacto: '', bio: '', activo: true };

const Avatar = ({ j, chico }: { j: any; chico?: boolean }) => (
  <div className={'avatar' + (chico ? ' chico' : '')} style={j.fotoMedioId ? { backgroundImage: `url(${urlMedio(j.fotoMedioId, 'mini')})` } : undefined}>
    {!j.fotoMedioId && (j.nombre[0] + j.apellidos[0])}
  </div>
);

export function Jugadores() {
  const { esEditor, cat } = useApp();
  const [busqueda, setBusqueda] = useState(''); const [alta, setAlta] = useState(false);
  const { datos, recargar } = useCarga(async () => (await exec('jugador.listar', { busqueda: busqueda || null }))[0], [busqueda]);
  return (
    <div className="col">
      <div className="fila entre"><h1>Jugadores</h1>
        <div className="fila"><input placeholder="Buscar jugador…" value={busqueda} onChange={e => setBusqueda(e.target.value)} />
          {esEditor && <button className="btn" onClick={() => setAlta(true)}>+ Nuevo jugador</button>}</div></div>
      {datos?.length === 0 && <div className="centro" style={{ minHeight: 200 }}>No hay jugadores.</div>}
      <div className="rejilla">
        {datos?.map(j => (
          <Link key={j.jugadorId} to={`/jugadores/${j.jugadorId}`} className="tarjeta fila" style={{ flexWrap: 'nowrap' }}>
            <Avatar j={j} chico />
            <div className="crece"><b>{j.nombre} {j.apellidos}</b>
              <div className="tenue chico">{j.dorsal ? `#${j.dorsal} · ` : ''}{j.posicion}{j.anioNacimiento ? ` · Cat. ${j.anioNacimiento}` : ''}</div>
              <div className="fila" style={{ gap: 5, marginTop: 4 }}><span className={'etq ' + (j.clips >= 12 ? 'verde' : j.clips > 0 ? 'ambar' : '')}>{j.clips} jugadas</span>{j.reels > 0 && <span className="etq azul">{j.reels} reel(s)</span>}</div></div>
          </Link>
        ))}
      </div>
      {alta && <Modal titulo="Nuevo jugador" cerrar={() => setAlta(false)}>
        <Formulario campos={camposJugador(cat)} inicial={jugadorVacio} cancelar={() => setAlta(false)}
          guardar={async v => { await exec('jugador.guardar', v); setAlta(false); recargar(); }} /></Modal>}
    </div>
  );
}

export function JugadorFicha() {
  const jugadorId = +useParams().id!;
  const { temporadaId, cat, esEditor } = useApp();
  const ir = useNavigate();
  const [soloTemporada, setSoloTemporada] = useState(true);
  const [editar, setEditar] = useState(false); const [clip, setClip] = useState<any>(null); const [foto, setFoto] = useState<any>(null);
  const [duracion, setDuracion] = useState(240); const [error, setError] = useState(''); const [consentir, setConsentir] = useState(false);
  const { datos, error: errCarga, recargar } = useCarga(async () => {
    const [[j], cobertura, clips, diagnostico, fotos, reels, consentimientos] = await exec('jugador.obtener', { jugadorId, temporadaId: soloTemporada ? temporadaId : null });
    return { j, cobertura, clips, diagnostico, fotos, reels, consentimientos };
  }, [jugadorId, temporadaId, soloTemporada]);

  if (errCarga) return <div className="centro">{errCarga}</div>;
  if (!datos) return <div className="centro">Cargando…</div>;
  const { j } = datos;
  const edad = j.fechaNacimiento ? Math.floor((Date.now() - new Date(j.fechaNacimiento).getTime()) / 31557600000) : null;
  const generar = () => exec('reel.generar', { jugadorId, temporadaId: soloTemporada ? temporadaId : null, duracionObjetivoSeg: duracion })
    .then(([[r]]) => ir(`/reels/${r.reelId}`)).catch(e => setError(e.message));
  const { posicion, posicionSecundaria, equipo, esMenor, puedeCompartir, contactoClub, ...editable } = j;

  return (
    <div className="col">
      <div className="tarjeta fila" style={{ alignItems: 'flex-start' }}>
        <Avatar j={j} />
        <div className="crece">
          <h1>{j.nombre} {j.apellidos} {j.dorsal && <span className="tenue">#{j.dorsal}</span>}</h1>
          <div>{j.posicion}{j.posicionSecundaria && ` / ${j.posicionSecundaria}`}{j.equipo && ` · ${j.equipo}`}</div>
          <div className="tenue">{[edad && `${edad} años`, j.estaturaCm && `${(j.estaturaCm / 100).toFixed(2)} m`, j.pesoKg && `${j.pesoKg} kg`, `Pie ${PIES[j.pieDominante].toLowerCase()}`,
            j.fechaNacimiento && `Categoría ${j.fechaNacimiento.slice(0, 4)}`, j.anioGraduacion && `Class of ${j.anioGraduacion}`, j.promedioAcademico && `Promedio ${j.promedioAcademico}`].filter(Boolean).join(' · ')}</div>
          <div className="tenue">Contacto para visores: {j.contactoClub || 'el equipo no tiene contacto registrado'}</div>
          {j.bio && <p style={{ margin: '8px 0 0' }}>{j.bio}</p>}
        </div>
        <div className="col" style={{ alignItems: 'flex-end' }}>
          {esEditor && <button className="btn sec" onClick={() => setEditar(true)}>Editar perfil</button>}
          <label className="check chico"><input type="checkbox" checked={soloTemporada} onChange={e => setSoloTemporada(e.target.checked)} />Solo temporada seleccionada</label>
        </div>
      </div>

      <div className="dos">
        <div className="col">
          <div>
            <h3>Mejores jugadas para reclutamiento ({datos.clips.length})</h3>
            {datos.clips.length === 0 && <div className="tenue">Sin jugadas confirmadas. Se marcan desde los videos de partido.</div>}
            <div className="lista">
              {datos.clips.map((c, i) => (
                <div key={c.clipId} className="item clic" onClick={() => c.medioListo && setClip(c)}>
                  <div className="puesto">{i + 1}</div>
                  <div className="crece"><b>{c.tipoEvento}</b> {c.resultado === 'F' && <span className="etq rojo">fallida</span>} {c.esDecisiva && <span className="etq verde">decisiva</span>} {c.esPieDebil && <span className="etq azul">pie no dominante</span>}
                    <div className="chico tenue">{c.rival ? `vs ${c.rival} (nivel ${c.nivelRival})` : 'Sin partido'}{c.fechaPartido && ` · ${fecha(c.fechaPartido)}`}{c.minuto && ` · min ${c.minuto}`} · {seg(c.segundoFin - c.segundoInicio)} <Estrellas n={c.calidad} /></div>
                    <Componentes c={c} /></div>
                  <div className="puntaje">{c.puntaje}</div>
                </div>
              ))}
            </div>
          </div>
          {datos.fotos.length > 0 && <div><h3>Fotos ({datos.fotos.length})</h3>
            <div className="fotos">{datos.fotos.map(f => <img key={f.medioId} src={urlMedio(f.medioId, 'mini')} alt={f.titulo} title={f.titulo} onClick={() => setFoto(f)} />)}</div></div>}
        </div>

        <div className="col">
          <div className="tarjeta col">
            <h3>Reel de reclutamiento</h3>
            {datos.reels.map(r => (
              <Link key={r.reelId} to={`/reels/${r.reelId}`} className="item clic">
                <div className="crece"><b>{r.titulo}</b><div className="chico tenue">{r.clips} jugadas · {fecha(r.creadoEn)}</div></div>
                <span className={'etq ' + (r.estado === 'LISTO' ? 'verde' : r.estado === 'ERROR' ? 'rojo' : 'ambar')}>{r.estado === 'LISTO' ? 'Listo' : r.estado === 'EN_COLA' ? 'Renderizando' : r.estado === 'ERROR' ? 'Error' : 'Borrador'}</span>
                {r.publicado && <span className="etq azul">Compartido</span>}
              </Link>
            ))}
            {esEditor && <div className="fila">
              <select value={duracion} onChange={e => setDuracion(+e.target.value)} aria-label="Duración objetivo">
                <option value={120}>2 minutos</option><option value={180}>3 minutos</option><option value={240}>4 minutos (recomendado)</option><option value={300}>5 minutos</option>
              </select>
              <button className="btn" onClick={generar} disabled={datos.clips.length === 0}>Generar reel automático</button>
            </div>}
            {error && <div className="aviso error">{error}</div>}
          </div>
          <div><h3>Diagnóstico del material</h3><Observaciones lista={datos.diagnostico} /></div>
          {(j.esMenor || datos.consentimientos.length > 0) && (
            <div className="tarjeta col">
              <div className="fila entre"><h3 style={{ margin: 0 }}>Consentimiento del tutor</h3>
                <span className={'etq ' + (j.puedeCompartir ? 'verde' : 'rojo')}>{j.puedeCompartir ? 'Se puede compartir' : 'No se puede compartir'}</span></div>
              {datos.consentimientos.length === 0 && <span className="tenue chico">Sin la autorización firmada de madre, padre o tutor, el reel de un menor no sale del club.</span>}
              <div className="lista">
                {datos.consentimientos.map(c => (
                  <div key={c.consentimientoId} className="item">
                    <div className="crece"><b>{c.tutorNombre}</b> <span className="tenue">· {c.parentesco}</span> <span className={'etq ' + (c.estado === 'VIGENTE' ? 'verde' : 'rojo')}>{c.estado === 'VIGENTE' ? 'Vigente' : c.estado === 'VENCIDO' ? 'Vencido' : 'Revocado'}</span>
                      <div className="chico tenue">Firmó el {fecha(c.fecha)}{c.vigenteHasta && ` · vigente hasta el ${fecha(c.vigenteHasta)}`} · autoriza: {[c.permiteReelPublico && 'compartir el reel', c.permiteContacto && 'mostrar su contacto'].filter(Boolean).join(' y ')}{c.referencia && ` · ${c.referencia}`}</div></div>
                    {esEditor && c.estado === 'VIGENTE' && <button className="btn peligro mini" onClick={() => confirm('¿Revocar este consentimiento? Los enlaces del jugador dejarán de abrir de inmediato.') && exec('consentimiento.revocar', { consentimientoId: c.consentimientoId }).then(recargar)}>Revocar</button>}
                  </div>
                ))}
              </div>
              {esEditor && <button className="btn sec" onClick={() => setConsentir(true)}>Registrar consentimiento</button>}
            </div>
          )}
          <div>
            <h3>Cobertura para la posición</h3>
            <table><thead><tr><th>Jugada</th><th>Peso</th><th className="der">Jugadas</th><th className="der">Mejor</th></tr></thead>
              <tbody>{datos.cobertura.map(c => (
                <tr key={c.tipoEventoId}><td>{c.nombre} {c.esClave && <span className="etq ambar">clave</span>}</td><td className="tenue">×{c.multiplicador}</td>
                  <td className="der" style={c.esClave && c.jugadas === 0 ? { color: 'var(--rojo)', fontWeight: 700 } : undefined}>{c.jugadas}</td><td className="der">{c.mejorPuntaje ?? '—'}</td></tr>
              ))}</tbody></table>
          </div>
        </div>
      </div>

      {editar && <Modal titulo="Editar perfil" cerrar={() => setEditar(false)}>
        <Formulario campos={camposJugador(cat)} inicial={{ ...editable, fechaNacimiento: j.fechaNacimiento ?? '' }} cancelar={() => setEditar(false)}
          guardar={async v => { await exec('jugador.guardar', v); setEditar(false); recargar(); }} /></Modal>}
      {consentir && <Modal titulo="Consentimiento del tutor" cerrar={() => setConsentir(false)}>
        <p className="tenue" style={{ marginTop: 0 }}>Registra aquí la autorización que el tutor firmó en papel o por escrito. Queda guardado quién la registró y cuándo.</p>
        <Formulario cancelar={() => setConsentir(false)} texto="Registrar"
          campos={[{ n: 'tutorNombre', e: 'Nombre del tutor', req: true }, { n: 'parentesco', e: 'Parentesco', req: true, t: 'select', op: ['Madre', 'Padre', 'Tutor legal'].map(x => ({ v: x, e: x })) },
            { n: 'fecha', e: 'Fecha de firma', t: 'date', req: true }, { n: 'vigenteHasta', e: 'Vigente hasta (opcional)', t: 'date' },
            { n: 'referencia', e: 'Dónde está el documento', ancho: true, ayuda: 'Folio, carpeta o archivo donde se guarda la autorización firmada' },
            { n: 'permiteReelPublico', e: 'Autoriza compartir el reel con visores', t: 'check' }, { n: 'permiteContacto', e: 'Autoriza mostrar su contacto a los visores', t: 'check' }]}
          inicial={{ tutorNombre: '', parentesco: 'Madre', fecha: new Date().toISOString().slice(0, 10), vigenteHasta: '', referencia: '', permiteReelPublico: true, permiteContacto: false }}
          guardar={async v => { await exec('consentimiento.guardar', { jugadorId, ...v }); setConsentir(false); recargar(); }} /></Modal>}
      {clip && <Modal titulo={`${clip.tipoEvento}${clip.rival ? ` · vs ${clip.rival}` : ''}`} cerrar={() => { setClip(null); recargar(); }} grande>
        <ClipPlayer clip={clip} />
        <div className="fila" style={{ marginTop: 8 }}><Link className="btn sec mini" to={`/medio/${clip.medioId}`}>Abrir el video completo</Link></div></Modal>}
      {foto && <Modal titulo={foto.titulo} cerrar={() => setFoto(null)} grande>
        <img src={urlMedio(foto.medioId, 'web')} alt={foto.titulo} style={{ width: '100%', maxHeight: '70vh', objectFit: 'contain' }} />
        {esEditor && <div className="fila" style={{ marginTop: 8 }}><button className="btn sec mini" onClick={() => exec('jugador.guardar', { ...editable, fotoMedioId: foto.medioId }).then(() => { setFoto(null); recargar(); })}>Usar como foto de perfil</button></div>}</Modal>}
    </div>
  );
}
