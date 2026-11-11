import { FormEvent, useState } from 'react';
import { NavLink, Route, Routes, useLocation } from 'react-router-dom';
import { useApp } from './contexto';
import Galeria from './paginas/Galeria';
import Subir from './paginas/Subir';
import VideoDetalle from './paginas/VideoDetalle';
import Highlights from './paginas/Highlights';
import { Jugadores, JugadorFicha } from './paginas/Jugadores';
import ReelDetalle from './paginas/ReelDetalle';
import ReelPublico from './paginas/ReelPublico';
import Admin from './paginas/Admin';

export default function App() {
  const { usuario, cargando, salir, esEditor, cat, temporadaId, setTemporadaId } = useApp();
  const { pathname } = useLocation();

  if (pathname.startsWith('/r/')) return <Routes><Route path="/r/:token" element={<ReelPublico />} /></Routes>;
  if (cargando) return <div className="centro">Cargando…</div>;
  if (!usuario) return <Login />;

  return (
    <>
      <header className="barra">
        <div className="marca">⚽ Soccer</div>
        <nav>
          <NavLink to="/" end>Galería</NavLink>
          <NavLink to="/highlights">Highlights</NavLink>
          <NavLink to="/jugadores">Jugadores</NavLink>
          {esEditor && <NavLink to="/subir">Subir</NavLink>}
          {esEditor && <NavLink to="/admin">Administración</NavLink>}
        </nav>
        <div className="barra-der">
          <select value={temporadaId ?? ''} onChange={e => setTemporadaId(e.target.value ? +e.target.value : null)} aria-label="Temporada">
            {cat.temporadas.length === 0 && <option value="">Sin temporadas</option>}
            {cat.temporadas.map(t => <option key={t.temporadaId} value={t.temporadaId}>Temporada {t.nombre}</option>)}
          </select>
          <span className="tenue">{usuario.nombre}</span>
          <button className="btn sec" onClick={salir}>Salir</button>
        </div>
      </header>
      <main>
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
    </>
  );
}

function Login() {
  const { entrar } = useApp();
  const [correo, setCorreo] = useState(''); const [clave, setClave] = useState('');
  const [error, setError] = useState(''); const [ocupado, setOcupado] = useState(false);
  const enviar = async (e: FormEvent) => {
    e.preventDefault(); setError(''); setOcupado(true);
    try { await entrar(correo, clave); } catch (x: any) { setError(x.message); } finally { setOcupado(false); }
  };
  return (
    <div className="centro">
      <form className="tarjeta login" onSubmit={enviar}>
        <h1>⚽ Soccer</h1>
        <p className="tenue">Videos, fotos y highlights de la temporada</p>
        <label>Correo<input type="email" value={correo} onChange={e => setCorreo(e.target.value)} required autoFocus /></label>
        <label>Contraseña<input type="password" value={clave} onChange={e => setClave(e.target.value)} required /></label>
        {error && <div className="aviso error">{error}</div>}
        <button className="btn" disabled={ocupado}>{ocupado ? 'Entrando…' : 'Entrar'}</button>
      </form>
    </div>
  );
}
