import { useEffect, useRef, useState } from 'react';
import { exec, urlMedio } from '../api';

/** Reproduce solo el tramo [inicio, fin] de un video y señala al jugador en los primeros segundos. */
export default function ClipPlayer({ clip, alTerminar, auto = true }: { clip: any; alTerminar?: () => void; auto?: boolean }) {
  const ref = useRef<HTMLVideoElement>(null);
  const [marca, setMarca] = useState(false);
  const [fin, setFin] = useState(false);
  const contada = useRef(false);
  // el contenedor toma la proporción real del video para que la marca (en % del cuadro) caiga donde debe
  const [prop, setProp] = useState<string>();

  useEffect(() => {
    const v = ref.current; if (!v) return;
    contada.current = false; setFin(false);
    const listo = () => { v.currentTime = clip.segundoInicio; if (auto) v.play().catch(() => {}); };
    if (v.readyState >= 1) listo(); else v.addEventListener('loadedmetadata', listo, { once: true });
    return () => v.removeEventListener('loadedmetadata', listo);
  }, [clip.clipId, clip.medioId, clip.segundoInicio, auto]);

  const tiempo = () => {
    const v = ref.current!; const t = v.currentTime;
    const ms = clip.marcaSegundo ?? clip.segundoInicio;
    setMarca(clip.marcaX != null && t >= ms - 0.3 && t < ms + 2);
    if (!contada.current && t - clip.segundoInicio > 2) {      // cuenta como vista al pasar de 2 s
      contada.current = true; exec('clip.interaccion', { clipId: clip.clipId, tipo: 'VISTA' }).catch(() => {});
    }
    if (t >= clip.segundoFin && !v.paused) { v.pause(); setFin(true); alTerminar?.(); }
  };
  const repetir = () => {
    const v = ref.current!; v.currentTime = clip.segundoInicio; setFin(false); v.play().catch(() => {});
    exec('clip.interaccion', { clipId: clip.clipId, tipo: 'REPETICION' }).catch(() => {});
  };

  return (
    <div>
      <div className="reproductor" style={prop ? { aspectRatio: prop } : undefined}>
        <video ref={ref} src={urlMedio(clip.medioId)} controls playsInline onTimeUpdate={tiempo}
          onLoadedMetadata={e => e.currentTarget.videoWidth && setProp(`${e.currentTarget.videoWidth}/${e.currentTarget.videoHeight}`)} />
        {marca && <div className="marca-jugador" style={{ left: `${clip.marcaX}%`, top: `${clip.marcaY}%`, height: `${clip.marcaTamano ?? 12}%` }} />}
      </div>
      <div className="fila" style={{ marginTop: 8 }}>
        <button className="btn sec mini" onClick={repetir}>↺ Repetir{fin ? ' jugada' : ''}</button>
      </div>
    </div>
  );
}
