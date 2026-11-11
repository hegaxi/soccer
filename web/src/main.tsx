import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { Proveedor } from './contexto';
import App from './App';
import './estilos.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode><BrowserRouter><Proveedor><App /></Proveedor></BrowserRouter></StrictMode>,
);

// Instalable ("fijar" en el teléfono o la barra de tareas). Solo en la versión compilada.
if (import.meta.env.PROD && 'serviceWorker' in navigator)
  window.addEventListener('load', () => { navigator.serviceWorker.register('/sw.js').catch(() => {}); });
