import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// En desarrollo /api se redirige a la API de .NET; al compilar, la app queda en api/wwwroot.
export default defineConfig({
  plugins: [react()],
  server: { proxy: { '/api': process.env.API ?? 'http://localhost:5080' } },
  build: { outDir: '../api/wwwroot', emptyOutDir: true },
});
