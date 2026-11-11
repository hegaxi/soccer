import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { exec, fecha, seg, urlMedio } from '../api';
import { useApp } from '../contexto';
import { Modal, useCarga } from '../componentes/comunes';

export default function Galeria() {
  const { temporadaId, esEditor } = useApp();
  const [tipo, setTipo] = useState<'VIDEO' | 'FOTO'>('VIDEO');
  const [partidoId, setPartidoId] = useState<number | null>(null);
  const [jugadorId, setJugadorId] = useState<number | null>(null);
  const [busqueda, setBusqueda] = useState(''); const [pagina, setPagina] = useState(1);
  const [foto, setFoto] = useState<any>(null);

  const filtros = useCarga(async () => {
    const [[partidos], [jugadores]] = await Promise.all([exec('partido.listar', { temporadaId }), exec('jugador.listar')]);
    return { partidos, jugadores };
  }, [temporadaId]);
  useEffect(() => { setPagina(1); setPartidoId(null); }, [temporadaId]);
  useEffect(() => { setPagina(1); }, [tipo, partidoId, jugadorId, busqueda]);

  const { datos, error, recargar } = useCarga(async () => {
    if (!temporadaId) return { items: [], total: 0, tamano: 24 };
    const [items, [t]] = await exec('medio.listar', { temporadaId, tipo, partidoId, jugadorId, busqueda: busqueda || null, pagina });
    return { items, total: t.total, tamano: t.tamano };
  }, [temporadaId, tipo, partidoId, jugadorId, busqueda, pagina]);

  // mientras haya medios procesándose, refresca
  useEffect(() => {
    if (!datos?.items.some(m => m.estado === 'SUBIDO' || m.estado === 'PROCESANDO')) return;
    const t = setTimeout(recargar, 3000); return () => clearTimeout(t);
  }, [datos, recargar]);

  const paginas = datos ? Math.max(1, Math.ceil(datos.total / datos.tamano)) : 1;
  return (
    <div className="col">
      <div className="fila entre">
        <h1>Galería de la temporada</h1>
        {esEditor && <Link className="btn" to="/subir">+ Subir videos o fotos</Link>}
      </div>
      <div className="fila">
        <div className="pestanas" style={{ margin: 0, border: 0 }}>
          <button className={tipo === 'VIDEO' ? 'activa' : ''} onClick={() => setTipo('VIDEO')}>Videos</button>
          <button className={tipo === 'FOTO' ? 'activa' : ''} onClick={() => setTipo('FOTO')}>Fotos</button>
        </div>
        <select value={partidoId ?? ''} onChange={e => setPartidoId(e.target.value ? +e.target.value : null)}>
          <option value="">Todos los partidos</option>
          {filtros.datos?.partidos.map(p => <option key={p.partidoId} value={p.partidoId}>{fecha(p.fecha)} · {p.local} vs {p.visita}</option>)}
        </select>
        <select value={jugadorId ?? ''} onChange={e => setJugadorId(e.target.value ? +e.target.value : null)}>
          <option value="">Todos los jugadores</option>
          {filtros.datos?.jugadores.map(j => <option key={j.jugadorId} value={j.jugadorId}>{j.nombre} {j.apellidos}</option>)}
        </select>
        <input placeholder="Buscar…" value={busqueda} onChange={e => setBusqueda(e.target.value)} />
      </div>
      {error && <div className="aviso error">{error}</div>}
      {datos && datos.items.length === 0 && (
        <div className="centro" style={{ minHeight: 240 }}>
          {temporadaId ? `Aún no hay ${tipo === 'VIDEO' ? 'videos' : 'fotos'} con estos filtros.` : 'Crea una temporada en Administración para empezar.'}
        </div>
      )}
      <div className="rejilla">
        {datos?.items.map(m => {
          const cuerpo = (
            <>
              <div className="mini" style={m.tieneMiniatura ? { backgroundImage: `url(${urlMedio(m.medioId, 'mini')})` } : undefined}>
                {!m.tieneMiniatura && (m.estado === 'ERROR' ? 'No se pudo procesar' : 'Procesando…')}
                {m.tipo === 'VIDEO' && m.duracionSeg != null && <span className="dur">{seg(m.duracionSeg)}</span>}
                {m.estado !== 'LISTO' && <span className={'etq tipo ' + (m.estado === 'ERROR' ? 'rojo' : 'ambar')}>{m.estado === 'ERROR' ? 'Error' : 'Procesando'}</span>}
              </div>
              <div className="pie">
                <div className="titulo" title={m.titulo}>{m.titulo}</div>
                <div className="tenue chico">{m.partido ?? fecha(m.creadoEn)}{m.fechaPartido && ` · ${fecha(m.fechaPartido)}`}</div>
                <div className="fila" style={{ gap: 5, marginTop: 5 }}>
                  {m.clips > 0 && <span className="etq verde">{m.clips} jugadas</span>}
                  {esEditor && m.candidatos > 0 && <span className="etq ambar">{m.candidatos} por revisar</span>}
                  {m.jugadores?.slice(0, 2).map((j: any) => <span key={j.id} className="etq">{j.nombre}</span>)}
                  {m.jugadores?.length > 2 && <span className="etq">+{m.jugadores.length - 2}</span>}
                </div>
              </div>
            </>
          );
          return m.tipo === 'VIDEO'
            ? <Link key={m.medioId} className="medio" to={`/medio/${m.medioId}`}>{cuerpo}</Link>
            : <div key={m.medioId} className="medio" onClick={() => setFoto(m)}>{cuerpo}</div>;
        })}
      </div>
      {paginas > 1 && (
        <div className="fila" style={{ justifyContent: 'center' }}>
          <button className="btn sec" disabled={pagina <= 1} onClick={() => setPagina(pagina - 1)}>← Anterior</button>
          <span className="tenue">Página {pagina} de {paginas}</span>
          <button className="btn sec" disabled={pagina >= paginas} onClick={() => setPagina(pagina + 1)}>Siguiente →</button>
        </div>
      )}
      {foto && <VisorFoto foto={foto} jugadores={filtros.datos?.jugadores ?? []} cerrar={() => setFoto(null)} cambio={recargar} />}
    </div>
  );
}

