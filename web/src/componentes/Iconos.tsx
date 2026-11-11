// Iconos de trazo en SVG: sin dependencias ni fuentes externas, heredan el color del texto.
const trazos: Record<string, string> = {
  galeria: 'M3 5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2zM3 16l5-5 4 4 3-3 6 6M15.5 8.5h.01',
  highlights: 'M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z',
  jugadores: 'M16 20v-1a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v1M9.5 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7M21 20v-1a4 4 0 0 0-3-3.9M15.5 4.2a3.5 3.5 0 0 1 0 6.6',
  subir: 'M12 16V4M7 9l5-5 5 5M4 16v3a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-3',
  admin: 'M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0M16 4v4M10 10v4M18 16v4',
  salir: 'M9 20H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1h4M16 16l4-4-4-4M20 12H9',
  ojo: 'M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12zM12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6',
  ojoNo: 'M3 3l18 18M10.6 5.1A9.8 9.8 0 0 1 12 5c6.4 0 10 7 10 7a17 17 0 0 1-3.2 4M6.3 6.3A17 17 0 0 0 2 12s3.6 7 10 7a9.6 9.6 0 0 0 4.3-1M9.9 9.9a3 3 0 0 0 4.2 4.2',
  mas: 'M12 5v14M5 12h14',
  video: 'M4 6a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2zM16 10l5-3v10l-5-3',
  foto: 'M4 8a2 2 0 0 1 2-2h1.5l1.5-2h6l1.5 2H18a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2zM12 16a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7',
};

export function Icono({ n, t = 20 }: { n: keyof typeof trazos | string; t?: number }) {
  return (
    <svg width={t} height={t} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"
         strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
      <path d={trazos[n]} />
    </svg>
  );
}

/** Marca de la aplicación: balón estilizado. */
export function Logo({ t = 28 }: { t?: number }) {
  return (
    <svg width={t} height={t} viewBox="0 0 32 32" aria-hidden="true" focusable="false">
      <circle cx="16" cy="16" r="15" fill="var(--verde2)" />
      <path d="M16 9.5l6 4.4-2.3 7.1h-7.4L10 13.9z" fill="#fff" />
      <path d="M16 9.5V3M22 13.9l6.4-2M19.7 21l4 5.4M12.3 21l-4 5.4M10 13.9l-6.4-2" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" />
    </svg>
  );
}
