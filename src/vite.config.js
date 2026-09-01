import { defineConfig } from 'vite';
import tailwindcss from '@tailwindcss/vite';
import { createReadStream, existsSync, readdirSync, copyFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = dirname(fileURLToPath(import.meta.url));
const iconsDir = resolve(rootDir, 'assets');

const ICON_MIME = {
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
};

function copyDir(src, dest) {
  mkdirSync(dest, { recursive: true });
  for (const ent of readdirSync(src, { withFileTypes: true })) {
    const from = join(src, ent.name);
    const to = join(dest, ent.name);
    if (ent.isDirectory()) copyDir(from, to);
    else copyFileSync(from, to);
  }
}

// Copy src/assets/* into dist/assets/ (alongside app.js / app.css) so the Pager
// can serve the icons as static files. In `vite`/`npm run dev`, the same folder
// is served at /assets/.
function copyStaticAssets() {
  return {
    name: 'copy-static-assets',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const raw = (req.url || '').split('?')[0];
        if (!raw.startsWith('/assets/')) return next();
        const rel = decodeURIComponent(raw.slice('/assets/'.length));
        if (!rel || rel.includes('..') || rel.includes('\\') || rel.includes('\0')) return next();
        const file = resolve(iconsDir, rel);
        const root = resolve(iconsDir);
        if ((file !== root && !file.startsWith(root + '/')) || !existsSync(file) || !statSync(file).isFile()) {
          return next();
        }
        res.setHeader('Content-Type', ICON_MIME[extname(file).toLowerCase()] || 'application/octet-stream');
        res.setHeader('Cache-Control', 'no-cache');
        createReadStream(file).pipe(res);
      });
    },
    writeBundle() {
      if (existsSync(iconsDir)) copyDir(iconsDir, resolve(rootDir, 'dist/assets'));
    },
  };
}

// The Pager serves the built output as plain static files via nginx (no Node on device).
// We emit deterministic, unhashed asset names so the portal PHP can reference them directly.
export default defineConfig({
  plugins: [tailwindcss(), copyStaticAssets()],
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      // Local `npm run dev` also starts PHP on :8080 against dummy files/USB drives.
      '/api': { target: 'http://127.0.0.1:8080', changeOrigin: true },
    },
  },
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    emptyOutDir: true,
    cssCodeSplit: false,
    rollupOptions: {
      input: 'main.js',
      output: {
        entryFileNames: 'assets/app.js',
        assetFileNames: 'assets/app.[ext]',
      },
    },
  },
});