function VisorFoto({ foto, jugadores, cerrar, cambio }: { foto: any; jugadores: any[]; cerrar: () => void; cambio: () => void }) {
  const { esEditor } = useApp();
  const [ids, setIds] = useState<number[]>((foto.jugadores ?? []).map((j: any) => j.id));
  const [msg, setMsg] = useState('');
  const hacer = (p: Promise<any>, ok: string, cierra = false) =>
    p.then(() => { setMsg(ok); cambio(); if (cierra) cerrar(); }).catch(e => setMsg(e.message));
  const guardar = (nuevos: number[]) => {
    setIds(nuevos);
    hacer(exec('medio.actualizar', { medioId: foto.medioId, titulo: foto.titulo, descripcion: foto.descripcion, partidoId: foto.partidoId, jugadoresJson: nuevos }), 'Etiquetas guardadas');
  };
  const perfil = async (jugadorId: number) => {
    const [[j]] = await exec('jugador.obtener', { jugadorId });
    const { posicion, posicionSecundaria, equipo, ...datos } = j;
    await exec('jugador.guardar', { ...datos, fotoMedioId: foto.medioId });
  };
  return (
    <Modal titulo={foto.titulo} cerrar={cerrar} grande>
      {foto.estado === 'LISTO'
        ? <img src={urlMedio(foto.medioId, 'web')} alt={foto.titulo} style={{ width: '100%', maxHeight: '64vh', objectFit: 'contain', borderRadius: 8, background: '#000' }} />
        : <div className="centro" style={{ minHeight: 200 }}>La foto aún se está procesando.</div>}
      <div className="col" style={{ marginTop: 12 }}>
        {foto.descripcion && <div>{foto.descripcion}</div>}
        <div className="fila">
          <span className="tenue">Aparecen:</span>
          {ids.length === 0 && <span className="tenue">nadie etiquetado</span>}
          {ids.map(id => {
            const j = jugadores.find(x => x.jugadorId === id);
            return <span key={id} className="etq">{j ? `${j.nombre} ${j.apellidos}` : id}
              {esEditor && <> · <a onClick={() => hacer(perfil(id), 'Foto de perfil actualizada')} style={{ cursor: 'pointer', color: 'var(--verde)' }}>usar de perfil</a>
                {' '}<a onClick={() => guardar(ids.filter(x => x !== id))} style={{ cursor: 'pointer' }}>✕</a></>}
            </span>;
          })}
          {esEditor && (
            <select value="" onChange={e => e.target.value && guardar([...ids, +e.target.value])}>
              <option value="">+ Etiquetar jugador</option>
              {jugadores.filter(j => !ids.includes(j.jugadorId)).map(j => <option key={j.jugadorId} value={j.jugadorId}>{j.nombre} {j.apellidos}</option>)}
            </select>
          )}
        </div>
        <div className="fila entre">
          <span className="tenue chico">{msg}</span>
          <div className="fila">
            <a className="btn sec mini" href={urlMedio(foto.medioId, 'orig')} download>Descargar original</a>
            {esEditor && <button className="btn peligro mini" onClick={() => confirm('¿Eliminar esta foto?') && hacer(exec('medio.eliminar', { medioId: foto.medioId }), '', true)}>Eliminar</button>}
          </div>
        </div>
      </div>
    </Modal>
  );
}
