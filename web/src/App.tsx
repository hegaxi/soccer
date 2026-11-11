import { FormEvent, useEffect, useState } from 'react';
import { NavLink, Route, Routes, useLocation } from 'react-router-dom';
import { useApp } from './contexto';
import { ROLES } from './api';
import { Avisos } from './componentes/comunes';
import { Icono, Logo } from './componentes/Iconos';
import Galeria from './paginas/Galeria';
import Subir from './paginas/Subir';
import VideoDetalle from './paginas/VideoDetalle';
import Highlights from './paginas/Highlights';
import { Jugadores, JugadorFicha } from './paginas/Jugadores';
import ReelDetalle from './paginas/ReelDetalle';
import ReelPublico from './paginas/ReelPublico';
import Admin from './paginas/Admin';

export default function App() {
  const { usuario, cargando, sinRed, reintentar, salir, esEditor, cat, temporadaId, setTemporadaId } = useApp();
  const { pathname } = useLocation();

  if (pathname.startsWith('/r/')) return <Routes><Route path="/r/:token" element={<ReelPublico />} /></Routes>;
  if (cargando) return <div className="centro"><div className="girando" aria-label="Cargando" /></div>;
  if (sinRed && !usuario) return (
    <div className="centro"><div className="col" style={{ alignItems: 'center' }}>
      <Logo t={56} /><h2 style={{ margin: 0, color: 'var(--texto)' }}>Sin conexión</h2>
      <p style={{ margin: 0, maxWidth: 320 }}>Los videos y los datos están en el servidor. Revisa tu conexión; la app se reconecta sola.</p>
      <button className="btn" onClick={reintentar}>Reintentar</button>
    </div></div>
  );
  if (!usuario) return <Login />;

  const secciones = [
    { a: '/', e: 'Galería', i: 'galeria', fin: true },
    { a: '/highlights', e: 'Highlights', i: 'highlights' },
    { a: '/jugadores', e: 'Jugadores', i: 'jugadores' },
    ...(esEditor ? [{ a: '/subir', e: 'Subir', i: 'subir' }, { a: '/admin', e: 'Administración', i: 'admin' }] : []),
  ];
  const temporada = (
    <select className="temporada" value={temporadaId ?? ''} onChange={e => setTemporadaId(e.target.value ? +e.target.value : null)} aria-label="Temporada">
      {cat.temporadas.length === 0 && <option value="">Sin temporadas</option>}
      {cat.temporadas.map(t => <option key={t.temporadaId} value={t.temporadaId}>Temporada {t.nombre}</option>)}
    </select>
  );

  return (
    <div className="app">
      <a className="saltar" href="#contenido">Saltar al contenido</a>
      {/* escritorio: barra lateral · móvil: cabecera compacta + pestañas inferiores */}
      <aside className="lateral">
        <div className="marca"><Logo /> <span>Soccer</span></div>
        {temporada}
        <nav aria-label="Secciones">
          {secciones.map(s => <NavLink key={s.a} to={s.a} end={s.fin}><Icono n={s.i} /> <span>{s.e}</span></NavLink>)}
        </nav>
        <Instalar />
        <div className="usuario">
          <div className="avatar chico">{usuario.nombre.slice(0, 1).toUpperCase()}</div>
          <div className="crece"><div className="nombre">{usuario.nombre}</div><div className="tenue chico">{ROLES[usuario.rol]}</div></div>
          <button className="btn-icono" onClick={salir} aria-label="Cerrar sesión" title="Cerrar sesión"><Icono n="salir" /></button>
        </div>
      </aside>
      <header className="cabecera-movil">
        <div className="marca"><Logo t={24} /> <span>Soccer</span></div>
        {temporada}
        <button className="btn-icono" onClick={salir} aria-label="Cerrar sesión"><Icono n="salir" /></button>
      </header>
      <main id="contenido">
        <Routes>
          <Route path="/" element={<Galeria />} />
          <Route path="/subir" element={<Subir />} />
          <Route path="/medio/:id" element={<VideoDetalle />} />
          <Route path="/highlights" element={<Highlights />} />
          <Route path="/jugadores" element={<Jugadores />} />
          <Route path="/jugadores/:id" element={<JugadorFicha />} />
          <Route path="/reels/:id" element={<ReelDetalle />} />
          <Route path="/admin" element={<Admin />} />
          <Route path="*" element={<div className="centro">Página no encontrada</div>} />
        </Routes>
      </main>
      <nav className="pestanas-movil" aria-label="Secciones">
        {secciones.map(s => <NavLink key={s.a} to={s.a} end={s.fin}><Icono n={s.i} t={22} /><span>{s.e === 'Administración' ? 'Admin' : s.e}</span></NavLink>)}
      </nav>
      <Avisos />
    </div>
  );
}

