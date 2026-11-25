#!/usr/bin/env node
// Still captures and hard checks for one page.
//   node shoot.mjs --url URL --out DIR [--settle 1500] [--full] [--allow-failed REGEX] [--cdp ENDPOINT]
// Writes desktop.png, phone.png, desktop-reduced.png, phone-reduced.png (and *-full.png with --full)
// and report.json. Exit 0: checks pass. 2: a check failed. 3: could not run.
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { args, die, launch, VIEWPORTS, watch } from './lib.mjs';

const a = args();
if (!a.url || !a.out) die('usage: node shoot.mjs --url URL --out DIR [--settle MS] [--full] [--allow-failed REGEX]');
const settle = Number(a.settle ?? 1500);
const allow = a['allow-failed'] ? new RegExp(a['allow-failed']) : null;
mkdirSync(a.out, { recursive: true });

const browser = await launch(a.cdp);
const report = { url: a.url, at: new Date().toISOString(), views: [], failures: [] };

for (const [name, vp] of Object.entries(VIEWPORTS)) {
  for (const reduced of [false, true]) {
    const label = reduced ? `${name}-reduced` : name;
    const context = await browser.newContext({
      viewport: { width: vp.width, height: vp.height }, isMobile: vp.isMobile, hasTouch: vp.hasTouch,
      deviceScaleFactor: 1, reducedMotion: reduced ? 'reduce' : 'no-preference',
    });
    const page = await context.newPage();
    const seen = watch(page);
    const bytes = {};
    const hosts = new Set();
    page.on('response', (r) => {
      const type = r.request().resourceType();
      bytes[type] = (bytes[type] ?? 0) + Number(r.headers()['content-length'] ?? 0);
      if (['image', 'media', 'font'].includes(type)) { try { hosts.add(new URL(r.url()).host); } catch {} }
    });
    try {
      await page.goto(a.url, { waitUntil: 'load', timeout: 45000 });
    } catch (e) {
      report.failures.push(`${label}: page did not load (${String(e).slice(0, 120)})`);
      await context.close();
      continue;
    }
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(settle);
    await page.screenshot({ path: path.join(a.out, `${label}.png`) });
    if (a.full) await page.screenshot({ path: path.join(a.out, `${label}-full.png`), fullPage: true });

    const dom = await page.evaluate(() => {
      const inView = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < innerHeight; };
      const media = [];
      for (const el of document.querySelectorAll('img')) {
        if (!inView(el)) continue;
        if (!el.complete || el.naturalWidth === 0) media.push(`img not decoded: ${(el.currentSrc || el.src).slice(0, 120)}`);
      }
      for (const el of document.querySelectorAll('video')) {
        if (!inView(el)) continue;
        if (el.readyState < 2 && !el.poster) media.push(`video has no frame and no poster: ${(el.currentSrc || el.src).slice(0, 120)}`);
      }
      const fonts = [...document.fonts].filter((f) => f.status === 'error').map((f) => f.family.replace(/["']/g, ''));
      const roles = {};
      for (const sel of ['h1', 'h2', 'p', 'a', 'button']) {
        const el = document.querySelector(sel);
        if (!el) continue;
        const c = getComputedStyle(el);
        const family = c.fontFamily.split(',')[0].replace(/["']/g, '').trim();
        // check() is true for system and generic families and for web fonts that finished loading.
        roles[sel] = { family, size: c.fontSize, weight: c.fontWeight, loaded: document.fonts.check(`${c.fontWeight} 16px "${family}"`) };
      }
      const h1 = document.querySelector('h1');
      return {
        overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        pageHeight: document.documentElement.scrollHeight,
        media, fonts, roles,
        h1InFirstView: h1 ? inView(h1) : null,
        h1Count: document.querySelectorAll('h1').length,
        hasMain: !!document.querySelector('main, [role=main]'),
        imagesWithoutAlt: [...document.querySelectorAll('img')].filter((el) => !el.hasAttribute('alt')).length,
        smallTargets: [...document.querySelectorAll('a[href], button, [role=button], input, select')].filter((el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 && (r.width < 24 || r.height < 24) && getComputedStyle(el).display !== 'inline'; }).length,
        videosNotMutedInline: [...document.querySelectorAll('video[autoplay]')].filter((el) => !el.muted || !el.playsInline).length,
        canvases: document.querySelectorAll('canvas').length,
        videos: document.querySelectorAll('video').length,
        runningAnimations: document.getAnimations().filter((x) => x.playState === 'running').length,
      };
    });

    const failed = seen.failed.filter((f) => !(allow && allow.test(f.url)));
    const unloaded = [...new Set(Object.values(dom.roles).filter((r) => !r.loaded).map((r) => r.family))];
    const pageHost = new URL(a.url).host;
    const kb = Object.fromEntries(Object.entries(bytes).map(([k, v]) => [k, Math.round(v / 1024)]));
    const view = { view: label, viewport: `${vp.width}x${vp.height}`, ...dom, transferKB: kb, externalAssetHosts: [...hosts].filter((h) => h !== pageHost), errors: seen.errors, failedRequests: failed };
    const note = (text) => { report.notes = [...(report.notes ?? []), `${label}: ${text}`]; };
    if (!reduced) {
      if (dom.h1Count !== 1) note(`${dom.h1Count} h1 elements; a page needs exactly one`);
      if (!dom.hasMain) note('no <main> element');
      if (dom.imagesWithoutAlt) note(`${dom.imagesWithoutAlt} image(s) without an alt attribute`);
      if (dom.smallTargets) note(`${dom.smallTargets} control(s) smaller than 24x24 px`);
      if (dom.videosNotMutedInline) note(`${dom.videosNotMutedInline} autoplay video(s) missing muted or playsinline; phones will not play them`);
      if (view.externalAssetHosts.length) note(`images, video or fonts load from other hosts (${view.externalAssetHosts.join(', ')}); store assets in the project`);
      const media = (kb.image ?? 0) + (kb.media ?? 0);
      if (media > 3000) note(`${media} KB of images and video reported on load`);
    }
    report.views.push(view);
    if (seen.errors.length) report.failures.push(`${label}: ${seen.errors.length} page or console error(s): ${seen.errors[0]}`);
    if (failed.length) report.failures.push(`${label}: ${failed.length} failed request(s): ${failed[0].url} (${failed[0].reason})`);
    if (dom.overflowX > 1) report.failures.push(`${label}: page scrolls sideways by ${dom.overflowX}px`);
    for (const m of dom.media) report.failures.push(`${label}: ${m}`);
    if (unloaded.length) report.failures.push(`${label}: font not loaded: ${unloaded.join(', ')}`);
    await context.close();
  }
}
await browser.close();

// Reduced motion should not leave movement running.
for (const v of report.views.filter((x) => x.view.endsWith('-reduced'))) {
  if (v.runningAnimations > 0) report.notes = [...(report.notes ?? []), `${v.view}: ${v.runningAnimations} animation(s) still running under reduced motion; check they are not decorative movement`];
}
report.pass = report.failures.length === 0;
writeFileSync(path.join(a.out, 'report.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify({ pass: report.pass, failures: report.failures, notes: report.notes ?? [], out: a.out }, null, 2));
process.exit(report.pass ? 0 : 2);
