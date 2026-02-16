import { defineConfig } from 'vite';

export default defineConfig({
  base: '/',
  server: {
    proxy: {
      '/api': {
        target: process.env.MOSHI_BACKEND || 'https://localhost:8998',
        ws: true,
        secure: false,
        changeOrigin: true,
      },
    },
  },
});
