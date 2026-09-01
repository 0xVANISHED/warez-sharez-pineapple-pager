#!/usr/bin/env node
// Local WarezSharez stack: dummy files + fake USB drives, PHP API on :8080,
// Vite (HMR) on :5173 proxying /api to PHP.
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, '..');
const dataRoot = join(__dirname, 'data');
const portal = join(root, 'payloads/user/WarezSharez/warezsharez_install/portal');
const srcDir = join(root, 'src');
const phpOnly = process.argv.includes('--php-only');

const PHP_HOST = '127.0.0.1';
const PHP_PORT = 8080;
const VITE_PORT = 5173;

// 1x1 PNG so inline image previews have something real to open.
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
);

function seed() {
  const files = {
    'payloads/notes.txt':
      'Outside the share (like /mmc/root). Browseable, not writable from the UI.\n',
    'warezsharez/drop-zone.txt':
      'Local-dev share. Upload, download, and delete work in this folder.\n',
    'warezsharez/screenshots/hello.png': PNG,
    'warezsharez/usb/KINGSTON/from-the-stick.txt':
      'Placeholder files on a fake Kingston USB drive.\n',
    'warezsharez/usb/KINGSTON/movies/not-a-real-movie.mp4': 'FAKE MP4\n',
    'warezsharez/usb/KINGSTON/music/track01.mp3': 'FAKE MP3\n',
    'warezsharez/usb/SANDISK/backups/old-stuff.zip': 'FAKE ZIP\n',
    'warezsharez/usb/SANDISK/photos/vacation.png': PNG,
  };
  for (const [rel, body] of Object.entries(files)) {
    const abs = join(dataRoot, rel);
    mkdirSync(dirname(abs), { recursive: true });
    if (!existsSync(abs)) writeFileSync(abs, body);
  }
}

function waitFor(url, timeoutMs = 15000) {
  const start = Date.now();
  return new Promise((resolve, reject) => {
    const tick = async () => {
      try {
        const res = await fetch(url);
        if (res.ok || res.status === 404) { resolve(); return; }
      } catch { /* not up yet */ }
      if (Date.now() - start > timeoutMs) {
        reject(new Error(`Timed out waiting for ${url}`));
        return;
      }
      setTimeout(tick, 150);
    };
    tick();
  });
}

seed();

const env = {
  ...process.env,
  WAREZ_DEV: '1',
  WAREZ_ROOT: join(dataRoot, 'warezsharez'),
  WAREZ_READ_ROOT: dataRoot,
};

const children = [];

function killAll() {
  for (const c of children) {
    try { c.kill('SIGTERM'); } catch { /* already gone */ }
  }
}

process.on('SIGINT', () => { killAll(); process.exit(0); });
process.on('SIGTERM', () => { killAll(); process.exit(0); });

console.log(`[dev] dummy share  ${env.WAREZ_ROOT}`);
console.log(`[dev] PHP API      http://${PHP_HOST}:${PHP_PORT}/`);

const php = spawn(
  'php',
  ['-S', `${PHP_HOST}:${PHP_PORT}`, '-t', portal, join(__dirname, 'router.php')],
  { env, cwd: portal, stdio: ['ignore', 'pipe', 'pipe'] },
);
children.push(php);
php.stdout.on('data', (b) => process.stdout.write(`[php] ${b}`));
php.stderr.on('data', (b) => process.stderr.write(`[php] ${b}`));
php.on('exit', (code) => {
  if (code && code !== 0) {
    console.error(`[dev] PHP exited with ${code}`);
    killAll();
    process.exit(code);
  }
});

try {
  await waitFor(`http://${PHP_HOST}:${PHP_PORT}/api/list.php?path=warezsharez`);
} catch (e) {
  console.error(`[dev] ${e.message}`);
  killAll();
  process.exit(1);
}

if (phpOnly) {
  console.log('[dev] PHP-only mode. Open the URL above (built assets, no Vite HMR).');
  await new Promise(() => { /* keep alive until signal */ });
}

const viteBin = join(srcDir, 'node_modules/.bin/vite');
console.log(`[dev] Vite UI      http://127.0.0.1:${VITE_PORT}/  (HMR, /api proxied to PHP)`);

const vite = spawn(viteBin, ['--host', '127.0.0.1', '--port', String(VITE_PORT)], {
  cwd: srcDir,
  env,
  stdio: 'inherit',
});
children.push(vite);
vite.on('exit', (code) => {
  killAll();
  process.exit(code ?? 0);
});
