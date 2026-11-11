// Toda la comunicación pasa por un solo endpoint: { accion, params } → procedimientos almacenados.
export class ErrorApi extends Error {
  constructor(public estado: number, mensaje: string) { super(mensaje); }
}

export async function exec(accion: string, params?: Record<string, any>): Promise<any[][]> {
  const r = await fetch('/api/exec', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, credentials: 'same-origin',
    body: JSON.stringify({ accion, params }),
  });
  const j = await r.json().catch(() => ({ ok: false, error: 'Respuesta inválida del servidor' }));
  if (!r.ok || !j.ok) {
    if (r.status === 401 && accion !== 'sesion.iniciar') window.dispatchEvent(new Event('sesion-expirada'));
    throw new ErrorApi(r.status, j.error ?? 'Error inesperado');
  }
  return j.resultados;
}

export const urlMedio = (medioId: number, v: 'web' | 'mini' | 'orig' = 'web', k?: string) =>
  `/api/archivo/${medioId}?v=${v}${k ? `&k=${k}` : ''}`;
export const urlReel = (reelId: number, k?: string) => `/api/archivo/reel/${reelId}${k ? `?k=${k}` : ''}`;

const PARTE = 8 * 1024 * 1024;

/** Sube el archivo por partes; si una parte falla por red, reintenta y retoma donde el servidor se quedó. */
export async function subirArchivo(medioId: number, archivo: File, progreso: (fraccion: number) => void) {
  let offset = 0, fallos = 0;
  while (offset < archivo.size) {
    let r: Response;
    try {
      r = await fetch(`/api/archivo/${medioId}?offset=${offset}`, {
        method: 'PUT', credentials: 'same-origin', body: archivo.slice(offset, offset + PARTE),
      });
    } catch (e) {
      if (++fallos > 4) throw new ErrorApi(0, 'Se perdió la conexión durante la subida');
      await new Promise(ok => setTimeout(ok, 1500 * fallos));
      continue;
    }
    const j = await r.json().catch(() => ({}));
    if (r.status === 409 && typeof j.recibido === 'number') { offset = j.recibido; continue; }
    if (!r.ok) throw new ErrorApi(r.status, j.error ?? 'No se pudo subir el archivo');
    fallos = 0; offset = j.recibido;
    progreso(offset / archivo.size);
  }
}

export const seg = (s?: number | null) => {
  if (s == null) return '—';
  const t = Math.max(0, Math.floor(s));
  const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), ss = String(t % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
};
export const fecha = (f?: string | null) =>
  f ? new Date(f.length === 10 ? f + 'T12:00:00' : f).toLocaleDateString('es-MX', { day: 'numeric', month: 'short', year: 'numeric' }) : '';
export const ROLES: Record<number, string> = { 1: 'Espectador', 2: 'Editor / entrenador', 3: 'Administrador' };
export const PIES: Record<string, string> = { D: 'Derecho', I: 'Izquierdo', A: 'Ambidiestro', C: 'Cabeza' };
