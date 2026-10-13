// @ts-check
import { defineConfig } from 'astro/config';

// The site lives under delphyra.tech/.nb2027/. Override with BASE_PATH=/ to serve from a domain root.
const base = process.env.BASE_PATH ?? '/.nb2027';

export default defineConfig({
  site: 'https://delphyra.tech',
  base,
  trailingSlash: 'always',
  build: { format: 'directory' },
  prefetch: { prefetchAll: true, defaultStrategy: 'hover' },
  devToolbar: { enabled: false },
  scopedStyleStrategy: 'class',
});
