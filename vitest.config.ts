import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    environment: 'node',
    setupFiles: ['./tests/offline/setup.ts'],
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, '.'),
      // `server-only` existe para que Next falle el BUILD si un módulo
      // de servidor se importa desde un client component. Bajo vitest
      // no hay esa distinción y el paquete resuelve a su build de
      // cliente, que tira siempre. Se mapea a un módulo vacío: el
      // guard real lo sigue aplicando `next build` (que pasa), acá
      // solo se destraba poder testear módulos de servidor.
      'server-only': path.resolve(__dirname, 'tests/stubs/server-only.ts'),
    },
  },
});
