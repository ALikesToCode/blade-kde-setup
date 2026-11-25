---
name: web-art-direction
description: Motion-led landing page, launch page, portfolio or hero section built around one made image, video or 3D object and one signature motion beat, checked with timed browser captures. Not for dashboards, forms, docs, product UI or small fixes.
---

# Web art direction

A page looks templated when its design decisions were never made. This skill makes you settle them
in writing, build the still page, add one piece of motion that means something, and prove the result
with captures that a separate reviewer checks.

Read the project's existing tokens, components, fonts and copy first. They outrank everything here.

Start here when the request is a motion-led public page. If `frontend-design-director` is already
leading the task, it stays the lead: use its contract, and take from this skill only step 2, step 4
and the two capture scripts. For product UI, or a page that does not need motion, use
`frontend-design-director` or `impeccable` instead.

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

Using a reference site? Run `scripts/shoot.mjs` and `scripts/motion.mjs` on it and read the captures
and `motion.json`. Ignore the pass or fail there, because the checks are written for your own page.
Record, for each reference, the one principle you take (a composition idea, a motion mechanic) and
how your page applies it to a different subject. Never reuse its copy, images, marks or layout. Stop
at logins and bot checks. [references/sources.md](references/sources.md) lists where to find references and
ready-made parts.

## 2. Make the main asset first

The page is composed around its main image, video or object, so that comes before layout.
[references/assets.md](references/assets.md) covers choosing the medium, generating it on this
machine, and delivery sizes. Text and controls stay in HTML, never baked into an image.

## 3. Build the still page, and pass the checks, before any motion

Build the first viewport with every state of its main interaction reachable as a still (a class or
a query flag), with no animation. Look at it, then extend to the other sections. Use final content.
Then run:

```bash
node scripts/shoot.mjs --url http://localhost:3000 --out design/run/1/still
```

It captures desktop, phone and reduced-motion views. It exits non-zero on:

- a page error or a failed request
- sideways overflow, or a control that is cut off and cannot be reached
- media that did not decode, or a canvas that paints nothing
- a named web font that rendered in a fallback font
- a picture that still changes under reduced motion

Its notes cover headings, heading text that runs past the edge, alt text, small tap targets, assets
loaded from other hosts and media weight. Look at every PNG yourself. Fix the still page until it
would be acceptable to ship with motion turned off.

Both scripts render in software unless the page asks for WebGL, and then they use the GPU.
`--gl hardware|software` forces one. `--cdp ENDPOINT` attaches to a browser that is already running,
for sessions that may not start their own. If the session may neither start Chromium nor attach
with `--cdp`, do not capture another way. Ask the parent to run the scripts, and report
`CAPTURES_NOT_RUN` if nobody can.

## 4. Add the signature beat

Implement the motion table. [references/motion.md](references/motion.md) says which tool to reach for
and the rules that keep it smooth. Then capture each row of the table by its trigger, and the load
once more under reduced motion:

```bash
node scripts/motion.mjs --url http://localhost:3000 --out design/run/1/load --trigger load
node scripts/motion.mjs --url http://localhost:3000 --out design/run/1/scroll --trigger wheel:1600
node scripts/motion.mjs --url http://localhost:3000 --out design/run/1/reduced --trigger load --reduced
```

Triggers are `load`, `wheel:PX`, `click:SELECTOR`, `hover:SELECTOR` and `key:KEY`. Each run writes a
labelled contact sheet, its frames and `motion.json`. Tile times count from the start of navigation
for `load` and from the input event for the other triggers. The first tile of a triggered run shows
the page just before the trigger.

`motion.json` lists what moved once, what loops, the animations and transitions that ran with their
declared durations, and how many frames changed on screen. A run exits non-zero when nothing moved
or when an animation changes a layout property. A `--reduced` run exits non-zero when an element
still moves or the picture is still changing at the end. Opacity may change there, so a cross-fade
is a valid replacement.

Read the contact sheet. A beat should show a start, a change and a settled end. A sheet where every
tile is the same means nothing moved. A screenshot test cannot judge motion, so do not skip this.

## 5. Hand the page to a separate reviewer

You do not grade your own page. Start a fresh agent with no build history, on a different model
family when one is available, and give it only: the brief, `design/contract.md`, the capture folders
and the running URL. It follows [references/review.md](references/review.md) and returns defects
tied to a screenshot, frame or input. It gives no score.

Fix the highest-impact defects in at most two rounds. Capture each round into its own folder
(`design/run/2/`, `design/run/3/`) with the same sub-folder names. From the second round the
reviewer also compares the previous round with the new one without knowing which is which:

```bash
mkdir -p design/run/pair
if (( RANDOM % 2 )); then a=1 b=2; else a=2 b=1; fi
cp -r design/run/$a design/run/pair/left && cp -r design/run/$b design/run/pair/right
```

Give the reviewer `design/run/pair/` and keep the order to yourself.

Ship when all three hold:

- Both scripts exit 0, with `motion.mjs` run for each row of the motion table and once with
  `--reduced`.
- The reviewer lists no high-severity defect.
- From the second round on, the reviewer does not prefer the previous round in the blind comparison.

If the reviewer prefers the previous round, keep that round and stop. If no separate reviewer was
available, say `SELF_REVIEW_ONLY` in your report.

## Report

State the thesis, what the signature beat is, the reviewer's defects and which you fixed, the result
of the blind comparison if there was one, and what is still open. Link the contact sheet and the
desktop and phone captures. Say plainly which checks did not run. Field performance and real-phone
behaviour are unverified unless you measured them.
