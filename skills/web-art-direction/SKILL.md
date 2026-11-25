---
name: web-art-direction
description: Build or redesign a public-facing web page with real art direction and motion instead of a template look. Use for landing pages, launch pages, portfolios, product showcases and hero sections, when the user wants a site that looks designed, shows a reference site to learn from, or asks for motion, video, 3D or shader work on a page. Not for dashboards, forms, docs or small UI fixes.
---

# Web art direction

A page looks templated when its design decisions were never made. This skill makes you settle them
in writing, build the still page, add one piece of motion that means something, and prove the result
with captures that a separate reviewer scores.

Read the project's existing tokens, components, fonts and copy first. They outrank everything here.
For product UI, or a page that does not need motion, use `frontend-design-director` or `impeccable`
instead.

## 1. Write the contract before any UI code

Create `design/contract.md` from [references/contract.md](references/contract.md). It fixes:

- **Thesis**: one sentence on what the visitor should see and feel, tied to this subject.
- **First viewport**: the focal subject, what overlaps what, and where the main action sits, for
  desktop and for phone. The phone layout is designed, not shrunk.
- **Type and colour**: at most two font families with roles, four to six colour roles with values,
  and the reason each one fits the subject.
- **Sections**: each one answers a different visitor question. Give each section one job.
- **Media**: what the main image, video or object is, who made it, its crops and its still fallback.
- **Motion table**: one signature beat plus small feedback. Each row has target, trigger, from, to,
  duration or scroll range, easing, what happens on interrupt, phone behaviour and the
  reduced-motion replacement.

Draft two different first-viewport concepts with the real copy and choose one. If a concept would
suit three unrelated businesses after swapping the logo, it is not a concept yet.

Using a reference site? Run `scripts/shoot.mjs` and `scripts/motion.mjs` on it and record, for each
reference, the one principle you take (a composition idea, a motion mechanic) and how your page
applies it to a different subject. Never reuse its copy, images, marks or layout. Stop at logins and
bot checks. [references/sources.md](references/sources.md) lists where to find references and
ready-made parts.

## 2. Make the main asset first

The page is composed around its main image, video or object, so that comes before layout.
[references/assets.md](references/assets.md) covers choosing the medium, generating it on this
machine, and delivery sizes. Text and controls stay in HTML, never baked into an image.

## 3. Build the still page, and pass the checks, before any motion

Build the first viewport and its main interaction, look at it, then extend to the other sections.
Use final content and no animation yet. Then run:

```bash
node scripts/shoot.mjs --url http://localhost:3000 --out design/run/still
```

It captures desktop, phone and reduced-motion views and exits non-zero on page errors, failed
requests, sideways overflow, undecoded media or fonts that did not load. Its notes cover headings,
alt text, small tap targets, assets loaded from other hosts and media weight. Look at every PNG
yourself. Both scripts take `--cdp ENDPOINT` to attach to a browser that is already running, for
sessions that may not start their own.
Fix the still page until it would be acceptable to ship with motion turned off.

## 4. Add the signature beat

Implement the motion table. [references/motion.md](references/motion.md) says which tool to reach for
and the rules that keep it smooth. Then capture it:

```bash
node scripts/motion.mjs --url http://localhost:3000 --out design/run/motion --trigger load
node scripts/motion.mjs --url http://localhost:3000 --out design/run/scroll --trigger wheel:1600
```

Each run writes numbered frames, a labelled contact sheet and `motion.json` (what moved, when it
started, how long it took, the longest gap between frames). Read the contact sheet: a beat should
show a start, a change and a settled end. A sheet where every tile is the same means nothing moved.
A screenshot test cannot judge motion, so do not skip this.

## 5. Hand the page to a separate reviewer

You do not grade your own page. Start a fresh agent with no build history, on a different model
family when one is available, and give it only: the brief, `design/contract.md`, the capture folders
and the running URL. It follows [references/review.md](references/review.md) and returns scores and
defects tied to a screenshot, frame or input.

Fix the highest-impact defects in at most two rounds, re-running the affected capture each time.
Ship when the hard checks pass and the review reaches 12 of 15 with no axis under 2. If a round
makes the score worse, keep the earlier version. If no separate reviewer was available, say
`SELF_REVIEW_ONLY` in your report.

## Report

State the thesis, what the signature beat is, the review score, what failed and was fixed, and what
is still open. Link the contact sheet and the desktop and phone captures. Say plainly which checks
did not run. Field performance and real-phone behaviour are unverified unless you measured them.
