import { useEffect, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { exec, fecha, PIES, seg, urlMedio } from '../api';
import { useApp } from '../contexto';
import { avisar, Componentes, Estrellas, Formulario, Modal, useCarga } from '../componentes/comunes';

const nuevo = (t: number) => ({ clipId: null, jugadorId: '', tipoEventoId: '', segundoEvento: Math.round(t * 10) / 10, segundoInicio: null, segundoFin: null,
  resultado: 'E', pie: '', calidad: 3, esDecisiva: false, marcaX: null, marcaY: null, nota: '', minuto: null });

export default function VideoDetalle() {
  const medioId = +useParams().id!;
  const ir = useNavigate();
  const { esEditor, cat } = useApp();
  const video = useRef<HTMLVideoElement>(null);
  const [t, setT] = useState(0);
  const [form, setForm] = useState<any>(null);       // jugada en edición
  const [marcando, setMarcando] = useState(false);
  const [error, setError] = useState(''); const [editarDatos, setEditarDatos] = useState(false);
  const ultimo = useRef(0);

  const { datos, error: errCarga, recargar } = useCarga(async () => {
    const [[medio], clips, jugadores] = await exec('medio.obtener', { medioId });
    return { medio, clips, jugadores };
  }, [medioId]);
  const plantel = useCarga(async () => (await exec('jugador.listar'))[0], []);
  const partidos = useCarga(async () => datos?.medio ? (await exec('partido.listar', { temporadaId: datos.medio.temporadaId }))[0] : [], [datos?.medio?.temporadaId]);

  const medio = datos?.medio;
  useEffect(() => {
    if (!medio || medio.estado === 'LISTO' || medio.estado === 'ERROR') return;
    const x = setTimeout(recargar, 3000); return () => clearTimeout(x);
  }, [medio, recargar]);
  useEffect(() => { if (medio?.estado === 'LISTO') exec('medio.interaccion', { medioId, tipo: 'VISTA' }).catch(() => {}); }, [medio?.estado, medioId]);

  if (errCarga) return <div className="centro">{errCarga}</div>;
  if (!medio) return <div className="centro">Cargando…</div>;
  if (medio.tipo !== 'VIDEO') return <div className="centro">Este medio es una foto; ábrela desde la galería.</div>;

  const dur = medio.duracionSeg || 1;
  const irA = (s: number, reproducir = true) => { const v = video.current; if (!v) return; v.currentTime = Math.max(0, s); if (reproducir) v.play().catch(() => {}); };
  const alBuscar = () => {
    const v = video.current!; // regresar más de 3 s = el usuario quiso volver a ver algo
    if (v.currentTime < ultimo.current - 3) exec('medio.interaccion', { medioId, tipo: 'REPETICION', segundo: Math.floor(v.currentTime) }).catch(() => {});
    ultimo.current = v.currentTime;
  };
  const tipoSel = cat.tipos.find(x => x.tipoEventoId === +form?.tipoEventoId);
  const pon = (c: any) => setForm((f: any) => ({ ...f, ...c }));

  const guardar = async () => {
    setError('');
    try {
      const p: any = { ...form, medioId, pie: form.pie || null, nota: form.nota || null };
      if (p.clipId == null) delete p.clipId; else delete p.medioId;
      if (!p.jugadorId || !p.tipoEventoId) throw new Error('Elige el jugador y el tipo de jugada');
      await exec('clip.guardar', p);
      setForm(null); setMarcando(false); recargar();
    } catch (e: any) { setError(e.message); }
  };
  const descartar = (clipId: number, msg: string) => confirm(msg) && exec('clip.eliminar', { clipId }).then(recargar).catch(e => avisar(e.message, 'error'));
  const editar = (c: any) => { setForm({ ...nuevo(c.segundoEvento), ...c, jugadorId: c.jugadorId ?? '', tipoEventoId: c.tipoEventoId ?? '', pie: c.pie ?? '', calidad: c.calidad ?? 3, nota: c.estado === 'CANDIDATO' ? '' : c.nota ?? '' }); irA(c.segundoInicio, false); };
  const meGusta = (c: any) => exec('clip.meGusta', { clipId: c.clipId }).then(recargar).catch(() => {});

  const confirmadas = datos!.clips.filter(c => c.estado === 'CONFIRMADO');
  const candidatos = datos!.clips.filter(c => c.estado === 'CANDIDATO');

  return (
    <div className="col">
      <div className="fila entre">
        <div>
          <h1>{medio.titulo}</h1>
          <div className="tenue">{medio.partido ?? 'Sin partido asignado'}{medio.fechaPartido && ` · ${fecha(medio.fechaPartido)}`}{medio.fase && ` · ${medio.fase}`}
            {medio.nivelRival && ` · rival nivel ${medio.nivelRival}/5`} · subido por {medio.subidoPor}</div>
        </div>
        {esEditor && <div className="fila">
          <button className="btn sec" onClick={() => setEditarDatos(true)}>Editar datos</button>
          <button className="btn peligro" onClick={() => confirm('¿Eliminar este video y sus jugadas?') && exec('medio.eliminar', { medioId }).then(() => ir('/'))}>Eliminar</button>
        </div>}
      </div>
      {medio.estado === 'ERROR' && <div className="aviso error">No se pudo procesar el video: {medio.errorProceso}</div>}
      {(medio.estado === 'SUBIDO' || medio.estado === 'PROCESANDO') && <div className="aviso">El video se está procesando (versión web, miniatura y análisis de audio). Esta página se actualiza sola.</div>}

      <div className="dos">
        <div>
          <div className="reproductor" style={medio.ancho && medio.alto ? { aspectRatio: `${medio.ancho}/${medio.alto}` } : undefined}>
            {medio.estado === 'LISTO' && <video ref={video} src={urlMedio(medioId)} controls playsInline
              onTimeUpdate={e => { setT(e.currentTarget.currentTime); if (!e.currentTarget.seeking) ultimo.current = e.currentTarget.currentTime; }} onSeeked={alBuscar} />}
            {marcando && <div className="capa" title="Haz clic sobre el jugador" onClick={e => {
              const r = e.currentTarget.getBoundingClientRect();
              pon({ marcaX: +(((e.clientX - r.left) / r.width) * 100).toFixed(1), marcaY: +(((e.clientY - r.top) / r.height) * 100).toFixed(1) }); setMarcando(false);
            }} />}
            {form?.marcaX != null && <div className="marca-jugador" style={{ left: `${form.marcaX}%`, top: `${form.marcaY}%` }} />}
          </div>
          <div className="linea-tiempo" onClick={e => { const r = e.currentTarget.getBoundingClientRect(); irA(((e.clientX - r.left) / r.width) * dur, false); }}>
            {datos!.clips.map(c => (
              <div key={c.clipId} className={'ev ' + (c.estado === 'CANDIDATO' ? 'CAND' : c.categoria)} title={c.estado === 'CANDIDATO' ? c.nota : `${c.tipoEvento} · ${c.jugador}`}
                   style={{ left: `${(c.segundoInicio / dur) * 100}%`, width: `${((c.segundoFin - c.segundoInicio) / dur) * 100}%` }} />
            ))}
            <div className="pos" style={{ left: `${(t / dur) * 100}%` }} />
          </div>
          <div className="fila chico tenue" style={{ marginTop: 6 }}>
            <span><i className="ev ATAQUE" style={{ position: 'static', display: 'inline-block', width: 10, height: 10 }} /> Ataque</span>
            <span><i className="ev CREACION" style={{ position: 'static', display: 'inline-block', width: 10, height: 10 }} /> Creación</span>
            <span><i className="ev DEFENSA" style={{ position: 'static', display: 'inline-block', width: 10, height: 10 }} /> Defensa</span>
            <span><i className="ev PORTERIA" style={{ position: 'static', display: 'inline-block', width: 10, height: 10 }} /> Portería</span>
            <span><i className="ev CAND" style={{ position: 'static', display: 'inline-block', width: 10, height: 10 }} /> Por revisar</span>
            <span className="crece der">{seg(t)} / {seg(medio.duracionSeg)}{medio.segundoInicioPartido == null && esEditor && ' · sin inicio de partido: el minuto no se calcula'}</span>
          </div>

          {esEditor && medio.estado === 'LISTO' && !form && (
            <button className="btn" style={{ marginTop: 12 }} onClick={() => { video.current?.pause(); setForm(nuevo(t)); }}>+ Marcar jugada en {seg(t)}</button>
          )}
          {form && (
            <div className="tarjeta col" style={{ marginTop: 12 }}>
              <h2>{form.clipId ? 'Editar jugada' : 'Nueva jugada'} · {seg(form.segundoEvento)}</h2>
              <div className="form">
                <label>Jugador *<select value={form.jugadorId} onChange={e => pon({ jugadorId: +e.target.value || '' })}>
                  <option value="">—</option>{plantel.datos?.map(j => <option key={j.jugadorId} value={j.jugadorId}>{j.dorsal ? `#${j.dorsal} ` : ''}{j.nombre} {j.apellidos}</option>)}</select></label>
                <label>Tipo de jugada *<select value={form.tipoEventoId} onChange={e => pon({ tipoEventoId: +e.target.value || '', segundoInicio: null, segundoFin: null })}>
                  <option value="">—</option>
                  {['ATAQUE', 'CREACION', 'DEFENSA', 'PORTERIA'].map(g => <optgroup key={g} label={g}>{cat.tipos.filter(x => x.categoria === g).map(x => <option key={x.tipoEventoId} value={x.tipoEventoId}>{x.nombre}</option>)}</optgroup>)}</select></label>
                <label>Resultado<select value={form.resultado} onChange={e => pon({ resultado: e.target.value })}><option value="E">Exitosa</option><option value="F">Fallida</option></select></label>
                <label>Ejecutada con<select value={form.pie} onChange={e => pon({ pie: e.target.value })}><option value="">No aplica</option><option value="D">Pie derecho</option><option value="I">Pie izquierdo</option><option value="C">Cabeza</option></select></label>
                <label>Calidad técnica (1-5)<input type="range" min={1} max={5} value={form.calidad} onChange={e => pon({ calidad: +e.target.value })} /><Estrellas n={form.calidad} /></label>
                <label>Minuto de partido<input type="number" min={1} max={130} value={form.minuto ?? ''} placeholder={medio.segundoInicioPartido != null ? 'automático' : ''} onChange={e => pon({ minuto: e.target.value ? +e.target.value : null })} /></label>
                <label>Momento exacto (s)<div className="fila"><input className="crece" type="number" step="0.1" value={form.segundoEvento} onChange={e => pon({ segundoEvento: +e.target.value })} />
                  <button type="button" className="btn sec mini" onClick={() => pon({ segundoEvento: Math.round(t * 10) / 10 })}>Usar {seg(t)}</button></div></label>
                <label>Inicio / fin del clip (s)<div className="fila">
                  <input className="crece" type="number" step="0.5" value={form.segundoInicio ?? ''} placeholder={tipoSel ? String(Math.max(0, form.segundoEvento - tipoSel.preRollSeg)) : 'auto'} onChange={e => pon({ segundoInicio: e.target.value ? +e.target.value : null })} />
                  <input className="crece" type="number" step="0.5" value={form.segundoFin ?? ''} placeholder={tipoSel ? String(form.segundoEvento + tipoSel.postRollSeg) : 'auto'} onChange={e => pon({ segundoFin: e.target.value ? +e.target.value : null })} /></div></label>
                <label className="check"><input type="checkbox" checked={form.esDecisiva} onChange={e => pon({ esDecisiva: e.target.checked })} />Jugada decisiva (cambió o salvó el resultado)</label>
                <label className="ancho">Nota<input value={form.nota ?? ''} maxLength={300} onChange={e => pon({ nota: e.target.value })} /></label>
              </div>
              <div className="fila">
                <button type="button" className={'btn ' + (marcando ? '' : 'sec')} onClick={() => { irA(form.segundoInicio ?? Math.max(0, form.segundoEvento - (tipoSel?.preRollSeg ?? 6)), false); video.current?.pause(); setMarcando(true); }}>
                  {marcando ? 'Haz clic sobre el jugador en el video…' : form.marcaX != null ? '✓ Jugador señalado (cambiar)' : 'Señalar al jugador al inicio del clip'}</button>
                {form.marcaX != null && <button type="button" className="btn sec mini" onClick={() => pon({ marcaX: null, marcaY: null })}>Quitar marca</button>}
                <span className="tenue chico crece">El visor debe saber a quién mirar antes de que empiece la jugada.</span>
              </div>
              {error && <div className="aviso error">{error}</div>}
              <div className="fila" style={{ justifyContent: 'flex-end' }}>
                <button className="btn sec" onClick={() => { setForm(null); setMarcando(false); setError(''); }}>Cancelar</button>
                <button className="btn" onClick={guardar}>Guardar jugada</button>
              </div>
            </div>
          )}
        </div>

        <div className="col">
          {esEditor && candidatos.length > 0 && (
            <div>
              <h3>Por revisar ({candidatos.length})</h3>
              <div className="lista">
                {candidatos.map(c => (
                  <div key={c.clipId} className="item">
                    <div className="crece"><b>{seg(c.segundoEvento)}</b> <span className="etq ambar">{c.origen === 'AUDIO' ? 'Audio' : 'Repeticiones'}</span>
                      <div className="chico tenue">{c.nota}</div></div>
                    <button className="btn sec mini" onClick={() => irA(c.segundoInicio)}>Ver</button>
                    <button className="btn mini" onClick={() => editar(c)}>Confirmar</button>
                    <button className="btn peligro mini" onClick={() => descartar(c.clipId, '¿Descartar este candidato?')}>✕</button>
                  </div>
                ))}
              </div>
            </div>
          )}
          <div>
            <div className="fila entre"><h3>Jugadas ({confirmadas.length})</h3>
              {esEditor && medio.estado === 'LISTO' && <button className="btn sec mini" onClick={() => exec('medio.candidatos', { medioId }).then(([[r]]) => { recargar(); avisar(r.nuevos ? `${r.nuevos} candidato(s) nuevos por revisar` : 'No hay candidatos nuevos'); })}>Buscar candidatos</button>}</div>
            {confirmadas.length === 0 && <div className="tenue">{esEditor ? 'Aún no hay jugadas. Pausa el video en el momento y usa «Marcar jugada».' : 'Aún no hay jugadas marcadas en este video.'}</div>}
            <div className="lista">
              {confirmadas.map(c => (
                <div key={c.clipId} className={'item' + (t >= c.segundoInicio && t <= c.segundoFin ? ' sel' : '')}>
                  <div className="crece clic" style={{ cursor: 'pointer' }} onClick={() => irA(c.segundoInicio)}>
                    <b>{c.tipoEvento}</b> · {c.jugador} {c.resultado === 'F' && <span className="etq rojo">fallida</span>} {c.esDecisiva && <span className="etq verde">decisiva</span>}
                    <div className="chico tenue">{seg(c.segundoInicio)}–{seg(c.segundoFin)}{c.minuto && ` · min ${c.minuto}`}{c.pie && ` · ${PIES[c.pie]}`} <Estrellas n={c.calidad} />{c.marcaX == null && esEditor && ' · sin señalar'}</div>
                    <Componentes c={c} />
                  </div>
                  <button className="btn sec mini" onClick={() => meGusta(c)} title="Me gusta">{c.miMeGusta ? '♥' : '♡'} {c.meGusta}</button>
                  <div className="puntaje" title="Puntaje de reclutamiento">{c.puntajeReclutamiento}</div>
                  {esEditor && <><button className="btn sec mini" onClick={() => editar(c)}>Editar</button>
                    <button className="btn peligro mini" onClick={() => descartar(c.clipId, '¿Eliminar esta jugada? También saldrá de los reels.')}>✕</button></>}
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {editarDatos && (
        <Modal titulo="Datos del video" cerrar={() => setEditarDatos(false)}>
          <Formulario
            campos={[
              { n: 'titulo', e: 'Título', req: true, ancho: true }, { n: 'descripcion', e: 'Descripción', t: 'area' },
              { n: 'partidoId', e: 'Partido', t: 'select', op: (partidos.datos ?? []).map(p => ({ v: p.partidoId, e: `${fecha(p.fecha)} · ${p.local} vs ${p.visita}` })) },
              { n: 'segundoInicioPartido', e: 'Segundo en que inicia el partido', t: 'number', paso: '0.1', ayuda: `Tiempo actual del video: ${t.toFixed(1)} s. Con este dato se calcula el minuto de cada jugada.` },
            ]}
            inicial={{ titulo: medio.titulo, descripcion: medio.descripcion ?? '', partidoId: medio.partidoId, segundoInicioPartido: medio.segundoInicioPartido }}
            cancelar={() => setEditarDatos(false)}
            guardar={async v => { await exec('medio.actualizar', { medioId, ...v }); setEditarDatos(false); recargar(); }} />
        </Modal>
      )}
    </div>
  );
}
