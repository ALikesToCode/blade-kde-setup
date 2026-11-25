#!/usr/bin/env node
// Runs shoot.mjs and motion.mjs on small pages that each have one known defect or one tricky
// property, and compares every verdict with the right answer.
//   node tests/run.mjs [--only TEXT] [--timing 3] [--jobs 3] [--keep]
// Needs Playwright (PLAYWRIGHT_PATH, see scripts/lib.mjs). The video page needs ffmpeg to make its
// clip; without ffmpeg its two cases are skipped and the last line says so.
// --timing N repeats the two clock cases N times. --keep leaves the capture folders in place.
// Exit 0: every verdict that ran is as expected and the median contact-sheet label error is under
// 60 ms. 1: otherwise.
import http from 'node:http';
import { execFile, spawnSync } from 'node:child_process';
import { createReadStream, existsSync, mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { args, launch, pixelReader } from '../scripts/lib.mjs';

const a = args();
const here = path.dirname(fileURLToPath(import.meta.url));
const scripts = path.join(here, '..', 'scripts');
const fixtures = path.join(here, 'fixtures');
const work = mkdtempSync(path.join(os.tmpdir(), 'web-art-direction-tests-'));
const LABEL_LIMIT_MS = 60;

// The video page's media is made here, so the repository holds no binary files.
const ff = (argv) => spawnSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...argv]).status === 0;
const hasVideo = ff(['-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24:duration=3', '-c:v', 'libvpx-vp9', '-b:v', '300k', '-deadline', 'realtime', '-cpu-used', '8', '-pix_fmt', 'yuv420p', path.join(work, 'clip.webm')])
  && ff(['-i', path.join(work, 'clip.webm'), '-frames:v', '1', '-q:v', '4', path.join(work, 'poster.jpg')]);

// Static files with byte ranges, which video needs. Looks in fixtures/, then in the work folder.
const TYPES = { '.html': 'text/html; charset=utf-8', '.jpg': 'image/jpeg', '.webm': 'video/webm' };
const server = http.createServer((req, res) => {
  const rel = path.normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^[/\\]+/, '');
  const file = [fixtures, work].map((root) => path.join(root, rel)).find((f) => !rel.startsWith('..') && existsSync(f) && statSync(f).isFile());
  if (!file) { res.writeHead(404, { 'content-type': 'text/plain' }); res.end('not found'); return; }
  const total = statSync(file).size;
  const head = { 'content-type': TYPES[path.extname(file)] ?? 'application/octet-stream', 'accept-ranges': 'bytes', 'cache-control': 'no-store' };
  const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range ?? '');
  if (range) {
    const start = range[1] ? Number(range[1]) : 0, end = range[2] ? Math.min(Number(range[2]), total - 1) : total - 1;
    res.writeHead(206, { ...head, 'content-range': `bytes ${start}-${end}/${total}`, 'content-length': end - start + 1 });
    createReadStream(file, { start, end }).pipe(res);
  } else {
    res.writeHead(200, { ...head, 'content-length': total });
    createReadStream(file).pipe(res);
  }
});
await new Promise((done) => server.listen(0, '127.0.0.1', done));
const base = `http://127.0.0.1:${server.address().port}`;

