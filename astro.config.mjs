// @ts-check
import { defineConfig } from 'astro/config';

// Served from the root of jpy27.delphyra.tech (a Cloudflare Worker, see wrangler.jsonc).
export default defineConfig({
  site: 'https://jpy27.delphyra.tech',
  trailingSlash: 'always',
  build: { format: 'directory' },
  prefetch: { prefetchAll: true, defaultStrategy: 'hover' },
  devToolbar: { enabled: false },
  scopedStyleStrategy: 'class',
  // maplibre-gl is imported lazily; pre-bundle it so the dev server does not re-optimise mid-load
  vite: { optimizeDeps: { include: ['maplibre-gl'] } },
});
