import { useState } from 'react';
import { exec, fecha, ROLES } from '../api';
import { useApp } from '../contexto';
import { Campo, Formulario, Modal, useCarga } from '../componentes/comunes';

type Edicion = { titulo: string; accion: string; campos: Campo[]; inicial: Record<string, any> } | null;

export default function Admin() {
  const { esEditor, esAdmin, cat, recargarCat, temporadaId } = useApp();
  const [tab, setTab] = useState('partidos'); const [ed, setEd] = useState<Edicion>(null);
  const partidos = useCarga(async () => (await exec('partido.listar', { temporadaId }))[0], [temporadaId]);
  const usuarios = useCarga(async () => esAdmin ? (await exec('usuario.listar'))[0] : [], [esAdmin]);
  if (!esEditor) return <div className="centro">Sección para editores y administradores.</div>;

  const equipos = cat.equipos.map(e => ({ v: e.equipoId, e: e.nombre }));
  const cPartido: Campo[] = [
    { n: 'fecha', e: 'Fecha', t: 'date', req: true }, { n: 'competencia', e: 'Competencia' }, { n: 'jornada', e: 'Jornada', t: 'number' },
    { n: 'fase', e: 'Fase', t: 'select', op: cat.fases.map(f => ({ v: f.clave, e: `${f.nombre} (×${f.factor})` })), req: true },
    { n: 'equipoLocalId', e: 'Local', t: 'select', op: equipos, req: true }, { n: 'equipoVisitaId', e: 'Visitante', t: 'select', op: equipos, req: true },
    { n: 'golesLocal', e: 'Goles local', t: 'number' }, { n: 'golesVisita', e: 'Goles visitante', t: 'number' },
    { n: 'nivelRival', e: 'Nivel del rival', t: 'select', req: true, ayuda: 'Pesa en el puntaje de reclutamiento de cada jugada',
      op: [1, 2, 3, 4, 5].map(n => ({ v: n, e: `${n} · ${['Muy débil', 'Débil', 'Parejo', 'Fuerte', 'Élite'][n - 1]}` })) },
  ];
  const cEquipo: Campo[] = [{ n: 'nombre', e: 'Nombre', req: true }, { n: 'categoria', e: 'Categoría' }, { n: 'esPropio', e: 'Es nuestro equipo', t: 'check' },
    { n: 'contactoNombre', e: 'Contacto para visores', ayuda: 'Coordinador o entrenador que atiende a los visores' }, { n: 'contactoCargo', e: 'Cargo' },
    { n: 'contactoCorreo', e: 'Correo del contacto', t: 'email' }, { n: 'contactoTelefono', e: 'Teléfono del contacto' }];
  const cTemporada: Campo[] = [{ n: 'nombre', e: 'Nombre', req: true }, { n: 'fechaInicio', e: 'Inicio', t: 'date', req: true }, { n: 'fechaFin', e: 'Fin', t: 'date', req: true }, { n: 'activa', e: 'Temporada activa', t: 'check' }];
  const cUsuario = (nuevo: boolean): Campo[] => [{ n: 'nombre', e: 'Nombre', req: true }, { n: 'correo', e: 'Correo', t: 'email', req: true },
    { n: 'rol', e: 'Rol', t: 'select', op: [1, 2, 3].map(r => ({ v: r, e: ROLES[r] })), req: true },
    { n: 'clave', e: nuevo ? 'Contraseña' : 'Nueva contraseña (opcional)', t: 'password', req: nuevo, ayuda: 'Mínimo 8 caracteres' }, { n: 'activo', e: 'Activo', t: 'check' }];

  const guardar = async (v: Record<string, any>) => {
    await exec(ed!.accion, v); setEd(null);
    await Promise.all([recargarCat(), partidos.recargar(), usuarios.recargar()]);
  };
  const tabs = [['partidos', 'Partidos'], ['equipos', 'Equipos'], ...(esAdmin ? [['temporadas', 'Temporadas'], ['usuarios', 'Usuarios']] : [])];

  return (
    <div className="col">
      <h1>Administración</h1>
      <div className="pestanas">{tabs.map(([k, e]) => <button key={k} className={tab === k ? 'activa' : ''} onClick={() => setTab(k)}>{e}</button>)}</div>

      {tab === 'partidos' && <>
        <div><button className="btn" disabled={!temporadaId} onClick={() => setEd({ titulo: 'Nuevo partido', accion: 'partido.guardar', campos: cPartido,
          inicial: { temporadaId, fecha: '', competencia: '', jornada: null, fase: 'LIGA', equipoLocalId: null, equipoVisitaId: null, golesLocal: null, golesVisita: null, nivelRival: 3 } })}>+ Nuevo partido</button></div>
        <table><thead><tr><th>Fecha</th><th>Partido</th><th>Competencia</th><th>Fase</th><th>Rival</th><th>Medios</th><th /></tr></thead>
          <tbody>{partidos.datos?.map(p => <tr key={p.partidoId}><td>{fecha(p.fecha)}</td><td><b>{p.local} {p.golesLocal ?? ''} - {p.golesVisita ?? ''} {p.visita}</b></td>
            <td className="tenue">{p.competencia}{p.jornada ? ` · J${p.jornada}` : ''}</td><td>{p.faseNombre}</td><td>Nivel {p.nivelRival}</td><td className="tenue">{p.videos} videos · {p.fotos} fotos</td>
            <td className="der"><button className="btn sec mini" onClick={() => { const { local, visita, faseNombre, videos, fotos, ...r } = p; setEd({ titulo: 'Editar partido', accion: 'partido.guardar', campos: cPartido, inicial: r }); }}>Editar</button></td></tr>)}</tbody></table>
      </>}

      {tab === 'equipos' && <>
        <div><button className="btn" onClick={() => setEd({ titulo: 'Nuevo equipo', accion: 'equipo.guardar', campos: cEquipo, inicial: { nombre: '', categoria: '', esPropio: false, contactoNombre: '', contactoCargo: '', contactoCorreo: '', contactoTelefono: '' } })}>+ Nuevo equipo</button></div>
        <table><thead><tr><th>Equipo</th><th>Categoría</th><th /><th /></tr></thead>
          <tbody>{cat.equipos.map(e => <tr key={e.equipoId}><td><b>{e.nombre}</b></td><td className="tenue">{e.categoria}</td><td>{e.esPropio && <span className="etq verde">Nuestro equipo</span>} {e.esPropio && !e.contactoCorreo && !e.contactoTelefono && <span className="etq ambar">Sin contacto para visores</span>}</td>
            <td className="der"><button className="btn sec mini" onClick={() => setEd({ titulo: 'Editar equipo', accion: 'equipo.guardar', campos: cEquipo, inicial: e })}>Editar</button></td></tr>)}</tbody></table>
      </>}

      {tab === 'temporadas' && esAdmin && <>
        <div><button className="btn" onClick={() => setEd({ titulo: 'Nueva temporada', accion: 'temporada.guardar', campos: cTemporada, inicial: { nombre: '', fechaInicio: '', fechaFin: '', activa: true } })}>+ Nueva temporada</button></div>
        <table><thead><tr><th>Temporada</th><th>Periodo</th><th /><th /></tr></thead>
          <tbody>{cat.temporadas.map(t => <tr key={t.temporadaId}><td><b>{t.nombre}</b></td><td className="tenue">{fecha(t.fechaInicio)} – {fecha(t.fechaFin)}</td><td>{t.activa && <span className="etq verde">Activa</span>}</td>
            <td className="der"><button className="btn sec mini" onClick={() => setEd({ titulo: 'Editar temporada', accion: 'temporada.guardar', campos: cTemporada, inicial: t })}>Editar</button></td></tr>)}</tbody></table>
      </>}

      {tab === 'usuarios' && esAdmin && <>
        <div><button className="btn" onClick={() => setEd({ titulo: 'Nuevo usuario', accion: 'usuario.guardar', campos: cUsuario(true), inicial: { nombre: '', correo: '', rol: 1, clave: '', activo: true } })}>+ Nuevo usuario</button></div>
        <table><thead><tr><th>Nombre</th><th>Correo</th><th>Rol</th><th /><th /></tr></thead>
          <tbody>{usuarios.datos?.map(u => <tr key={u.usuarioId}><td><b>{u.nombre}</b></td><td className="tenue">{u.correo}</td><td>{ROLES[u.rol]}</td><td>{!u.activo && <span className="etq rojo">Inactivo</span>}</td>
            <td className="der"><button className="btn sec mini" onClick={() => { const { creadoEn, ...r } = u; setEd({ titulo: 'Editar usuario', accion: 'usuario.guardar', campos: cUsuario(false), inicial: { ...r, clave: '' } }); }}>Editar</button></td></tr>)}</tbody></table>
      </>}

      {ed && <Modal titulo={ed.titulo} cerrar={() => setEd(null)}><Formulario campos={ed.campos} inicial={ed.inicial} guardar={guardar} cancelar={() => setEd(null)} /></Modal>}
    </div>
  );
}
