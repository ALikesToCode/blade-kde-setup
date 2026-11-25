#!/usr/bin/env node
// Record one piece of motion and turn it into evidence a reviewer can read.
//   node motion.mjs --url URL --out DIR --trigger load|wheel:PX|click:SELECTOR|hover:SELECTOR|key:KEY
//                   [--ms 4000] [--view desktop|phone] [--reduced] [--settle 1500] [--tiles 16] [--cdp ENDPOINT]
// Writes clip.webm, frames/NN.png, sheet.png (labelled contact sheet) and motion.json.
// Exit 0: something moved. 2: nothing moved, or an animation changes layout properties. 3: could not run.
import { mkdirSync, writeFileSync, renameSync, readdirSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { args, die, launch, VIEWPORTS, watch } from './lib.mjs';

const a = args();
if (!a.url || !a.out || !a.trigger) die('usage: node motion.mjs --url URL --out DIR --trigger load|wheel:PX|click:SEL|hover:SEL|key:KEY [--ms 4000] [--view desktop|phone] [--reduced]');
const ms = Number(a.ms ?? 4000);
const settle = Number(a.settle ?? 1500);
const tiles = Number(a.tiles ?? 16);
const vp = VIEWPORTS[a.view ?? 'desktop'] ?? die(`unknown --view ${a.view}`);
const [kind, ...rest] = String(a.trigger).split(':');
const param = rest.join(':');
if (!['load', 'wheel', 'click', 'hover', 'key'].includes(kind)) die(`unknown trigger ${a.trigger}`);
mkdirSync(path.join(a.out, 'frames'), { recursive: true });

const browser = await launch(a.cdp);
const size = { width: vp.width, height: vp.height };
const t0 = Date.now();
const context = await browser.newContext({
  viewport: size, isMobile: vp.isMobile, hasTouch: vp.hasTouch, deviceScaleFactor: 1,
  reducedMotion: a.reduced ? 'reduce' : 'no-preference',
  recordVideo: { dir: a.out, size },
});
const page = await context.newPage();
const seen = watch(page);

// Samples element boxes and opacity on every animation frame while tracing.
await context.addInitScript(() => {
  const T = (window.__motion = { on: false, rows: new Map(), gaps: [], t0: 0 });
  const name = (el) => {
    let s = el.tagName.toLowerCase();
    if (el.id) return `${s}#${el.id}`;
    const c = String(el.className?.baseVal ?? el.className ?? '').trim().split(/\s+/).filter(Boolean).slice(0, 2).join('.');
    return c ? `${s}.${c}` : s;
  };
  const key = (el) => {
    const r = el.getBoundingClientRect();
    const c = getComputedStyle(el);
    return [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height), Math.round(Number(c.opacity) * 100), c.clipPath === 'none' ? '' : c.clipPath].join(',');
  };
  T.start = () => {
    T.on = true; T.rows = new Map(); T.gaps = []; T.t0 = performance.now();
    const els = [...document.querySelectorAll('body *')].filter((el) => !['SCRIPT', 'STYLE', 'BR', 'PATH', 'DEFS', 'NOSCRIPT'].includes(el.tagName)).slice(0, 400);
    let last = T.t0;
    const scroll0 = scrollY;
    const tick = (now) => {
      if (!T.on) return;
      T.gaps.push(now - last); last = now;
      const dy = scrollY - scroll0;
      for (const el of els) {
        let k = key(el);
        // Ignore pure page scroll: compare positions in document space.
        const parts = k.split(','); parts[1] = String(Number(parts[1]) + Math.round(dy)); k = parts.join(',');
        let row = T.rows.get(el);
        if (!row) { T.rows.set(el, (row = { name: name(el), first: k, prev: k, start: null, end: null, changes: 0 })); continue; }
        if (k !== row.prev) { if (row.start === null) row.start = now - T.t0; row.end = now - T.t0; row.changes++; row.prev = k; }
      }
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  };
  T.stop = () => {
    T.on = false;
    const moved = [...T.rows.values()].filter((r) => r.changes > 1).map((r) => ({ element: r.name, startMs: Math.round(r.start), endMs: Math.round(r.end), durationMs: Math.round(r.end - r.start), frames: r.changes }));
    // Many siblings often move together; report each distinct movement once with a count.
    const groups = new Map();
    for (const m of moved) {
      const k = `${m.element}|${Math.round(m.startMs / 50)}|${Math.round(m.durationMs / 50)}`;
      const g = groups.get(k);
      if (g) g.count++; else groups.set(k, { ...m, count: 1 });
    }
    moved.length = 0; moved.push(...groups.values());
    moved.sort((x, y) => x.startMs - y.startMs || y.durationMs - x.durationMs);
    const gaps = T.gaps.slice(2);
    return { moved, frames: gaps.length, longestFrameGapMs: gaps.length ? Math.round(Math.max(...gaps)) : null, medianFrameGapMs: gaps.length ? Math.round([...gaps].sort((p, q) => p - q)[gaps.length >> 1]) : null };
  };
  if (window.__motionAtLoad) addEventListener('DOMContentLoaded', () => T.start());
});
if (kind === 'load') await context.addInitScript(() => { window.__motionAtLoad = true; });

let clipStart;
try {
  if (kind === 'load') {
    clipStart = Date.now();
    await page.goto(a.url, { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.evaluate(() => { if (!window.__motion.on) window.__motion.start(); });
  } else {
    await page.goto(a.url, { waitUntil: 'load', timeout: 45000 });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(settle);
    await page.evaluate(() => window.__motion.start());
    clipStart = Date.now();
    if (kind === 'wheel') {
      const total = Number(param || 1200), steps = Math.max(8, Math.round(ms / 2 / 16));
      await page.mouse.move(size.width / 2, size.height / 2);
      for (let i = 0; i < steps; i++) { await page.mouse.wheel(0, total / steps); await page.waitForTimeout(16); }
    } else if (kind === 'click') await page.locator(param).first().click({ timeout: 8000 });
    else if (kind === 'hover') await page.locator(param).first().hover({ timeout: 8000 });
    else if (kind === 'key') await page.keyboard.press(param);
  }
} catch (e) {
  await context.close(); await browser.close();
  die(`could not run trigger ${a.trigger}: ${String(e).slice(0, 200)}`);
}
await page.waitForTimeout(Math.max(0, ms - (Date.now() - clipStart)));
const trace = await page.evaluate(() => window.__motion.stop());
const declared = await page.evaluate(() => document.getAnimations().slice(0, 60).map((x) => {
  const t = x.effect?.getComputedTiming?.() ?? {};
  const props = [...new Set((x.effect?.getKeyframes?.() ?? []).flatMap((k) => Object.keys(k)))].filter((p) => !['offset', 'easing', 'composite', 'computedOffset'].includes(p));
  const el = x.effect?.target;
  return { target: el ? el.tagName.toLowerCase() + (el.id ? `#${el.id}` : el.classList?.[0] ? `.${el.classList[0]}` : '') : '?', durationMs: Number(t.duration) || null, delayMs: t.delay ?? 0, easing: t.easing, iterations: t.iterations === Infinity ? 'infinite' : t.iterations, properties: props, state: x.playState };
}));
const clipEnd = Date.now();
const video = page.video();
await context.close();
await browser.close();

const clip = path.join(a.out, 'clip.webm');
renameSync(await video.path(), clip);
const from = Math.max(0, (clipStart - t0) / 1000);
const length = (clipEnd - clipStart) / 1000;
for (const f of readdirSync(path.join(a.out, 'frames'))) rmSync(path.join(a.out, 'frames', f));
const step = length / tiles;
const cols = Math.ceil(Math.sqrt(tiles * (vp.width > vp.height ? 1 : 2)));
const cell = vp.width > vp.height ? 480 : 220;
const run = (argv) => spawnSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...argv], { encoding: 'utf8' });
let ff = run(['-ss', String(from), '-t', String(length), '-i', clip, '-vf', `fps=${(1 / step).toFixed(4)}`, '-frames:v', String(tiles), path.join(a.out, 'frames', '%02d.png')]);
let sheet = null;
if (ff.status === 0) {
  const label = `drawtext=text='%{eif\\:t*1000\\:d} ms':x=8:y=8:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=4`;
  const base = ['-ss', String(from), '-t', String(length), '-i', clip, '-frames:v', '1'];
  const out = path.join(a.out, 'sheet.png');
  ff = run([...base, '-vf', `fps=${(1 / step).toFixed(4)},scale=${cell}:-1,${label},tile=${cols}x${Math.ceil(tiles / cols)}:padding=4:color=0x222222`, out]);
  if (ff.status !== 0) ff = run([...base, '-vf', `fps=${(1 / step).toFixed(4)},scale=${cell}:-1,tile=${cols}x${Math.ceil(tiles / cols)}:padding=4:color=0x222222`, out]);
  if (ff.status === 0) sheet = out;
}

const layoutProps = ['top', 'left', 'right', 'bottom', 'width', 'height', 'margin', 'marginTop', 'marginLeft', 'padding'];
const layoutAnimations = declared.filter((d) => d.properties.some((p) => layoutProps.includes(p)));
const failures = [];
if (trace.moved.length === 0 && !a.reduced) failures.push('nothing moved during the capture window');
if (layoutAnimations.length) failures.push(`${layoutAnimations.length} animation(s) change layout properties (${[...new Set(layoutAnimations.flatMap((d) => d.properties.filter((p) => layoutProps.includes(p))))].join(', ')}); use transform instead`);
const notes = [];
if (a.reduced && trace.moved.length > 3) notes.push(`${trace.moved.length} elements still moved under reduced motion`);
if (trace.longestFrameGapMs > 100) notes.push(`longest gap between frames was ${trace.longestFrameGapMs} ms; headless software rendering exaggerates this, so confirm in a real browser before calling it a stutter`);
if (!sheet) notes.push(`contact sheet not made (ffmpeg: ${(ff.stderr || 'not found').slice(0, 160)})`);
const report = {
  url: a.url, trigger: a.trigger, view: a.view ?? 'desktop', reducedMotion: !!a.reduced, windowMs: Math.round(length * 1000), tileEveryMs: Math.round(step * 1000),
  movedCount: trace.moved.length, moved: trace.moved.slice(0, 40), frames: trace.frames, medianFrameGapMs: trace.medianFrameGapMs, longestFrameGapMs: trace.longestFrameGapMs,
  declaredAnimations: declared, errors: seen.errors, failures, notes, clip, sheet,
  caveat: 'Canvas, WebGL and video content moves without any element changing, so read the contact sheet as well as this list.',
};
writeFileSync(path.join(a.out, 'motion.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify({ pass: failures.length === 0, movedCount: report.movedCount, first: report.moved.slice(0, 5), failures, notes, sheet }, null, 2));
process.exit(failures.length ? 2 : 0);
