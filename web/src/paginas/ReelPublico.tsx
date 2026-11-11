import { useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { exec, fecha, PIES, seg, urlMedio, urlReel } from '../api';
import { useCarga } from '../componentes/comunes';

/** Lo que abre un visor con su enlace: perfil del jugador y el video. Sin sesión.
 *  De un menor solo se muestra el año de nacimiento y el contacto del club. */
export default function ReelPublico() {
  const token = useParams().token!;
  const { datos, error } = useCarga(async () => { const [[reel], clips] = await exec('reel.publico', { token }); return { reel, clips }; }, [token]);
  useEffect(() => {   // que los buscadores no indexen la página
    const m = document.createElement('meta'); m.name = 'robots'; m.content = 'noindex, nofollow';
    document.head.appendChild(m); return () => { m.remove(); };
  }, []);
  if (error) return <div className="centro">{error}</div>;
  if (!datos) return <div className="centro"><div className="girando" aria-label="Cargando" /></div>;
  const r = datos.reel;
  let acumulado = 4; // la tarjeta inicial dura 4 s
  return (
    <div className="publico col">
      <div className="tarjeta fila" style={{ alignItems: 'flex-start' }}>
        <div className="avatar" style={r.fotoMedioId ? { backgroundImage: `url(${urlMedio(r.fotoMedioId, 'mini', token)})` } : undefined}>{!r.fotoMedioId && r.jugador[0]}</div>
        <div className="crece">
          <h1>{r.jugador} {r.dorsal && <span className="tenue">#{r.dorsal}</span>}</h1>
          <div>{r.posicion}{r.posicionSecundaria && ` / ${r.posicionSecundaria}`}{r.equipo && ` · ${r.equipo}`}</div>
          <div className="tenue">{[r.anioNacimiento && `Categoría ${r.anioNacimiento}`, r.estaturaCm && `${(r.estaturaCm / 100).toFixed(2)} m`, r.pesoKg && `${r.pesoKg} kg`,
            `Pie ${PIES[r.pieDominante].toLowerCase()}`, r.anioGraduacion && `Class of ${r.anioGraduacion}`, r.promedioAcademico && `Promedio ${r.promedioAcademico}`].filter(Boolean).join(' · ')}</div>
          {r.bio && <p style={{ margin: '8px 0 0' }}>{r.bio}</p>}
        </div>
      </div>
      <div className="reproductor"><video src={urlReel(r.reelId, token)} controls playsInline controlsList="nodownload" onContextMenu={e => e.preventDefault()} /></div>
      <div className="tarjeta">
        <h3>Contacto</h3>
        {r.contactoCorreo || r.contactoTelefono ? (
          <div className="fila">
            <div className="crece"><b>{r.contactoNombre ?? r.equipo}</b>{r.contactoCargo && <span className="tenue"> · {r.contactoCargo}</span>}
              <div className="tenue chico">El club atiende las solicitudes sobre este jugador.</div></div>
            {r.contactoCorreo && <a className="btn" href={`mailto:${r.contactoCorreo}`}>{r.contactoCorreo}</a>}
            {r.contactoTelefono && <a className="btn sec" href={`tel:${r.contactoTelefono.replace(/\s/g, '')}`}>{r.contactoTelefono}</a>}
          </div>
        ) : !(r.correoPersonal || r.telefonoPersonal) && <span className="tenue">Solicita el contacto a quien te compartió este enlace.</span>}
        {(r.correoPersonal || r.telefonoPersonal) && (
          <div className="fila" style={{ marginTop: 10 }}>
            <div className="crece"><b>Contacto directo</b><div className="tenue chico">Compartido con autorización.</div></div>
            {r.correoPersonal && <a className="btn sec" href={`mailto:${r.correoPersonal}`}>{r.correoPersonal}</a>}
            {r.telefonoPersonal && <a className="btn sec" href={`tel:${r.telefonoPersonal.replace(/\s/g, '')}`}>{r.telefonoPersonal}</a>}
          </div>
        )}
      </div>
      <div>
        <h3>Contenido · {seg(r.duracionSeg)}</h3>
        <table><tbody>{datos.clips.map(c => {
          const inicio = acumulado; acumulado += (c.segundoFin - c.segundoInicio) + (c.marcaX != null ? 1.5 : 0);
          return <tr key={c.orden}><td className="tenue">{seg(inicio)}</td><td><b>{c.tipoEvento}</b></td>
            <td className="tenue">{c.rival ? `vs ${c.rival}` : ''}{c.minuto ? ` · min ${c.minuto}` : ''}</td>
            <td>{c.esDecisiva && <span className="etq verde">decisiva</span>} {c.esPieDebil && <span className="etq azul">pie no dominante</span>}</td></tr>;
        })}</tbody></table>
      </div>
      {r.expiraEn && <p className="tenue chico">Enlace personal, disponible hasta el {fecha(r.expiraEn)}. Material de un jugador en formación: no lo redistribuyas.</p>}
    </div>
  );
}
