import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

// Docker Desktop bind mounts (macOS/linuxkit) don't deliver inotify events, so
// the `vite build --watch` file watcher never sees source edits. Opt into
// polling when VITE_USE_POLLING=true (set by the Phoenix dev watcher).
const usePolling = process.env.VITE_USE_POLLING === 'true'

export default defineConfig({
  server: {
    port: 5173,
    strictPort: true,
    cors: { origin: "http://localhost:9000" },
    watch: usePolling ? { usePolling: true, interval: 200 } : undefined,
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
    watch: usePolling ? { chokidar: { usePolling: true, interval: 200 } } : undefined,
  },
  plugins: [
    svelte(),
  ]
})
