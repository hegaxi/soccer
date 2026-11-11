import { createContext, useCallback, useContext, useEffect, useState, ReactNode } from 'react';
import { exec, ErrorApi } from './api';

type Usuario = { usuarioId: number; nombre: string; correo: string; rol: number };
type Catalogos = { temporadas: any[]; posiciones: any[]; tipos: any[]; fases: any[]; equipos: any[] };
type Ctx = {
  usuario: Usuario | null; cargando: boolean; sinRed: boolean; reintentar: () => void; esEditor: boolean; esAdmin: boolean;
  entrar: (correo: string, clave: string) => Promise<void>; salir: () => Promise<void>;
  cat: Catalogos; recargarCat: () => Promise<void>;
  temporadaId: number | null; setTemporadaId: (id: number | null) => void;
};
const vacio: Catalogos = { temporadas: [], posiciones: [], tipos: [], fases: [], equipos: [] };
const C = createContext<Ctx>(null as any);
export const useApp = () => useContext(C);

export function Proveedor({ children }: { children: ReactNode }) {
  const [usuario, setUsuario] = useState<Usuario | null>(null);
  const [cargando, setCargando] = useState(true);
  const [cat, setCat] = useState<Catalogos>(vacio);
  const [temporadaId, setTemporadaId] = useState<number | null>(null);

  const recargarCat = useCallback(async () => {
    const [temporadas, posiciones, tipos, fases, equipos] = await exec('catalogo.inicial');
    setCat({ temporadas, posiciones, tipos, fases, equipos });
    setTemporadaId(a => a ?? (temporadas.find(t => t.activa) ?? temporadas[0])?.temporadaId ?? null);
  }, []);

  // Sin conexión no se sabe si hay sesión: se avisa en vez de mandar al usuario a iniciar sesión otra vez.
  const [sinRed, setSinRed] = useState(false);
  const reintentar = useCallback(() => {
    setCargando(true);
    exec('sesion.actual').then(([[u]]) => { setUsuario(u ?? null); setSinRed(false); })
      .catch(e => setSinRed(!(e instanceof ErrorApi)))
      .finally(() => setCargando(false));
  }, []);
  useEffect(() => {
    reintentar();
    const fuera = () => setUsuario(null);
    window.addEventListener('sesion-expirada', fuera); window.addEventListener('online', reintentar);
    return () => { window.removeEventListener('sesion-expirada', fuera); window.removeEventListener('online', reintentar); };
  }, [reintentar]);
  useEffect(() => { if (usuario) recargarCat().catch(() => {}); else { setCat(vacio); setTemporadaId(null); } }, [usuario, recargarCat]);

  const entrar = async (correo: string, clave: string) => {
    const [[u]] = await exec('sesion.iniciar', { correo, clave });
    setUsuario(u);
  };
  const salir = async () => { await exec('sesion.cerrar').catch(() => {}); setUsuario(null); };

  return (
    <C.Provider value={{
      usuario, cargando, sinRed, reintentar, esEditor: (usuario?.rol ?? 0) >= 2, esAdmin: usuario?.rol === 3,
      entrar, salir, cat, recargarCat, temporadaId, setTemporadaId,
    }}>{children}</C.Provider>
  );
}
