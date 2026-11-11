import { useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { exec, fecha, subirArchivo } from '../api';
import { useApp } from '../contexto';
import { useCarga } from '../componentes/comunes';

type Item = { archivo: File; titulo: string; estado: 'espera' | 'subiendo' | 'listo' | 'error'; avance: number; error?: string; medioId?: number };
const esVideo = (f: File) => f.type.startsWith('video/') || /\.(mp4|mov|m4v|mkv|webm|avi)$/i.test(f.name);

export default function Subir() {
  const { temporadaId, cat, esEditor } = useApp();
  const [items, setItems] = useState<Item[]>([]);
  const [partidoId, setPartidoId] = useState<number | null>(null);
  const [jugadores, setJugadores] = useState<number[]>([]);
  const [ocupado, setOcupado] = useState(false);
  const entrada = useRef<HTMLInputElement>(null);
  const { datos } = useCarga(async () => {
    const [[partidos], [plantel]] = await Promise.all([exec('partido.listar', { temporadaId }), exec('jugador.listar')]);
    return { partidos, plantel };
  }, [temporadaId]);

  if (!esEditor) return <div className="centro">Solo editores y administradores pueden subir archivos.</div>;
  const temporada = cat.temporadas.find(t => t.temporadaId === temporadaId);

  const agregar = (lista: FileList | null) => {
    if (!lista) return;
    setItems(a => [...a, ...Array.from(lista).map(f => ({ archivo: f, titulo: f.name.replace(/\.[^.]+$/, '').replace(/[_-]+/g, ' '), estado: 'espera' as const, avance: 0 }))]);
  };
  const cambia = (i: number, c: Partial<Item>) => setItems(a => a.map((x, k) => k === i ? { ...x, ...c } : x));

  const subir = async () => {
    setOcupado(true);
    for (let i = 0; i < items.length; i++) {
      const it = items[i]; if (it.estado === 'listo') continue;
      cambia(i, { estado: 'subiendo', avance: 0, error: undefined });
      try {
        let medioId = it.medioId;
        if (!medioId) {
          const [[r]] = await exec('medio.crear', {
            tipo: esVideo(it.archivo) ? 'VIDEO' : 'FOTO', titulo: it.titulo, temporadaId, partidoId,
            nombreOriginal: it.archivo.name, tipoMime: it.archivo.type || null, tamanoBytes: it.archivo.size,
            jugadoresJson: jugadores.length ? jugadores : null,
          });
          medioId = r.medioId; cambia(i, { medioId });
        }
        await subirArchivo(medioId!, it.archivo, f => cambia(i, { avance: f }));
        cambia(i, { estado: 'listo', avance: 1 });
      } catch (e: any) { cambia(i, { estado: 'error', error: e.message }); }
    }
    setOcupado(false);
  };

  return (
    <div className="col" style={{ maxWidth: 860, margin: '0 auto' }}>
      <h1>Subir videos y fotos</h1>
      {!temporada ? <div className="aviso error">No hay temporada seleccionada. Crea una en Administración.</div> : (
        <>
          <div className="tarjeta form">
            <label>Temporada<input value={temporada.nombre} disabled /></label>
            <label>Partido (opcional)
              <select value={partidoId ?? ''} onChange={e => setPartidoId(e.target.value ? +e.target.value : null)}>
                <option value="">Sin partido (entrenamiento, evento…)</option>
                {datos?.partidos.map(p => <option key={p.partidoId} value={p.partidoId}>{fecha(p.fecha)} · {p.local} vs {p.visita}</option>)}
              </select>
            </label>
            <label className="ancho">Jugadores que aparecen (opcional; útil para fotos)
              <select multiple size={4} value={jugadores.map(String)} onChange={e => setJugadores(Array.from(e.target.selectedOptions).map(o => +o.value))}>
                {datos?.plantel.map(j => <option key={j.jugadorId} value={j.jugadorId}>{j.nombre} {j.apellidos} · {j.posicionClave}</option>)}
              </select>
            </label>
          </div>
          <div className="zona" onClick={() => entrada.current?.click()} onDragOver={e => e.preventDefault()}
               onDrop={e => { e.preventDefault(); agregar(e.dataTransfer.files); }}>
            Arrastra aquí los archivos o haz clic para elegirlos<br />
            <span className="chico">Videos: mp4, mov, m4v, mkv, webm, avi · Fotos: jpg, png, webp</span>
            <input ref={entrada} type="file" multiple hidden accept="video/*,image/jpeg,image/png,image/webp,.mkv,.avi"
                   onChange={e => { agregar(e.target.files); e.target.value = ''; }} />
          </div>
          <div className="lista">
            {items.map((it, i) => (
              <div key={i} className="item">
                <span className={'etq ' + (esVideo(it.archivo) ? 'azul' : 'verde')}>{esVideo(it.archivo) ? 'Video' : 'Foto'}</span>
                <div className="crece">
                  <input style={{ width: '100%' }} value={it.titulo} disabled={it.estado !== 'espera' && it.estado !== 'error' || !!it.medioId}
                         onChange={e => cambia(i, { titulo: e.target.value })} aria-label="Título" />
                  <div className="chico tenue" style={{ marginTop: 3 }}>
                    {(it.archivo.size / 1048576).toFixed(1)} MB
                    {it.estado === 'listo' && <> · <span style={{ color: 'var(--verde)' }}>Subido; se está procesando</span>{esVideo(it.archivo) && <> · <Link to={`/medio/${it.medioId}`} style={{ textDecoration: 'underline' }}>abrir</Link></>}</>}
                    {it.estado === 'error' && <span style={{ color: 'var(--rojo)' }}> · {it.error}</span>}
                  </div>
                  {it.estado === 'subiendo' && <div className="progreso" style={{ marginTop: 5 }}><i style={{ width: `${it.avance * 100}%` }} /></div>}
                </div>
                {it.estado !== 'subiendo' && it.estado !== 'listo' && <button className="btn sec mini" onClick={() => setItems(a => a.filter((_, k) => k !== i))}>Quitar</button>}
              </div>
            ))}
          </div>
          {items.some(i => i.estado === 'espera' || i.estado === 'error') && (
            <button className="btn" disabled={ocupado} onClick={subir}>{ocupado ? 'Subiendo…' : items.some(i => i.estado === 'error') ? 'Reintentar' : `Subir ${items.filter(i => i.estado === 'espera').length} archivo(s)`}</button>
          )}
        </>
      )}
    </div>
  );
}