// exit: the right exit code. must: a failure that has to be reported. only: every failure has to
// match it, so a page cannot fail for an unrelated reason and still count. check: extra test on the
// script's JSON, returning a complaint or nothing.
const moved = (name, from, to) => (j) => {
  const row = (j.first ?? []).find((r) => r.element === name);
  if (!row) return `${name} is not among the elements that moved`;
  return row.startMs >= from && row.startMs <= to ? null : `${name} started at ${row.startMs} ms, expected ${from} to ${to}`;
};
const cases = [
  { id: 'font-missing/shoot', script: 'shoot.mjs', page: 'font-missing.html', exit: 2, must: /asks? for Clash Display, rendered in /, only: /asks? for (Clash Display|Satoshi), rendered in / },
  { id: 'font-404/shoot', script: 'shoot.mjs', page: 'font-404.html', exit: 2, must: /asks? for Ghost Grotesk, rendered in /, only: /missing-font\.woff2|asks? for Ghost Grotesk/ },
  { id: 'overflow-clipped/shoot', script: 'shoot.mjs', page: 'overflow-clipped.html', exit: 2, must: /^phone: .*Book a visit.* cut off/, only: /^phone(-reduced)?: .* cut off/ },
  { id: 'reduced-ignored/shoot', script: 'shoot.mjs', page: 'reduced-ignored.html', exit: 2, must: /^desktop-reduced: .*still changing/, only: /-reduced: .*still changing/ },
  { id: 'video-hero/shoot', script: 'shoot.mjs', page: 'video-hero.html', exit: 0, video: true },
  { id: 'canvas-blank/shoot', script: 'shoot.mjs', page: 'canvas-only.html?blank=1', exit: 2, must: /canvas#c paints nothing/, only: /canvas#c paints nothing/ },
  { id: 'fixed-header/motion-wheel', script: 'motion.mjs', page: 'fixed-header.html', args: ['--trigger', 'wheel:1600'], exit: 2, only: /nothing moved/ },
  { id: 'late-mount/motion-load', script: 'motion.mjs', page: 'late-mount.html', args: ['--trigger', 'load'], exit: 0, check: moved('h1', 250, 900) },
  { id: 'layout-anim/motion-load', script: 'motion.mjs', page: 'layout-anim.html', args: ['--trigger', 'load'], exit: 2, only: /layout properties \((left, width|width, left)\)/ },
  { id: 'layout-anim/motion-click', script: 'motion.mjs', page: 'layout-anim.html', args: ['--trigger', 'click:#grow', '--ms', '1500'], exit: 2, only: /layout properties \((width, margin-left|margin-left, width)\)/ },
  { id: 'canvas-only/motion-load', script: 'motion.mjs', page: 'canvas-only.html', args: ['--trigger', 'load'], exit: 0, check: (j) => (j.pixels.changedFrames > 20 ? null : `only ${j.pixels.changedFrames} frames changed`) },
  { id: 'canvas-blank/motion-load', script: 'motion.mjs', page: 'canvas-only.html?blank=1', args: ['--trigger', 'load'], exit: 2, only: /nothing moved/ },
  { id: 'video-hero/motion-load', script: 'motion.mjs', page: 'video-hero.html', args: ['--trigger', 'load'], exit: 0, video: true, check: (j) => (j.pixels.changedFrames > 20 ? null : `only ${j.pixels.changedFrames} frames changed`) },
  { id: 'reduced-ignored/motion-reduced', script: 'motion.mjs', page: 'reduced-ignored.html', args: ['--trigger', 'load', '--reduced'], exit: 2, must: /still move under reduced motion/, only: /under reduced motion/ },
  { id: 'clock/motion-load', script: 'motion.mjs', page: 'clock.html?mode=load', args: ['--trigger', 'load', '--ms', '3200'], exit: 0, clock: true, check: moved('div#box', 900, 1500) },
  { id: 'clock/motion-click', script: 'motion.mjs', page: 'clock.html?mode=click', args: ['--trigger', 'click:#go', '--ms', '1600'], exit: 0, clock: true, check: moved('div#box', 150, 700) },
].filter((c) => !a.only || c.id.includes(a.only));

const run = (c, n = 0) => new Promise((done) => {
  const out = path.join(work, c.id.replace('/', '--') + (n ? `-${n}` : ''));
  const argv = [path.join(scripts, c.script), '--url', `${base}/${c.page}`, '--out', out, ...(c.script === 'shoot.mjs' ? ['--settle', '800'] : []), ...(c.args ?? [])];
  execFile('node', argv, { encoding: 'utf8', timeout: 180000, maxBuffer: 1 << 24 }, (error, stdout, stderr) => {
    const exit = error ? (typeof error.code === 'number' ? error.code : -1) : 0;
    let j = null;
    try { j = JSON.parse(stdout); } catch {}
    const failures = j?.failures ?? [];
    const why = [];
    if (exit !== c.exit) why.push(`exit ${exit}, expected ${c.exit}`);
    if (!j) why.push(`no JSON on stdout: ${(stderr || stdout).trim().slice(0, 200)}`);
    if (c.exit === 0 && failures.length) why.push(`unexpected failure: ${failures[0]}`);
    if (c.must && !failures.some((f) => c.must.test(f))) why.push(`no failure matches ${c.must}`);
    const stray = c.only ? failures.filter((f) => !c.only.test(f)) : [];
    if (stray.length) why.push(`failed for another reason: ${stray[0]}`);
    const complaint = j && exit === c.exit && c.check ? c.check(j) : null;
    if (complaint) why.push(complaint);
    done({ c, out, exit, why, failures });
  });
});

// Verdict cases run a few at a time. The clock cases run alone, because they measure time.
const results = [];
const queue = cases.filter((c) => !c.clock && (hasVideo || !c.video));
const skipped = cases.filter((c) => c.video && !hasVideo);
await Promise.all(Array.from({ length: Math.max(1, Number(a.jobs ?? 3)) }, async () => {
  for (let c; (c = queue.shift());) results.push(await run(c));
}));
const clockRuns = [];
for (const c of cases.filter((x) => x.clock)) {
  for (let n = 0; n < Math.max(1, Number(a.timing ?? 1)); n++) {
    const r = await run(c, n);
    if (n === 0) results.push(r);
    else if (r.why.length) results.push({ ...r, c: { ...c, id: `${c.id} (run ${n + 1})` } });
    clockRuns.push(r);
  }
}

// The clock page draws a red bar 1 px wide per 5 ms since zero. Reading it from each tile gives the
// time the tile really shows. The label error is that time minus the time the label states, which
// is the wanted time, or the frame's own time when the label gives one. The lag is the tile's
// picture against the wanted time alone: it grows when a busy machine drops frames, and the label
// then says which frame is shown.
const timing = [];
const median = (list) => (list.length ? [...list].sort((p, q) => p - q)[list.length >> 1] : null);
if (clockRuns.length) {
  const { browser } = await launch(a);
  const px = await pixelReader(browser);
  for (const c of cases.filter((x) => x.clock)) {
    const errors = [], lags = [];
    const runs = clockRuns.filter((r) => r.c === c && r.exit === 0 && existsSync(path.join(r.out, 'motion.json')));
    for (const r of runs) {
      for (const t of JSON.parse(readFileSync(path.join(r.out, 'motion.json'), 'utf8')).tiles) {
        if (t.shownMs === null) continue;
        const b64 = readFileSync(path.join(r.out, 'frames', `${String(t.tile).padStart(2, '0')}.jpg`)).toString('base64');
        const clock = await px.page.evaluate(async (d) => {
          const im = await window.__px.decode(d, 'image/jpeg', 4096);
          let best = 0;
          for (let y = 0; y < im.h; y++) {
            let n = 0;
            for (let x = 0; x < im.w; x++) { const i = (y * im.w + x) * 4; if (im.data[i] > 170 && im.data[i + 1] < 80 && im.data[i + 2] < 80) n++; }
            if (n > best) best = n;
          }
          return Math.round((best * 5 * 1440) / im.w);
        }, b64);
        if (clock > 0) { errors.push(clock - t.shownMs); lags.push(clock - t.wantMs); }
      }
    }
    errors.sort((p, q) => p - q);
    const row = { id: c.id, runs: runs.length, tiles: errors.length, medianMs: median(errors), minMs: errors[0] ?? null, maxMs: errors.at(-1) ?? null, medianLagMs: median(lags) };
    timing.push(row);
    const first = results.find((r) => r.c === c);
    if (row.medianMs === null) first.why.push('no tile shows the clock');
    else if (Math.abs(row.medianMs) >= LABEL_LIMIT_MS) first.why.push(`labels are off by a median of ${row.medianMs} ms (limit ${LABEL_LIMIT_MS})`);
  }
  await px.close();
  await browser.close();
}
server.close();

results.sort((p, q) => cases.findIndex((c) => p.c.id.startsWith(c.id)) - cases.findIndex((c) => q.c.id.startsWith(c.id)));
for (const r of results) {
  console.log(`${r.why.length ? 'WRONG' : 'ok   '} ${r.c.id.padEnd(32)} exit ${r.exit}${r.why.length ? `  ${r.why.join('; ')}` : r.failures[0] ? `  ${r.failures[0].slice(0, 110)}` : ''}`);
}
for (const c of skipped) console.log(`SKIP  ${c.id.padEnd(32)} ffmpeg could not make the clip`);
for (const t of timing) console.log(`label error ${t.id}: median ${t.medianMs} ms, range ${t.minMs} to ${t.maxMs} ms over ${t.tiles} tiles in ${t.runs} run(s); picture against the wanted time: median ${t.medianLagMs} ms`);
const wrong = results.filter((r) => r.why.length).length;
const right = results.filter((r) => !r.c.id.includes('(run')).length - results.filter((r) => r.why.length && !r.c.id.includes('(run')).length;
console.log(`${right} of ${cases.length - skipped.length} verdicts as expected${skipped.length ? `, ${skipped.length} skipped` : ''}`);
if (a.keep) console.log(`captures kept in ${work}`);
else rmSync(work, { recursive: true, force: true });
process.exit(wrong ? 1 : 0);
