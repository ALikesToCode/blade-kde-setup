#!/usr/bin/env node
// Still captures and hard checks for one page.
//   node shoot.mjs --url URL --out DIR [--settle 1500] [--full] [--allow-failed REGEX] [--allow-blank-canvas]
//                  [--gl hardware|software] [--cdp ENDPOINT]
// Writes desktop.png, phone.png, desktop-reduced.png, phone-reduced.png (and *-full.png with --full)
// and report.json. Exit 0: checks pass. 2: a check failed. 3: could not run.
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { args, die, launch, pixelReader, VIEWPORTS, watch } from './lib.mjs';

const a = args();
if (!a.url || !a.out) die('usage: node shoot.mjs --url URL --out DIR [--settle MS] [--full] [--allow-failed REGEX] [--allow-blank-canvas]');
const settle = Number(a.settle ?? 1500);
const allow = a['allow-failed'] ? new RegExp(a['allow-failed']) : null;
mkdirSync(a.out, { recursive: true });

// Families a page may name without loading a file for them.
const SYSTEM = /^(system-ui|ui-sans-serif|ui-serif|ui-monospace|ui-rounded|sans-serif|serif|monospace|cursive|fantasy|math|emoji|-apple-system|BlinkMacSystemFont|Arial|Helvetica|Helvetica Neue|Times|Times New Roman|Georgia|Courier|Courier New|Verdana|Tahoma|Trebuchet MS|Segoe UI|Roboto|Menlo|Monaco|Consolas|SF Pro Text|SF Pro Display|Apple Color Emoji|Segoe UI Emoji|Noto Color Emoji)$/i;
const ROLES = ['h1', 'h2', 'p', 'a', 'button'];
// The first element for a role that draws text of its own, so the font asked for and the font
// rendered belong to the same node.
const pickText = `(sel) => { for (const el of [...document.querySelectorAll(sel)].slice(0, 30)) { const w = document.createTreeWalker(el, NodeFilter.SHOW_TEXT); for (let n; (n = w.nextNode());) if (n.data.trim() && n.parentElement.getClientRects().length) return n.parentElement; } return null; }`;
const describeFont = `function () { const c = getComputedStyle(this); const asked = c.fontFamily.split(',')[0].replace(/["']/g, '').trim(); return { asked, size: c.fontSize, weight: c.fontWeight, faceLoaded: [...document.fonts].some((f) => f.status === 'loaded' && f.family.replace(/["']/g, '').trim().toLowerCase() === asked.toLowerCase()) }; }`;

// Which font drew each role. document.fonts.check() cannot tell: it is true for any family that
// no stylesheet declares. The browser reports the face by its full name ("Archivo SemiBold" for a
// family called "Archivo Wide"), so the test is a loaded face under the asked name plus glyphs
// that came from a web font, not a name match.
async function fontsByRole(cdp) {
  await cdp.send('DOM.enable');
  await cdp.send('CSS.enable');
  await cdp.send('DOM.getDocument', { depth: 0 });
  const roles = {};
  for (const sel of ROLES) {
    const { result } = await cdp.send('Runtime.evaluate', { expression: `(${pickText})(${JSON.stringify(sel)})` });
    if (!result.objectId) continue;
    const { nodeId } = await cdp.send('DOM.requestNode', { objectId: result.objectId });
    const { fonts } = await cdp.send('CSS.getPlatformFontsForNode', { nodeId });
    if (!fonts.length) continue;
    const used = [...fonts].sort((x, y) => y.glyphCount - x.glyphCount)[0];
    const info = (await cdp.send('Runtime.callFunctionOn', { objectId: result.objectId, functionDeclaration: describeFont, returnByValue: true })).result.value;
    const system = SYSTEM.test(info.asked);
    roles[sel] = { family: info.asked, size: info.size, weight: info.weight, rendered: used.familyName, custom: !!used.isCustomFont, ...(system ? { system: true } : { loaded: info.faceLoaded && !!used.isCustomFont }) };
  }
  return roles;
}

const { browser, renderer } = await launch(a);
const px = await pixelReader(browser);
const report = { url: a.url, at: new Date().toISOString(), renderer, views: [], failures: [], notes: [] };

