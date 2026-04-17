import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

export default defineConfig({
  server: {
    port: 5173,
    strictPort: true,
    cors: { origin: "http://localhost:9000" },
  },
  optimizeDeps: {
    include: ["phoenix", "phoenix_html", "phoenix_live_view"],
  },
  build: {
    rollupOptions: {
      input: ["js/app.js"],
      output: {
        entryFileNames: "assets/[name].js",
        chunkFileNames: "assets/[name].js",
      },
    },
    outDir: "../priv/static",
    emptyOutDir: false,
  },
  plugins: [
    svelte(),
  ]
})
