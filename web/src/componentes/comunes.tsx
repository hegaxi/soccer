import { FormEvent, ReactNode, useCallback, useEffect, useState } from 'react';

export function Modal({ titulo, cerrar, children, grande }: { titulo: string; cerrar: () => void; children: ReactNode; grande?: boolean }) {
  useEffect(() => {
    const t = (e: KeyboardEvent) => e.key === 'Escape' && cerrar();
    window.addEventListener('keydown', t); return () => window.removeEventListener('keydown', t);
  }, [cerrar]);
  return (
    <div className="modal-fondo" onMouseDown={e => e.target === e.currentTarget && cerrar()}>
      <div className={'modal' + (grande ? ' grande' : '')} role="dialog" aria-label={titulo}>
        <div className="fila entre" style={{ marginBottom: 12 }}>
          <h2 style={{ margin: 0 }}>{titulo}</h2>
          <button className="btn sec mini" onClick={cerrar} aria-label="Cerrar">✕</button>
        </div>
        {children}
      </div>
    </div>
  );
}

export type Campo = {
  n: string; e: string; t?: 'text' | 'number' | 'date' | 'select' | 'check' | 'area' | 'password' | 'email';
  op?: { v: any; e: string }[]; req?: boolean; ancho?: boolean; paso?: string; ayuda?: string;
};

/** Formulario genérico: los valores se envían tal cual como parámetros de la acción. */
export function Formulario({ campos, inicial, guardar, cancelar, texto = 'Guardar' }: {
  campos: Campo[]; inicial: Record<string, any>; guardar: (v: Record<string, any>) => Promise<void>; cancelar?: () => void; texto?: string;
}) {
  const [v, setV] = useState<Record<string, any>>(inicial);
  const [error, setError] = useState(''); const [ocupado, setOcupado] = useState(false);
  const pon = (n: string, x: any) => setV(a => ({ ...a, [n]: x }));
  const enviar = async (e: FormEvent) => {
    e.preventDefault(); setError(''); setOcupado(true);
    try {
      const limpio: Record<string, any> = {};
      for (const [k, x] of Object.entries(v)) limpio[k] = x === '' ? null : x;
      await guardar(limpio);
    } catch (x: any) { setError(x.message); } finally { setOcupado(false); }
  };
  return (
    <form onSubmit={enviar} className="col">
      <div className="form">
        {campos.map(c => c.t === 'check' ? (
          <label key={c.n} className="check"><input type="checkbox" checked={!!v[c.n]} onChange={e => pon(c.n, e.target.checked)} />{c.e}</label>
        ) : (
          <label key={c.n} className={c.ancho || c.t === 'area' ? 'ancho' : ''}>{c.e}{c.req && ' *'}
            {c.t === 'select' ? (
              <select value={v[c.n] ?? ''} required={c.req} onChange={e => pon(c.n, e.target.value === '' ? null : isNaN(+e.target.value) ? e.target.value : +e.target.value)}>
                <option value="">—</option>
                {c.op!.map(o => <option key={o.v} value={o.v}>{o.e}</option>)}
              </select>
            ) : c.t === 'area' ? (
              <textarea rows={3} value={v[c.n] ?? ''} onChange={e => pon(c.n, e.target.value)} />
            ) : (
              <input type={c.t ?? 'text'} step={c.paso} value={v[c.n] ?? ''} required={c.req}
                onChange={e => pon(c.n, c.t === 'number' ? (e.target.value === '' ? null : +e.target.value) : e.target.value)} />
            )}
            {c.ayuda && <span className="chico">{c.ayuda}</span>}
          </label>
        ))}
      </div>
      {error && <div className="aviso error">{error}</div>}
      <div className="fila" style={{ justifyContent: 'flex-end' }}>
        {cancelar && <button type="button" className="btn sec" onClick={cancelar}>Cancelar</button>}
        <button className="btn" disabled={ocupado}>{ocupado ? 'Guardando…' : texto}</button>
      </div>
    </form>
  );
}

export const Estrellas = ({ n }: { n?: number | null }) =>
  n ? <span className="estrellas" title={`Calidad técnica ${n}/5`}>{'★'.repeat(n)}<span style={{ opacity: .25 }}>{'★'.repeat(5 - n)}</span></span> : null;

/** Barras de los tres componentes del puntaje. */
export const Componentes = ({ c }: { c: any }) => (
  <div className="barras" title={`Técnico ${c.tecnico} · Interacción ${c.interaccion} · Audio ${c.audio}`}>
    <i style={{ width: `${c.tecnico * 0.6}%`, background: 'var(--verde)' }} />
    <i style={{ width: `${c.interaccion * 0.25}%`, background: 'var(--azul)' }} />
    <i style={{ width: `${c.audio * 0.15}%`, background: 'var(--ambar)' }} />
  </div>
);

export const Observaciones = ({ lista }: { lista: any[] }) => (
  <div className="col" style={{ gap: 6 }}>
    {lista.map((o, i) => <div key={i} className={'aviso ' + o.severidad}>{o.mensaje}</div>)}
  </div>
);

/** Carga datos y los recarga cuando cambian las dependencias. */
export function useCarga<T>(fn: () => Promise<T>, deps: any[]) {
  const [datos, setDatos] = useState<T | null>(null);
  const [error, setError] = useState('');
  const recargar = useCallback(() => fn().then(d => { setDatos(d); setError(''); }).catch(e => setError(e.message)), deps); // eslint-disable-line
  useEffect(() => { let vivo = true; fn().then(d => vivo && (setDatos(d), setError(''))).catch(e => vivo && setError(e.message)); return () => { vivo = false; }; }, deps); // eslint-disable-line
  return { datos, error, recargar, setDatos };
}