for (const [name, vp] of Object.entries(VIEWPORTS)) {
  for (const reduced of [false, true]) {
    const label = reduced ? `${name}-reduced` : name;
    const fail = (text) => report.failures.push(`${label}: ${text}`);
    const note = (text) => report.notes.push(`${label}: ${text}`);
    // A phone has about three device pixels per CSS pixel, which decides srcset and canvas sizes.
    const context = await browser.newContext({
      viewport: { width: vp.width, height: vp.height }, isMobile: vp.isMobile, hasTouch: vp.hasTouch,
      deviceScaleFactor: vp.isMobile ? 3 : 1, reducedMotion: reduced ? 'reduce' : 'no-preference',
    });
    const page = await context.newPage();
    const seen = watch(page);
    // Bytes as they crossed the network. content-length is missing on compressed and chunked responses.
    const cdp = await context.newCDPSession(page);
    const requests = new Map();
    await cdp.send('Network.enable');
    cdp.on('Network.responseReceived', (e) => { if (/^https?:/.test(e.response.url)) requests.set(e.requestId, { type: String(e.type).toLowerCase(), url: e.response.url, bytes: 0, done: false }); });
    cdp.on('Network.dataReceived', (e) => { const r = requests.get(e.requestId); if (r && !r.done) r.bytes += e.encodedDataLength; });
    cdp.on('Network.loadingFinished', (e) => { const r = requests.get(e.requestId); if (r) { r.bytes = e.encodedDataLength; r.done = true; } });
    try {
      await page.goto(a.url, { waitUntil: 'load', timeout: 45000 });
    } catch (e) {
      fail(`page did not load (${String(e).slice(0, 120)})`);
      await context.close();
      continue;
    }
    const loadedAt = Date.now();
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(settle);
    await page.screenshot({ path: path.join(a.out, `${label}.png`) });
    if (a.full) await page.screenshot({ path: path.join(a.out, `${label}-full.png`), fullPage: true });
    // Reduced motion means the page comes to rest, so two stills a second apart must match. They
    // are taken four and five seconds after load, because a replacement fade may still be ending.
    let changingShare = null;
    if (reduced) {
      await page.waitForTimeout(Math.max(0, 4000 - (Date.now() - loadedAt)));
      const first = await page.screenshot();
      await page.waitForTimeout(1000);
      changingShare = await px.differ(first.toString('base64'), (await page.screenshot()).toString('base64'), 'image/png');
    }

    const dom = await page.evaluate(() => {
      const vw = document.documentElement.clientWidth;
      const reach = Math.max(0, document.documentElement.scrollWidth - vw);
      const inView = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < innerHeight; };
      const shown = (el) => { const r = el.getBoundingClientRect(); const c = getComputedStyle(el); return r.width > 0 && r.height > 0 && c.visibility !== 'hidden' && Number(c.opacity) > 0.05; };
      const text = (el) => `${el.tagName.toLowerCase()} "${(el.innerText || el.getAttribute('aria-label') || el.value || '').trim().replace(/\s+/g, ' ').slice(0, 24)}"`;
      const id = (el) => el.tagName.toLowerCase() + (el.id ? `#${el.id}` : el.classList[0] ? `.${el.classList[0]}` : '');
      // How far a box is cut off sideways, and whether a transform put it there. The scroll width
      // cannot show this: overflow-x hidden or clip on the root makes it 0 while content sits off screen.
      const cutOff = (el, rect) => {
        let r = { left: rect.left, right: rect.right }, px = 0, offLeft = false, pos = getComputedStyle(el).position, parked = false;
        const moved = (c) => (c.transform !== 'none' && Math.abs(new DOMMatrixReadOnly(c.transform).m41) > 1) || (c.translate && c.translate !== 'none');
        const against = (box) => { const over = Math.max(r.right - box.right, box.left - r.left); if (over > px) { px = over; offLeft = r.right <= box.left; } };
        parked = moved(getComputedStyle(el));
        for (let p = el.parentElement; p; p = p.parentElement) {
          const c = getComputedStyle(p);
          if (moved(c)) parked = true;
          // An absolute box is clipped only from its containing block up, a fixed one by nothing.
          if (pos === 'fixed' || (pos === 'absolute' && c.position === 'static')) continue;
          pos = c.position;
          const root = p === document.body || p === document.documentElement;
          if (!root && /auto|scroll/.test(c.overflowX)) { const b = p.getBoundingClientRect(); r = { left: b.left, right: b.right }; } // reachable by scrolling inside p
          else if (/hidden|clip/.test(c.overflowX)) against(root ? { left: 0, right: vw } : p.getBoundingClientRect());
        }
        against({ left: -scrollX, right: vw + reach - scrollX });
        return { px: Math.round(px), offLeft, parked };
      };
      const media = [];
      for (const el of document.querySelectorAll('img')) {
        if (!inView(el)) continue;
        if (!el.complete || el.naturalWidth === 0) media.push(`img not decoded: ${(el.currentSrc || el.src).slice(0, 120)}`);
      }
      for (const el of document.querySelectorAll('video')) {
        if (!inView(el)) continue;
        if (el.readyState < 2 && !el.poster) media.push(`video has no frame and no poster: ${(el.currentSrc || el.src).slice(0, 120)}`);
      }
      // Controls parked off screen on purpose (a closed drawer, the next slide) belong in an inert
      // or aria-hidden container, and those are skipped.
      const unreachableControls = [], parkedControls = [];
      for (const el of [...document.querySelectorAll('a[href], button, [role=button], input, select, textarea')].slice(0, 400)) {
        if (!shown(el) || el.closest('[inert], [aria-hidden="true"]')) continue;
        const cut = cutOff(el, el.getBoundingClientRect());
        if (cut.px <= 8) continue;
        // A box wholly off the left edge is a skip link or a closed drawer, and a transform is how
        // sliders and marquees park things. Layout that pushes a control off screen is a defect.
        (cut.offLeft || cut.parked ? parkedControls : unreachableControls).push({ control: text(el), px: cut.px });
      }
      const clippedHeadings = [];
      for (const el of document.querySelectorAll('h1, h2')) {
        if (!shown(el)) continue;
        // The box of a block element does not show overflowing text; a range over its contents does.
        const range = document.createRange();
        range.selectNodeContents(el);
        const cut = cutOff(el, range.getBoundingClientRect());
        if (cut.px > 8) clippedHeadings.push({ heading: text(el), px: cut.px });
      }
      const canvases = [...document.querySelectorAll('canvas')].map((el, index) => ({ el, index, r: el.getBoundingClientRect() }))
        .filter(({ el, r }) => shown(el) && r.right > 0 && r.bottom > 0 && r.left < innerWidth && r.top < innerHeight)
        .map(({ el, index, r }) => { const x = Math.max(0, r.left), y = Math.max(0, r.top); return { canvas: id(el), index, clip: { x, y, width: Math.min(innerWidth, r.right) - x, height: Math.min(innerHeight, r.bottom) - y } }; })
        .filter((c) => c.clip.width > 8 && c.clip.height > 8).slice(0, 3);
      const h1 = document.querySelector('h1');
      return {
        overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        pageHeight: document.documentElement.scrollHeight,
        media, unreachableControls: unreachableControls.slice(0, 8), parkedControls: parkedControls.length, clippedHeadings: clippedHeadings.slice(0, 8), canvases,
        fontFilesFailed: [...document.fonts].filter((f) => f.status === 'error').map((f) => f.family.replace(/["']/g, '')),
        h1InFirstView: h1 ? inView(h1) : null,
        h1Count: document.querySelectorAll('h1').length,
        hasMain: !!document.querySelector('main, [role=main]'),
        imagesWithoutAlt: [...document.querySelectorAll('img')].filter((el) => !el.hasAttribute('alt')).length,
        smallTargets: [...document.querySelectorAll('a[href], button, [role=button], input, select')].filter((el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 && (r.width < 24 || r.height < 24) && getComputedStyle(el).display !== 'inline'; }).length,
        videosNotMutedInline: [...document.querySelectorAll('video[autoplay]')].filter((el) => !el.muted || !el.playsInline).length,
        videos: document.querySelectorAll('video').length,
        runningAnimations: document.getAnimations().filter((x) => x.playState === 'running').length,
      };
    });
    const roles = await fontsByRole(cdp);
    // A canvas that paints nothing leaves a hole where the picture should be. Compare its box with
    // the canvas shown and hidden.
    if (!reduced) {
      const hide = (on) => page.evaluate(([i, v]) => { const el = document.querySelectorAll('canvas')[i]; if (v) { el.dataset.shootVisibility = el.style.visibility; el.style.setProperty('visibility', 'hidden', 'important'); } else { el.style.visibility = el.dataset.shootVisibility; delete el.dataset.shootVisibility; } }, on);
      for (const c of dom.canvases) {
        const shownShot = await page.screenshot({ clip: c.clip });
        await hide([c.index, true]);
        const hiddenShot = await page.screenshot({ clip: c.clip });
        await hide([c.index, false]);
        c.paintedShare = Number((await px.differ(shownShot.toString('base64'), hiddenShot.toString('base64'), 'image/png')).toFixed(4));
      }
    }

    const failed = seen.failed.filter((f) => !(allow && allow.test(f.url)));
    const pageHost = new URL(a.url).host;
    const kb = {};
    const hosts = new Set();
    for (const r of requests.values()) {
      kb[r.type] = (kb[r.type] ?? 0) + r.bytes;
      if (['image', 'media', 'font'].includes(r.type)) hosts.add(new URL(r.url).host);
    }
    for (const k of Object.keys(kb)) kb[k] = Math.round(kb[k] / 1024);
    const view = { view: label, viewport: `${vp.width}x${vp.height}`, ...dom, canvases: dom.canvases.map(({ canvas, paintedShare }) => ({ canvas, paintedShare })), roles, changingShare, transferKB: kb, externalAssetHosts: [...hosts].filter((h) => h !== pageHost), errors: seen.errors, failedRequests: failed };
    if (!reduced) {
      if (dom.h1Count !== 1) note(`${dom.h1Count} h1 elements; a page needs exactly one`);
      if (!dom.hasMain) note('no <main> element');
      if (dom.imagesWithoutAlt) note(`${dom.imagesWithoutAlt} image(s) without an alt attribute`);
      if (dom.smallTargets) note(`${dom.smallTargets} control(s) smaller than 24x24 px`);
      if (dom.videosNotMutedInline) note(`${dom.videosNotMutedInline} autoplay video(s) missing muted or playsinline; phones will not play them`);
      if (view.externalAssetHosts.length) note(`images, video or fonts load from other hosts (${view.externalAssetHosts.join(', ')}); store assets in the project`);
      const media = (kb.image ?? 0) + (kb.media ?? 0);
      if (media > 3000) note(`${media} KB of images and video loaded`);
      // A cropped headline can be deliberate, so this is a question, not a failure.
      for (const h of dom.clippedHeadings) note(`${h.heading} runs ${h.px} px past the edge`);
      if (dom.parkedControls) note(`${dom.parkedControls} control(s) sit off screen behind a transform or past the left edge; keep them inert until they are shown`);
    }
    report.views.push(view);
    if (seen.errors.length) fail(`${seen.errors.length} page or console error(s): ${seen.errors[0]}`);
    if (failed.length) fail(`${failed.length} failed request(s): ${failed[0].url} (${failed[0].reason})`);
    if (dom.overflowX > 1) fail(`page scrolls sideways by ${dom.overflowX}px`);
    for (const m of dom.media) fail(m);
    for (const c of dom.unreachableControls) fail(`${c.control} is cut off by ${c.px} px and cannot be reached`);
    const fallback = new Map();
    for (const [sel, r] of Object.entries(roles)) if (r.loaded === false) fallback.set(`${r.family}|${r.rendered}`, [...(fallback.get(`${r.family}|${r.rendered}`) ?? []), sel]);
    for (const [k, sels] of fallback) fail(`${sels.join(', ')} ${sels.length > 1 ? 'ask' : 'asks'} for ${k.split('|')[0]}, rendered in ${k.split('|')[1]}`);
    for (const c of dom.canvases) {
      if (c.paintedShare === undefined || c.paintedShare >= 0.0005) continue;
      if (a['allow-blank-canvas']) note(`${c.canvas} paints nothing in the first view`);
      else fail(`${c.canvas} paints nothing in the first view (pass --allow-blank-canvas if it only draws on input)`);
    }
    if (changingShare > 0.002) fail(`the picture is still changing under reduced motion (${(changingShare * 100).toFixed(1)}% of pixels differ between two stills a second apart)`);
    else if (reduced && dom.runningAnimations > 0) note(`${dom.runningAnimations} animation(s) still running under reduced motion; check they are not decorative movement`);
    await context.close();
  }
}
await px.close();
await browser.close();

report.pass = report.failures.length === 0;
writeFileSync(path.join(a.out, 'report.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify({ pass: report.pass, renderer, failures: report.failures, notes: report.notes, out: a.out }, null, 2));
process.exit(report.pass ? 0 : 2);
