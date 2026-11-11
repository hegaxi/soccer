import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { Proveedor } from './contexto';
import App from './App';
import './estilos.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode><BrowserRouter><Proveedor><App /></Proveedor></BrowserRouter></StrictMode>,
);