function Login() {
  const { entrar } = useApp();
  const [correo, setCorreo] = useState(''); const [clave, setClave] = useState('');
  const [ver, setVer] = useState(false);
  const [error, setError] = useState(''); const [ocupado, setOcupado] = useState(false);
  const enviar = async (e: FormEvent) => {
    e.preventDefault(); setError(''); setOcupado(true);
    try { await entrar(correo.trim(), clave); } catch (x: any) { setError(x.message); } finally { setOcupado(false); }
  };
  return (
    <div className="acceso">
      <section className="acceso-marca" aria-hidden="true">
        <svg className="cancha" viewBox="0 0 400 600" preserveAspectRatio="xMidYMid slice">
          <g fill="none" stroke="currentColor" strokeWidth="2">
            <rect x="30" y="30" width="340" height="540" /><path d="M30 300h340" /><circle cx="200" cy="300" r="56" />
            <rect x="110" y="30" width="180" height="90" /><rect x="155" y="30" width="90" height="36" /><path d="M160 120a44 44 0 0 0 80 0" />
            <rect x="110" y="480" width="180" height="90" /><rect x="155" y="534" width="90" height="36" /><path d="M160 480a44 44 0 0 1 80 0" />
          </g>
          <circle cx="200" cy="300" r="4" fill="currentColor" />
        </svg>
        <div className="acceso-texto">
          <div className="marca grande"><Logo t={44} /> <span>Soccer</span></div>
          <h1>La temporada completa, lista para que te vean.</h1>
          <ul>
            <li><Icono n="galeria" /> Videos y fotos de cada partido en una sola galería</li>
            <li><Icono n="highlights" /> Las mejores jugadas, ordenadas con criterio de visor</li>
            <li><Icono n="jugadores" /> Un reel de reclutamiento por jugador, listo para compartir</li>
          </ul>
        </div>
      </section>
      <section className="acceso-form">
        <form onSubmit={enviar} noValidate={false}>
          <div className="marca solo-movil"><Logo t={32} /> <span>Soccer</span></div>
          <h2>Inicia sesión</h2>
          <p className="tenue">Entra con la cuenta que te dio tu club.</p>
          <label>Correo
            <input type="email" autoComplete="username" inputMode="email" value={correo} onChange={e => setCorreo(e.target.value)} required autoFocus placeholder="nombre@club.com" />
          </label>
          <label>Contraseña
            <div className="con-boton">
              <input type={ver ? 'text' : 'password'} autoComplete="current-password" value={clave} onChange={e => setClave(e.target.value)} required />
              <button type="button" className="btn-icono" onClick={() => setVer(!ver)} aria-label={ver ? 'Ocultar contraseña' : 'Mostrar contraseña'} aria-pressed={ver}><Icono n={ver ? 'ojoNo' : 'ojo'} t={18} /></button>
            </div>
          </label>
          {error && <div className="aviso error" role="alert">{error}</div>}
          <button className="btn grande" disabled={ocupado}>{ocupado ? 'Entrando…' : 'Entrar'}</button>
          <p className="tenue chico">¿No tienes cuenta o la olvidaste? Pídela al administrador de tu club.</p>
        </form>
      </section>
    </div>
  );
}

/** Botón "Instalar app": aparece solo cuando el navegador ofrece instalarla y aún no está instalada. */
function Instalar() {
  const [oferta, setOferta] = useState<any>(null);
  useEffect(() => {
    const oye = (e: Event) => { e.preventDefault(); setOferta(e); };
    const lista = () => setOferta(null);
    window.addEventListener('beforeinstallprompt', oye); window.addEventListener('appinstalled', lista);
    return () => { window.removeEventListener('beforeinstallprompt', oye); window.removeEventListener('appinstalled', lista); };
  }, []);
  if (!oferta) return null;
  return <button className="btn sec" onClick={async () => { oferta.prompt(); await oferta.userChoice; setOferta(null); }}><Icono n="mas" t={16} /> Instalar app</button>;
}
