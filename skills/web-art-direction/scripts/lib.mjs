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

const AUTOPLAY = '--autoplay-policy=no-user-gesture-required';
const GL_FLAGS = {
  hardware: ['--use-angle=gl-egl', '--enable-gpu', '--ignore-gpu-blocklist', AUTOPLAY],
  software: ['--enable-webgl', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', AUTOPLAY],
};

// The WebGL renderer this browser really uses, or null when it has no WebGL.
async function webglRenderer(browser) {
  const context = await browser.newContext();
  try {
    const page = await context.newPage();
    return await page.evaluate(() => {
      const gl = document.createElement('canvas').getContext('webgl');
      if (!gl) return null;
      const info = gl.getExtension('WEBGL_debug_renderer_info');
      return String(gl.getParameter(info ? info.UNMASKED_RENDERER_WEBGL : gl.RENDERER));
    });
  } catch { return null; } finally { await context.close().catch(() => {}); }
}

export const isSoftwareGL = (renderer) => !renderer || /swiftshader|llvmpipe|softpipe/i.test(renderer);

// Does the page ask for a WebGL or WebGPU context while it loads?
async function wantsGPU(browser, url) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  try {
    await context.addInitScript(() => {
      const flag = () => { window.__wantsGPU = true; };
      const get = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (type, ...rest) { if (/webgl|webgpu/i.test(String(type))) flag(); return get.call(this, type, ...rest); };
      // A canvas handed to a worker is almost always a WebGL scene.
      const transfer = HTMLCanvasElement.prototype.transferControlToOffscreen;
      if (transfer) HTMLCanvasElement.prototype.transferControlToOffscreen = function (...rest) { flag(); return transfer.apply(this, rest); };
      if (navigator.gpu?.requestAdapter) { const ask = navigator.gpu.requestAdapter.bind(navigator.gpu); navigator.gpu.requestAdapter = (...rest) => { flag(); return ask(...rest); }; }
    });
    const page = await context.newPage();
    await page.goto(url, { waitUntil: 'load', timeout: 45000 });
    await page.waitForTimeout(800);
    for (const frame of page.frames()) if (await frame.evaluate(() => !!window.__wantsGPU).catch(() => false)) return true;
    return false;
  } catch { return false; } finally { await context.close().catch(() => {}); }
}

// Starts Chromium and returns { browser, renderer, gl }.
// A page that asks for WebGL gets the machine's GPU: software WebGL runs a 3D scene at a few frames
// per second, and a page that hides its scene from software renderers would show only its fallback.
// Every other page gets software rendering, which does not stall when other programs keep the GPU
// busy. --gl hardware|software overrides the choice. Without a usable GPU the browser falls back to
// software. With --cdp ENDPOINT the scripts attach to a browser that is already running instead.
export async function launch({ cdp, gl, url } = {}) {
  if (gl !== undefined && !GL_FLAGS[gl]) die(`unknown --gl ${gl} (use hardware or software)`);
  const chromium = await loadChromium();
  if (cdp) {
    const browser = await chromium.connectOverCDP(String(cdp));
    const renderer = await webglRenderer(browser);
    return { browser, renderer, gl: isSoftwareGL(renderer) ? 'software' : 'hardware' };
  }
  const candidates = [process.env.CHROMIUM_PATH, '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome-stable'];
  const executablePath = candidates.find((p) => p && existsSync(p));
  const start = (mode) => chromium.launch({ ...(executablePath ? { executablePath } : {}), headless: true, args: GL_FLAGS[mode] });
  let mode = gl ?? 'software';
  let browser = await start(mode);
  if (gl === undefined && url && (await wantsGPU(browser, url))) {
    await browser.close();
    mode = 'hardware';
    browser = await start(mode);
  }
  let renderer = await webglRenderer(browser);
  if (mode === 'hardware' && !renderer) {
    await browser.close();
    mode = 'software';
    browser = await start(mode);
    renderer = await webglRenderer(browser);
  }
  return { browser, renderer, gl: isSoftwareGL(renderer) ? 'software' : 'hardware' };
}

export const VIEWPORTS = {
  desktop: { width: 1440, height: 900, isMobile: false, hasTouch: false },
  phone: { width: 390, height: 844, isMobile: true, hasTouch: true },
};

export function watch(page) {
  const errors = [];
  const failed = [];
  page.on('pageerror', (e) => errors.push(String(e).slice(0, 300)));
  // Failed loads are reported once, from the request events below.
  page.on('console', (m) => { if (m.type() === 'error' && !m.text().startsWith('Failed to load resource')) errors.push(`console: ${m.text().slice(0, 300)}`); });
  page.on('requestfailed', (r) => failed.push({ url: r.url().slice(0, 200), reason: r.failure()?.errorText ?? '' }));
  page.on('response', (r) => { if (r.status() >= 400) failed.push({ url: r.url().slice(0, 200), reason: `HTTP ${r.status()}` }); });
  return { errors, failed };
}

