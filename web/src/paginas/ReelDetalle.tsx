import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { exec, seg, urlReel } from '../api';
import { useApp } from '../contexto';
import ClipPlayer from '../componentes/ClipPlayer';
import { Estrellas, Observaciones, useCarga } from '../componentes/comunes';

const ESTADO: Record<string, [string, string]> = { BORRADOR: ['Borrador', 'ambar'], EN_COLA: ['Renderizando…', 'ambar'], LISTO: ['Video listo', 'verde'], ERROR: ['Error al renderizar', 'rojo'] };

export default function ReelDetalle() {
  const reelId = +useParams().id!;
  const { esEditor } = useApp(); const ir = useNavigate();
  const [lista, setLista] = useState<any[] | null>(null);   // orden en edición (sin guardar)
  const [i, setI] = useState(0); const [error, setError] = useState(''); const [copiado, setCopiado] = useState(false);
  const [agregar, setAgregar] = useState(false);

  const { datos, error: errCarga, recargar } = useCarga(async () => {
    const [[reel], clips, obs] = await exec('reel.obtener', { reelId });
    return { reel, clips, obs };
  }, [reelId]);
  const otras = useCarga(async () => datos ? (await exec('jugador.obtener', { jugadorId: datos.reel.jugadorId, temporadaId: datos.reel.temporadaId }))[2] : [], [datos?.reel.jugadorId]);
  useEffect(() => { if (datos?.reel.estado !== 'EN_COLA') return; const t = setTimeout(recargar, 3000); return () => clearTimeout(t); }, [datos, recargar]);

  if (errCarga) return <div className="centro">{errCarga}</div>;
  if (!datos) return <div className="centro">Cargando…</div>;
  const { reel } = datos; const clips = lista ?? datos.clips;
  const total = clips.reduce((s, c) => s + (c.segundoFin - c.segundoInicio), 0);
  const enlace = reel.tokenPublico ? `${location.origin}/r/${reel.tokenPublico}` : '';
  const [txt, color] = ESTADO[reel.estado];

  const mover = (k: number, d: number) => { const a = [...clips]; const [x] = a.splice(k, 1); a.splice(k + d, 0, x); setLista(a); };
  const hacer = (p: Promise<any>) => { setError(''); return p.then(() => { setLista(null); recargar(); }).catch(e => setError(e.message)); };
  const guardar = () => hacer(exec('reel.ordenar', { reelId, clipsJson: clips.map(c => c.clipId) }));
  const disponibles = (otras.datos ?? []).filter(c => c.medioListo && !clips.some(x => x.clipId === c.clipId));

  return (
    <div className="col">
      <div className="fila entre">
        <div><h1>{reel.titulo}</h1>
          <div className="tenue"><Link to={`/jugadores/${reel.jugadorId}`} style={{ textDecoration: 'underline' }}>{reel.jugador}</Link> · {reel.posicion} · {clips.length} jugadas · {seg(total)} de jugadas
            {' '}<span className={'etq ' + color}>{txt}</span></div></div>
        {esEditor && <div className="fila">
          {lista ? <><button className="btn sec" onClick={() => setLista(null)}>Descartar cambios</button><button className="btn" onClick={guardar}>Guardar orden</button></> : <>
            {reel.estado !== 'EN_COLA' && reel.estado !== 'LISTO' && <button className="btn" onClick={() => hacer(exec('reel.renderizar', { reelId }))}>Renderizar video</button>}
            {reel.estado === 'LISTO' && !reel.tokenPublico && <button className="btn" onClick={() => hacer(exec('reel.publicar', { reelId, publicar: true }))}>Crear enlace para visores</button>}
            {reel.tokenPublico && <button className="btn sec" onClick={() => hacer(exec('reel.publicar', { reelId, publicar: false }))}>Revocar enlace</button>}
            <button className="btn peligro" onClick={() => confirm('¿Eliminar este reel?') && exec('reel.eliminar', { reelId }).then(() => ir(`/jugadores/${reel.jugadorId}`))}>Eliminar</button></>}
        </div>}
      </div>
      {error && <div className="aviso error">{error}</div>}
      {reel.estado === 'ERROR' && <div className="aviso error">{reel.errorProceso}</div>}
      {enlace && reel.estado === 'LISTO' && <div className="aviso OK fila"><span className="crece">Enlace para visores (no requiere cuenta): <b>{enlace}</b></span>
        <button className="btn sec mini" onClick={() => navigator.clipboard.writeText(enlace).then(() => setCopiado(true))}>{copiado ? 'Copiado' : 'Copiar'}</button></div>}
      {reel.tokenPublico && reel.estado !== 'LISTO' && <div className="aviso MEDIA">El reel cambió después de compartirse: el enlace deja de funcionar hasta que lo renderices de nuevo.</div>}

      <div className="dos">
        <div className="col">
          {reel.estado === 'LISTO' && !lista
            ? <div className="reproductor"><video src={urlReel(reelId)} controls playsInline /></div>
            : clips[i] ? <><ClipPlayer clip={clips[i]} alTerminar={() => i < clips.length - 1 && setI(i + 1)} auto={false} />
                <div className="tenue chico">Vista previa jugada {i + 1} de {clips.length}. El video final incluye la tarjeta con los datos del jugador y el recuadro que lo señala.</div></>
              : <div className="centro" style={{ minHeight: 200 }}>El reel no tiene jugadas.</div>}
          <div><h3>Observaciones</h3><Observaciones lista={datos.obs} /></div>
        </div>
        <div className="col">
          <div className="fila entre"><h3>Orden de las jugadas</h3>
            {esEditor && reel.estado !== 'EN_COLA' && <button className="btn sec mini" onClick={() => setAgregar(!agregar)}>{agregar ? 'Cerrar' : '+ Agregar jugada'}</button>}</div>
          {agregar && <div className="lista tarjeta" style={{ maxHeight: 260, overflow: 'auto' }}>
            {disponibles.length === 0 && <span className="tenue">No hay más jugadas disponibles de este jugador.</span>}
            {disponibles.map(c => <div key={c.clipId} className="item clic" onClick={() => setLista([...clips, { ...c, motivo: 'Agregada a mano' }])}>
              <div className="crece"><b>{c.tipoEvento}</b><div className="chico tenue">{c.rival ? `vs ${c.rival}` : ''} · {seg(c.segundoFin - c.segundoInicio)}</div></div><div className="puntaje">{c.puntaje}</div></div>)}
          </div>}
          <div className="lista">
            {clips.map((c, k) => (
              <div key={c.clipId} className={'item' + (k === i && (reel.estado !== 'LISTO' || lista) ? ' sel' : '')}>
                <div className="puesto">{k + 1}</div>
                <div className="crece" style={{ cursor: 'pointer' }} onClick={() => setI(k)}>
                  <b>{c.tipoEvento}</b> <Estrellas n={c.calidad} /> {c.marcaX == null && <span className="etq ambar" title="Sin recuadro de identificación">sin señalar</span>}
                  <div className="chico tenue">{c.motivo} · {seg(c.segundoFin - c.segundoInicio)}</div></div>
                <div className="puntaje">{c.puntaje}</div>
                {esEditor && reel.estado !== 'EN_COLA' && <div className="fila" style={{ gap: 3, flexWrap: 'nowrap' }}>
                  <button className="btn sec mini" disabled={k === 0} onClick={() => mover(k, -1)} aria-label="Subir">↑</button>
                  <button className="btn sec mini" disabled={k === clips.length - 1} onClick={() => mover(k, 1)} aria-label="Bajar">↓</button>
                  <button className="btn peligro mini" onClick={() => setLista(clips.filter((_, x) => x !== k))} aria-label="Quitar">✕</button></div>}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
