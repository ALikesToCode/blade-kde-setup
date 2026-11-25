#!/usr/bin/env node
// Record one piece of motion and turn it into evidence a reviewer can read.
//   node motion.mjs --url URL --out DIR --trigger load|wheel:PX|click:SELECTOR|hover:SELECTOR|key:KEY
//                   [--ms 4000] [--view desktop|phone] [--reduced] [--settle 1500] [--tiles 16] [--every 80]
//                   [--clip] [--gl hardware|software] [--cdp ENDPOINT]
// Frames come from the browser's screencast, each stamped with the time it was shown. Zero is the
// start of navigation for `load` and the first input event for the other triggers. `wheel:PX` sends
// notches of 100 px, --every ms apart, and the window runs --ms past the last one.
// Writes frames/NN.jpg, sheet.png (labelled contact sheet) and motion.json, and clip.webm with --clip.
// Exit 0: pass. 2: nothing moved, an animation changes layout properties, or the page keeps moving
// under --reduced. 3: could not run.
import { mkdirSync, writeFileSync, renameSync, readdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import { args, die, isSoftwareGL, launch, pixelReader, VIEWPORTS, watch } from './lib.mjs';

const a = args();
if (!a.url || !a.out || !a.trigger) die('usage: node motion.mjs --url URL --out DIR --trigger load|wheel:PX|click:SEL|hover:SEL|key:KEY [--ms 4000] [--view desktop|phone] [--reduced] [--tiles 16] [--every 80] [--clip]');
const reduced = !!a.reduced;
// A reduced-motion run needs time to show that the page has come to rest.
const ms = Math.max(Number(a.ms ?? 4000), reduced ? 5000 : 0);
const settle = Number(a.settle ?? 1500);
const tiles = Math.max(2, Number(a.tiles ?? 16));
const every = Number(a.every ?? 80);
const vp = VIEWPORTS[a.view ?? 'desktop'] ?? die(`unknown --view ${a.view}`);
const [kind, ...rest] = String(a.trigger).split(':');
const param = rest.join(':');
if (!['load', 'wheel', 'click', 'hover', 'key'].includes(kind)) die(`unknown trigger ${a.trigger}`);
mkdirSync(path.join(a.out, 'frames'), { recursive: true });

// Runs in the page from the first script on. On every animation frame it samples element boxes and
// opacity, and lists the animations and transitions that exist at that moment.
function tracer() {
  if (window !== window.top) return;
  const SKIP = new Set(['HTML', 'HEAD', 'BODY', 'SCRIPT', 'STYLE', 'BR', 'NOSCRIPT', 'META', 'LINK', 'TITLE', 'TEMPLATE']);
  const INPUTS = { click: ['pointerdown', 'mousedown', 'touchstart'], wheel: ['wheel'], key: ['keydown'], hover: ['pointerover', 'mouseover', 'pointermove', 'mousemove'] };
  const T = (window.__motion = { on: true, armed: null, armAt: null, trigAt: null, lastInputAt: null, scrolled: false });
  const rows = new Map();
  const els = new Set();
  let anims = new Map(), trans = new Map(), gaps = [];
  const name = (el) => {
    const s = el.tagName.toLowerCase();
    if (el.id) return `${s}#${el.id}`;
    const c = String(el.className?.baseVal ?? el.className ?? '').trim().split(/\s+/).filter(Boolean).slice(0, 2).join('.');
    return c ? `${s}.${c}` : s;
  };
  // Elements are added as they appear, so content that mounts late is traced too.
  const add = (n) => { if (els.size < 1200 && !n.ownerSVGElement && !SKIP.has(n.tagName.toUpperCase())) els.add(n); };
  new MutationObserver((list) => {
    for (const m of list) for (const n of m.addedNodes) if (n.nodeType === 1) { add(n); for (const d of n.querySelectorAll('*')) add(d); }
  }).observe(document, { childList: true, subtree: true });
  // The moment of the trigger on the page's own clock.
  for (const type of new Set(Object.values(INPUTS).flat())) {
    addEventListener(type, (e) => {
      if (!T.armed || !INPUTS[T.armed].includes(e.type)) return;
      if (T.trigAt === null) T.trigAt = e.timeStamp;
      T.lastInputAt = e.timeStamp;
    }, { capture: true, passive: true });
  }
  addEventListener('scroll', () => { if (T.armed) T.scrolled = true; }, { capture: true, passive: true });
  // A transition names its property when it starts, so short ones are not lost.
  addEventListener('transitionrun', (e) => {
    if (e.target?.nodeType !== 1) return;
    const k = `${name(e.target)}|${e.propertyName}`;
    if (!trans.has(k)) trans.set(k, { target: name(e.target), property: e.propertyName, at: performance.now() });
  }, true);
  const collect = (now) => {
    for (const an of document.getAnimations()) {
      const el = an.effect?.target;
      if (!el || anims.has(an) || anims.size >= 300) continue;
      let frames = [];
      try { frames = an.effect.getKeyframes(); } catch {}
      const t = an.effect.getComputedTiming();
      anims.set(an, {
        target: name(el), kind: an.transitionProperty ? 'transition' : 'animation', name: an.animationName ?? an.transitionProperty ?? an.id ?? '',
        properties: [...new Set(frames.flatMap((k) => Object.keys(k)))].filter((p) => !['offset', 'easing', 'composite', 'computedOffset'].includes(p)),
        durationMs: Number(t.duration) || null, delayMs: t.delay ?? 0, easing: frames[0]?.easing ?? t.easing,
        iterations: t.iterations === Infinity ? 'infinite' : t.iterations, at: now,
      });
    }
  };
  let last = performance.now();
  const far = (x, y) => Math.abs(x - y) >= 0.05;
  const tick = (now) => {
    if (!T.on) return;
    gaps.push(now - last);
    last = now;
    collect(now);
    const sx = scrollX, sy = scrollY;
    for (const el of els) {
      if (!el.isConnected) continue;
      const r = el.getBoundingClientRect();
      const cs = getComputedStyle(el);
      const cur = { x: r.x, y: r.y, w: r.width, h: r.height, clip: cs.clipPath, op: Number(cs.opacity) };
      const row = rows.get(el);
      if (!row) { rows.set(el, { name: name(el), cur, dx: r.x + sx, dy: r.y + sy, w: r.width, h: r.height, op: cur.op, acc: 0, n: 0, geo: 0, fade: 0, first: null, last: null }); continue; }
      // Plain scrolling changes the viewport position only, and a fixed or sticky element changes
      // the document position only. Moving means both changed in the same frame.
      const dx = r.x + sx, dy = r.y + sy;
      if ((far(r.x, row.cur.x) || far(r.y, row.cur.y)) && (far(dx, row.dx) || far(dy, row.dy))) row.acc += Math.max(Math.abs(r.x - row.cur.x), Math.abs(r.y - row.cur.y));
      const geo = row.acc >= 0.5 || Math.abs(r.width - row.w) >= 0.5 || Math.abs(r.height - row.h) >= 0.5 || cur.clip !== row.cur.clip;
      const fade = Math.abs(cur.op - row.op) >= 0.01;
      if (geo) { row.geo++; row.acc = 0; row.w = r.width; row.h = r.height; }
      if (fade) { row.fade++; row.op = cur.op; }
      if (geo || fade) { row.n++; row.first ??= now; row.last = now; }
      row.cur = cur; row.dx = dx; row.dy = dy;
    }
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
  // Called just before the trigger: forget what happened while the page loaded.
  T.arm = (kind) => {
    for (const row of rows.values()) Object.assign(row, { acc: 0, n: 0, geo: 0, fade: 0, first: null, last: null });
    anims = new Map(); trans = new Map(); gaps = [];
    Object.assign(T, { armed: kind, armAt: performance.now(), trigAt: null, lastInputAt: null, scrolled: false });
  };
  T.stop = () => {
    T.on = false;
    collect(performance.now());
    return {
      zero: T.armed ? T.trigAt ?? T.armAt : 0, end: performance.now(), scrolled: T.scrolled,
      rows: [...rows.values()].filter((r) => r.n > 2).map((r) => ({ name: r.name, n: r.n, geo: r.geo, fade: r.fade, first: r.first, last: r.last })),
      animations: [...anims.values()], transitions: [...trans.values()], gaps: gaps.slice(2),
    };
  };
}

const { browser, renderer } = await launch(a);
const size = { width: vp.width, height: vp.height };
const context = await browser.newContext({
  viewport: size, isMobile: vp.isMobile, hasTouch: vp.hasTouch, deviceScaleFactor: vp.isMobile ? 2 : 1,
  reducedMotion: reduced ? 'reduce' : 'no-preference',
  ...(a.clip ? { recordVideo: { dir: a.out, size } } : {}),
});
await context.addInitScript(tracer);
const page = await context.newPage();
const seen = watch(page);
const cdp = await context.newCDPSession(page);
const frames = [];
cdp.on('Page.screencastFrame', (f) => {
  frames.push({ ts: f.metadata.timestamp * 1000, data: f.data });
  cdp.send('Page.screencastFrameAck', { sessionId: f.sessionId }).catch(() => {});
});
// The screencast sends a frame only when the picture changes.
const startCast = () => cdp.send('Page.startScreencast', { format: 'jpeg', quality: 70, maxWidth: size.width, maxHeight: size.height, everyNthFrame: 1 });
const pageNow = () => page.evaluate(() => performance.timeOrigin + performance.now());
// Canvas and video boxes in the viewport, as fractions of it.
const mediaBoxes = () => page.evaluate(() => [...document.querySelectorAll('canvas, video')].map((el) => el.getBoundingClientRect())
  .filter((r) => r.width > 8 && r.height > 8 && r.right > 0 && r.bottom > 0 && r.left < innerWidth && r.top < innerHeight)
  .map((r) => {
    const x0 = Math.max(0, r.left), y0 = Math.max(0, r.top), x1 = Math.min(innerWidth, r.right), y1 = Math.min(innerHeight, r.bottom);
    return { x: x0 / innerWidth, y: y0 / innerHeight, w: (x1 - x0) / innerWidth, h: (y1 - y0) / innerHeight };
  }));

const notes = [];
let zero, end, wheel = null, boxes = null;
try {
  if (kind === 'load') {
    await startCast();
    await page.goto(a.url, { waitUntil: 'commit', timeout: 45000 });
    zero = await page.evaluate(() => performance.timeOrigin);
    end = zero + ms;
  } else {
    await page.goto(a.url, { waitUntil: 'load', timeout: 45000 });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(settle);
    await startCast();
    if (kind === 'wheel') await page.mouse.move(size.width / 2, size.height / 2);
    await page.waitForTimeout(150);
    boxes = await mediaBoxes();
    await page.evaluate((k) => window.__motion.arm(k), kind);
    if (kind === 'wheel') {
      // A mouse wheel sends about 100 px per notch. Pages ignore much smaller deltas.
      const notches = Math.max(1, Math.ceil(Number(param || 1200) / 100));
      const began = Date.now();
      for (let i = 0; i < notches; i++) { await page.mouse.wheel(0, 100); if (i < notches - 1) await page.waitForTimeout(every); }
      wheel = { notches, plannedMs: (notches - 1) * every, tookMs: Date.now() - began };
      if (wheel.tookMs > Math.max(200, wheel.plannedMs * 1.5)) notes.push(`the wheel notches took ${wheel.tookMs} ms where ${wheel.plannedMs} ms was planned; the page is slow to take input`);
    } else if (kind === 'click') await page.locator(param).first().click({ timeout: 8000 });
    else if (kind === 'hover') await page.locator(param).first().hover({ timeout: 8000 });
    else if (kind === 'key') await page.keyboard.press(param);
    const t = await page.evaluate(() => ({ origin: performance.timeOrigin, arm: window.__motion.armAt, first: window.__motion.trigAt, last: window.__motion.lastInputAt }));
    if (t.first === null) notes.push('the page saw no input event for this trigger; times count from just before it was sent');
    zero = t.origin + (t.first ?? t.arm);
    end = t.origin + (t.last ?? t.arm) + ms;
  }
  const left = end - (await pageNow());
  await page.waitForTimeout(Math.max(0, left) + 60);
} catch (e) {
  await context.close().catch(() => {});
  await browser.close().catch(() => {});
  die(`could not run trigger ${a.trigger}: ${String(e).slice(0, 200)}`);
}
const trace = await page.evaluate(() => window.__motion.stop());
// Scrolling repaints the whole picture, whether a wheel, a key or a link caused it. Pixels then
// count only inside a canvas or video box that stayed where it was.
const scrolled = kind === 'wheel' || trace.scrolled;
if (scrolled) {
  const after = await mediaBoxes();
  const near = (p, q) => ['x', 'y', 'w', 'h'].every((k) => Math.abs(p[k] - q[k]) < 0.002);
  boxes = boxes.filter((b) => after.some((c) => near(b, c)));
} else boxes = null;
await cdp.send('Page.stopScreencast').catch(() => {});
const video = a.clip ? page.video() : null;
await context.close();
let clip = null;
if (video) { clip = path.join(a.out, 'clip.webm'); renameSync(await video.path(), clip); }

// Pixels: how many frames after zero differ from the last frame that counted as a change.
const windowMs = Math.round(end - zero);
const before = frames.filter((f) => f.ts < zero).at(-1) ?? null;
const inWindow = frames.filter((f) => f.ts >= zero && f.ts <= end + 60);
const px = await pixelReader(browser);
const pixels = { region: scrolled ? 'canvas and video boxes that stayed in place' : 'page', frames: inWindow.length, changedFrames: 0, lastChangeMs: null };
if (!scrolled || boxes.length) {
  if (kind !== 'load' && before) await px.next(before.data, 'image/jpeg', boxes);
  for (const f of inWindow) {
    if ((await px.next(f.data, 'image/jpeg', boxes)) > 0.002) { pixels.changedFrames++; pixels.lastChangeMs = Math.round(f.ts - zero); }
  }
}

// Tiles: what was on screen at each wanted time, which is the last frame shown at or before it.
// Tile 0 of a triggered run is the last frame before the trigger, so the sheet starts untouched.
for (const f of readdirSync(path.join(a.out, 'frames'))) rmSync(path.join(a.out, 'frames', f));
const picked = [];
for (let i = 0; i < tiles; i++) {
  const wantMs = Math.round((i * windowMs) / (tiles - 1));
  let f = null;
  if (i === 0 && kind !== 'load') f = before;
  else for (const x of frames) { if (x.ts <= zero + wantMs + 8) f = x; else break; }
  f ??= frames[0];
  if (!f) continue;
  const frameMs = Math.round(f.ts - zero);
  // The label gives the wanted time, and the frame's own time when the two are more than 20 ms
  // apart. shownMs is the time the label states for the picture.
  let label = `${wantMs} ms`, shownMs = wantMs;
  if (i === 0 && kind !== 'load') { label += ' · before trigger'; shownMs = null; }
  else if (frameMs < 0) { label += ' · no change yet'; shownMs = null; }
  else if (Math.abs(wantMs - frameMs) > 20) { label += ` · ${frameMs > wantMs ? 'first frame at' : 'frame from'} ${frameMs}`; shownMs = frameMs; }
  const file = path.join(a.out, 'frames', `${String(i).padStart(2, '0')}.jpg`);
  writeFileSync(file, Buffer.from(f.data, 'base64'));
  picked.push({ tile: i, wantMs, frameMs, shownMs, label, b64: f.data });
}
let sheet = null;
if (picked.length) {
  const wide = vp.width > vp.height;
  try {
    const png = await px.sheet(picked.map((p) => ({ b64: p.b64, mime: 'image/jpeg', label: p.label })), wide ? 480 : 220, Math.ceil(Math.sqrt(tiles * (wide ? 1 : 2))));
    sheet = path.join(a.out, 'sheet.png');
    writeFileSync(sheet, png);
  } catch (e) { notes.push(`contact sheet not made (${String(e).slice(0, 160)})`); }
} else notes.push('the browser sent no frames, so there is no contact sheet');
await px.close();
await browser.close();

// Elements: times are since zero. An element that changed before the trigger, is still changing at
// the end, or has an endless animation is a loop, not the beat.
const rel = (t) => Math.round(t - trace.zero);
const traceEnd = rel(trace.end);
const kebab = (p) => p.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);
const animations = trace.animations.map(({ at, ...x }) => ({ ...x, properties: x.properties.map(kebab), firstSeenMs: rel(at) }));
const transitions = trace.transitions.map(({ at, ...x }) => ({ ...x, startedMs: rel(at) }));
const endless = new Set(animations.filter((x) => x.iterations === 'infinite').map((x) => x.target));
const oneShot = [], looping = [];
const groups = new Map();
for (const r of trace.rows) {
  const row = { element: r.name, startMs: rel(r.first), endMs: rel(r.last), visibleChangeMs: rel(r.last) - rel(r.first), frames: r.n, geometryFrames: r.geo, opacityFrames: r.fade };
  // Sub-pixel tails are invisible to the trace, so the declared duration is the real length.
  const declared = animations.filter((x) => x.target === r.name && x.iterations !== 'infinite' && x.durationMs).map((x) => x.durationMs);
  if (declared.length) row.declaredMs = Math.max(...declared);
  const loop = row.startMs < 0 || row.endMs > traceEnd - 250 || endless.has(r.name);
  // Siblings often move together; report each distinct movement once with a count.
  const k = `${loop}|${row.element}|${Math.round(row.startMs / 50)}|${Math.round(row.visibleChangeMs / 50)}`;
  const g = groups.get(k);
  if (g) g.count++;
  else { groups.set(k, { ...row, count: 1 }); (loop ? looping : oneShot).push(groups.get(k)); }
}
for (const list of [oneShot, looping]) list.sort((x, y) => x.startMs - y.startMs || y.visibleChangeMs - x.visibleChangeMs);
const movedCount = oneShot.length + looping.length;

const LAYOUT = /^(top|left|right|bottom|width|height|(min|max)-(width|height)|inset(-.+)?|margin(-.+)?|padding(-.+)?)$/;
const layout = [...new Set([...animations.flatMap((x) => x.properties), ...transitions.map((x) => x.property)].filter((p) => LAYOUT.test(p)))];
const failures = [];
if (!reduced && movedCount === 0 && pixels.changedFrames <= 2) failures.push('nothing moved during the capture window');
if (layout.length) failures.push(`animations or transitions change layout properties (${layout.join(', ')}); use transform instead`);
if (reduced) {
  // Opacity may still change, so a cross-fade replacement is allowed.
  const moving = [...oneShot, ...looping].filter((r) => r.geometryFrames > 2);
  if (moving.length) failures.push(`${moving.length} element(s) still move under reduced motion (${moving.slice(0, 3).map((r) => r.element).join(', ')}); show the settled state at once`);
  if (pixels.lastChangeMs !== null && pixels.lastChangeMs > windowMs - 1000) failures.push('the picture is still changing in the last second under reduced motion');
}
if (!reduced && movedCount === 0 && pixels.changedFrames > 2) {
  if (scrolled) notes.push('no element moved; the verdict rests on pixels inside a canvas or video box, which content scrolling over it also changes. Confirm on the sheet');
  else if (kind === 'load' && pixels.changedFrames <= 6) notes.push(`no element moved and only ${pixels.changedFrames} frames changed; this can be the page loading in steps. Confirm on the sheet`);
}
const gaps = trace.gaps;
const longestFrameGapMs = gaps.length ? Math.round(Math.max(...gaps)) : null;
if (longestFrameGapMs > 100) notes.push(`longest gap between frames was ${longestFrameGapMs} ms; ${isSoftwareGL(renderer) ? 'software rendering exaggerates this, so confirm in a real browser' : 'a busy GPU or machine causes this too, so run it again'} before calling it a stutter`);
const report = {
  url: a.url, trigger: a.trigger, view: a.view ?? 'desktop', renderer, reducedMotion: reduced,
  zero: new Date(zero).toISOString(), windowMs, firstPaintMs: kind === 'load' && inWindow.length ? Math.round(inWindow[0].ts - zero) : null,
  movedCount, oneShot: oneShot.slice(0, 40), looping: looping.slice(0, 20), pixels, wheel,
  animations: animations.slice(0, 60), transitions: transitions.slice(0, 60),
  frames: gaps.length, medianFrameGapMs: gaps.length ? Math.round([...gaps].sort((p, q) => p - q)[gaps.length >> 1]) : null, longestFrameGapMs,
  tiles: picked.map(({ tile, wantMs, frameMs, shownMs }) => ({ tile, wantMs, frameMs, shownMs })),
  errors: seen.errors, failures, notes, sheet, clip,
};
writeFileSync(path.join(a.out, 'motion.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify({ pass: failures.length === 0, renderer, movedCount, first: oneShot.slice(0, 5), looping: looping.length, pixels, failures, notes, sheet }, null, 2));
process.exit(failures.length ? 2 : 0);