// Reads pixels inside a blank page of the same browser, so the scripts need no image library.
// Images are passed as base64 strings.
//   next(b64, mime, boxes)  share of pixels that differ from the reference image (null on the first
//                           call). The image becomes the new reference only when more than 0.2%
//                           differ, so a slow fade adds up instead of hiding under the threshold.
//                           boxes limits the comparison to parts of the picture, each
//                           { x, y, w, h } as fractions of its width and height.
//   differ(a, b, mime)      the same share for two images.
//   sheet(tiles, cell, cols) a PNG contact sheet as a Buffer; tiles are [{ b64, mime, label }].
export async function pixelReader(browser) {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.evaluate(() => {
    const bitmap = (b64, mime) => createImageBitmap(new Blob([Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))], { type: mime }));
    const decode = async (b64, mime, width = 360) => {
      const bmp = await bitmap(b64, mime);
      const w = Math.min(width, bmp.width), h = Math.max(1, Math.round((bmp.height * w) / bmp.width));
      const g = new OffscreenCanvas(w, h).getContext('2d', { willReadFrequently: true });
      g.drawImage(bmp, 0, 0, w, h);
      bmp.close();
      return { w, h, data: g.getImageData(0, 0, w, h).data };
    };
    const share = (a, b, boxes) => {
      if (!a || !b || a.w !== b.w || a.h !== b.h) return null;
      const areas = boxes ? boxes.map((r) => [Math.floor(r.x * a.w), Math.floor(r.y * a.h), Math.ceil((r.x + r.w) * a.w), Math.ceil((r.y + r.h) * a.h)]) : [[0, 0, a.w, a.h]];
      let n = 0, d = 0;
      for (const [x0, y0, x1, y1] of areas) {
        for (let y = Math.max(0, y0); y < Math.min(a.h, y1); y++) {
          for (let x = Math.max(0, x0); x < Math.min(a.w, x1); x++) {
            const i = (y * a.w + x) * 4;
            n++;
            if (Math.abs(a.data[i] - b.data[i]) + Math.abs(a.data[i + 1] - b.data[i + 1]) + Math.abs(a.data[i + 2] - b.data[i + 2]) > 24) d++;
          }
        }
      }
      return n ? d / n : 0;
    };
    let ref = null;
    window.__px = {
      decode,
      reset: () => { ref = null; },
      next: async (b64, mime, boxes) => { const cur = await decode(b64, mime); const s = share(ref, cur, boxes); if (s === null || s > 0.002) ref = cur; return s; },
      differ: async (a, b, mime) => share(await decode(a, mime, 720), await decode(b, mime, 720)),
      sheet: async (tiles, cell, cols) => {
        const bmps = await Promise.all(tiles.map((t) => bitmap(t.b64, t.mime)));
        // Each label sits in its own band above the tile, so it hides none of the picture.
        const pad = 4, band = 24, th = Math.round((bmps[0].height * cell) / bmps[0].width);
        const c = new OffscreenCanvas(cols * (cell + pad) + pad, Math.ceil(tiles.length / cols) * (th + band + pad) + pad);
        const g = c.getContext('2d');
        g.fillStyle = '#222';
        g.fillRect(0, 0, c.width, c.height);
        g.font = '600 15px sans-serif';
        g.textBaseline = 'middle';
        g.fillStyle = '#fff';
        tiles.forEach((t, i) => {
          const x = pad + (i % cols) * (cell + pad), y = pad + Math.floor(i / cols) * (th + band + pad);
          g.fillText(t.label, x + 2, y + band / 2, cell - 4);
          g.drawImage(bmps[i], x, y + band, cell, th);
        });
        const bytes = new Uint8Array(await (await c.convertToBlob({ type: 'image/png' })).arrayBuffer());
        let s = '';
        for (let i = 0; i < bytes.length; i += 32768) s += String.fromCharCode(...bytes.subarray(i, i + 32768));
        return btoa(s);
      },
    };
  });
  return {
    page,
    reset: () => page.evaluate(() => window.__px.reset()),
    next: (b64, mime, boxes = null) => page.evaluate(([d, m, b]) => window.__px.next(d, m, b), [b64, mime, boxes]),
    differ: (x, y, mime) => page.evaluate(([p, q, m]) => window.__px.differ(p, q, m), [x, y, mime]),
    sheet: async (tiles, cell, cols) => Buffer.from(await page.evaluate(([t, c, n]) => window.__px.sheet(t, c, n), [tiles, cell, cols]), 'base64'),
    close: () => context.close(),
  };
}
