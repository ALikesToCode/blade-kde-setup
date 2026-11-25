// Shared helpers: argument parsing, finding Playwright, launching Chromium.
import { createRequire } from 'node:module';
import { existsSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

export function args(argv = process.argv.slice(2)) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) { out._.push(a); continue; }
    const eq = a.indexOf('=');
    if (eq > 0) out[a.slice(2, eq)] = a.slice(eq + 1);
    else if (argv[i + 1] !== undefined && !argv[i + 1].startsWith('--')) out[a.slice(2)] = argv[++i];
    else out[a.slice(2)] = true;
  }
  return out;
}

export function die(message, code = 3) {
  console.error(message);
  process.exit(code);
}

// Playwright is not bundled. Look in the current project, then PLAYWRIGHT_PATH, then global installs.
export async function loadChromium() {
  const tried = [];
  for (const base of [process.cwd(), process.env.PLAYWRIGHT_PATH].filter(Boolean)) {
    for (const name of ['playwright-core', 'playwright']) {
      try {
        const resolved = createRequire(path.join(base, 'noop.js')).resolve(name);
        const mod = await import(pathToFileURL(resolved).href);
        const chromium = mod.chromium ?? mod.default?.chromium;
        if (chromium) return chromium;
        tried.push(`${name} from ${base} (no chromium export)`);
      } catch { tried.push(`${name} from ${base}`); }
    }
  }
  die(`Playwright not found (${tried.join('; ')}).\nRun from a project that has playwright or playwright-core installed, or set PLAYWRIGHT_PATH to such a project's folder.`);
}

export async function launch(extra = {}) {
  const chromium = await loadChromium();
  const candidates = [process.env.CHROMIUM_PATH, '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome-stable'];
  const executablePath = candidates.find((p) => p && existsSync(p));
  return chromium.launch({
    ...(executablePath ? { executablePath } : {}),
    headless: true,
    // Software WebGL so canvases render without a display.
    args: ['--enable-webgl', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'],
    ...extra,
  });
}

export const VIEWPORTS = {
  desktop: { width: 1440, height: 900, isMobile: false, hasTouch: false },
  phone: { width: 390, height: 844, isMobile: true, hasTouch: true },
};

export function watch(page) {
  const errors = [];
  const failed = [];
  page.on('pageerror', (e) => errors.push(String(e).slice(0, 300)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(`console: ${m.text().slice(0, 300)}`); });
  page.on('requestfailed', (r) => failed.push({ url: r.url().slice(0, 200), reason: r.failure()?.errorText ?? '' }));
  page.on('response', (r) => { if (r.status() >= 400) failed.push({ url: r.url().slice(0, 200), reason: `HTTP ${r.status()}` }); });
  return { errors, failed };
}
