import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { exec, fecha } from '../api';
import { useApp } from '../contexto';
import ClipPlayer from '../componentes/ClipPlayer';
import { Componentes, Estrellas, useCarga } from '../componentes/comunes';

export default function Highlights() {
  const { temporadaId } = useApp();
  const [modo, setModo] = useState<'GENERAL' | 'RECLUTAMIENTO'>('GENERAL');
  const [jugadorId, setJugadorId] = useState<number | null>(null);
  const [categoria, setCategoria] = useState('');
  const [sel, setSel] = useState<number | null>(null);
  const [continuo, setContinuo] = useState(false);

  const plantel = useCarga(async () => (await exec('jugador.listar'))[0], []);
  const { datos, error, recargar } = useCarga(async () =>
    (await exec('highlight.top', { temporadaId, modo, jugadorId, categoria: categoria || null, top: 50 }))[0], [temporadaId, modo, jugadorId, categoria]);
  useEffect(() => { if (datos && !datos.some(c => c.clipId === sel)) setSel(datos[0]?.clipId ?? null); }, [datos]); // eslint-disable-line

  const actual = datos?.find(c => c.clipId === sel);
  const siguiente = () => { if (!continuo || !datos) return; const i = datos.findIndex(c => c.clipId === sel); if (datos[i + 1]) setSel(datos[i + 1].clipId); };

  return (
    <div className="col">
      <div className="fila entre">
        <div><h1>Mejores highlights</h1>
          <div className="tenue">{modo === 'GENERAL'
            ? 'Ranking general: valor técnico de la jugada, reacción de los usuarios y pico de audio.'
            : 'Ranking de reclutamiento: lo que pesa para un visor — relevancia para la posición, calidad, nivel del rival y contexto.'}</div></div>
        <div className="fila">
          <div className="pestanas" style={{ margin: 0, border: 0 }}>
            <button className={modo === 'GENERAL' ? 'activa' : ''} onClick={() => setModo('GENERAL')}>General</button>
            <button className={modo === 'RECLUTAMIENTO' ? 'activa' : ''} onClick={() => setModo('RECLUTAMIENTO')}>Reclutamiento</button>
          </div>
          <select value={jugadorId ?? ''} onChange={e => setJugadorId(e.target.value ? +e.target.value : null)}>
            <option value="">Todos los jugadores</option>
            {plantel.datos?.map(j => <option key={j.jugadorId} value={j.jugadorId}>{j.nombre} {j.apellidos}</option>)}
          </select>
          <select value={categoria} onChange={e => setCategoria(e.target.value)}>
            <option value="">Todas las jugadas</option><option value="ATAQUE">Ataque</option><option value="CREACION">Creación</option>
            <option value="DEFENSA">Defensa</option><option value="PORTERIA">Portería</option>
          </select>
        </div>
      </div>
      {error && <div className="aviso error">{error}</div>}
      {datos && datos.length === 0 && <div className="centro" style={{ minHeight: 240 }}>Aún no hay jugadas marcadas con estos filtros. Se marcan desde cada video.</div>}
      {actual && (
        <div className="dos">
          <div>
            <ClipPlayer clip={actual} alTerminar={siguiente} />
            <div className="tarjeta" style={{ marginTop: 10 }}>
              <div className="fila entre">
                <div><h2 style={{ margin: 0 }}>#{actual.posicion} · {actual.tipoEvento}</h2>
                  <Link to={`/jugadores/${actual.jugadorId}`} style={{ textDecoration: 'underline' }}>{actual.jugador}</Link>
                  <span className="tenue">{actual.rival && ` · vs ${actual.rival}`}{actual.fechaPartido && ` · ${fecha(actual.fechaPartido)}`}{actual.minuto && ` · min ${actual.minuto}`}</span></div>
                <div className="fila">
                  <button className="btn sec" onClick={() => exec('clip.meGusta', { clipId: actual.clipId }).then(recargar)}>{actual.miMeGusta ? '♥' : '♡'} {actual.meGusta}</button>
                  <Link className="btn sec" to={`/medio/${actual.medioId}`}>Ver en el partido</Link>
                </div>
              </div>
              <div className="fila" style={{ marginTop: 10, gap: 18 }}>
                <span>Técnico <b>{actual.tecnico}</b></span><span>Interacción <b>{actual.interaccion}</b></span><span>Audio <b>{actual.audio}</b></span>
                <Estrellas n={actual.calidad} />
                {actual.esDecisiva && <span className="etq verde">decisiva</span>}{actual.esPieDebil && <span className="etq azul">pie no dominante</span>}
                {actual.nivelRival >= 4 && <span className="etq ambar">rival nivel {actual.nivelRival}</span>}
              </div>
              {actual.nota && <div className="tenue" style={{ marginTop: 8 }}>{actual.nota}</div>}
            </div>
          </div>
          <div className="col">
            <label className="check"><input type="checkbox" checked={continuo} onChange={e => setContinuo(e.target.checked)} />Reproducir en cadena</label>
            <div className="lista" style={{ maxHeight: '72vh', overflow: 'auto' }}>
              {datos!.map(c => (
                <div key={c.clipId} className={'item clic' + (c.clipId === sel ? ' sel' : '')} onClick={() => setSel(c.clipId)}>
                  <div className="puesto">{c.posicion}</div>
                  <div className="crece"><b>{c.tipoEvento}</b> · {c.jugador}
                    <div className="chico tenue">{c.rival ? `vs ${c.rival}` : 'Sin partido'}{c.minuto && ` · min ${c.minuto}`} · ♥ {c.meGusta} · {c.vistas} vistas</div>
                    <Componentes c={c} /></div>
                  <div className="puntaje">{c.puntaje}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
