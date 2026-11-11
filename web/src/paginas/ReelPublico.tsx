import { useParams } from 'react-router-dom';
import { exec, PIES, seg, urlMedio, urlReel } from '../api';
import { useCarga } from '../componentes/comunes';

/** Lo que abre un visor con el enlace: perfil del jugador y el video. Sin sesión. */
export default function ReelPublico() {
  const token = useParams().token!;
  const { datos, error } = useCarga(async () => { const [[reel], clips] = await exec('reel.publico', { token }); return { reel, clips }; }, [token]);
  if (error) return <div className="centro">{error}</div>;
  if (!datos) return <div className="centro">Cargando…</div>;
  const r = datos.reel;
  const edad = r.fechaNacimiento ? Math.floor((Date.now() - new Date(r.fechaNacimiento).getTime()) / 31557600000) : null;
  let acumulado = 4; // la tarjeta inicial dura 4 s
  return (
    <div className="publico col">
      <div className="tarjeta fila" style={{ alignItems: 'flex-start' }}>
        <div className="avatar" style={r.fotoMedioId ? { backgroundImage: `url(${urlMedio(r.fotoMedioId, 'mini', token)})` } : undefined}>{!r.fotoMedioId && r.jugador[0]}</div>
        <div className="crece">
          <h1>{r.jugador} {r.dorsal && <span className="tenue">#{r.dorsal}</span>}</h1>
          <div>{r.posicion}{r.posicionSecundaria && ` / ${r.posicionSecundaria}`}{r.equipo && ` · ${r.equipo}`}</div>
          <div className="tenue">{[edad && `${edad} años`, r.estaturaCm && `${(r.estaturaCm / 100).toFixed(2)} m`, r.pesoKg && `${r.pesoKg} kg`, `Pie ${PIES[r.pieDominante].toLowerCase()}`,
            r.anioGraduacion && `Generación ${r.anioGraduacion}`, r.promedioAcademico && `Promedio ${r.promedioAcademico}`].filter(Boolean).join(' · ')}</div>
          {r.bio && <p style={{ margin: '8px 0 0' }}>{r.bio}</p>}
          <div style={{ marginTop: 8 }}>
            {r.correoContacto && <a className="btn" href={`mailto:${r.correoContacto}`}>{r.correoContacto}</a>}{' '}
            {r.telefonoContacto && <a className="btn sec" href={`tel:${r.telefonoContacto.replace(/\s/g, '')}`}>{r.telefonoContacto}</a>}
          </div>
        </div>
      </div>
      <div className="reproductor"><video src={urlReel(r.reelId, token)} controls playsInline /></div>
      <div>
        <h3>Contenido · {seg(r.duracionSeg)}</h3>
        <table><tbody>{datos.clips.map(c => {
          const inicio = acumulado; acumulado += (c.segundoFin - c.segundoInicio) + (c.marcaX != null ? 1.5 : 0);
          return <tr key={c.orden}><td className="tenue">{seg(inicio)}</td><td><b>{c.tipoEvento}</b></td>
            <td className="tenue">{c.rival ? `vs ${c.rival}` : ''}{c.minuto ? ` · min ${c.minuto}` : ''}</td>
            <td>{c.esDecisiva && <span className="etq verde">decisiva</span>} {c.esPieDebil && <span className="etq azul">pie no dominante</span>}</td></tr>;
        })}</tbody></table>
      </div>
    </div>
  );
}
