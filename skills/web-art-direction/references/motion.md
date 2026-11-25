# Motion: tool choice and rules

## Reach for the smallest tool that does the job

| Need | Use |
| --- | --- |
| One state change, hover, press, menu | CSS transitions or keyframes |
| Progress tied to scroll or to an element entering view | CSS `animation-timeline: scroll()` / `view()`, with the still state as fallback |
| Moving between two page states or routes | View Transitions API |
| React component enter, exit, shared layout, springs, gestures | Motion (`motion/react`) |
| Overlapping beats, pinning, scrubbing, reversal, split text | GSAP with ScrollTrigger; in React use `useGSAP` with a scope, and `gsap.matchMedia()` for breakpoints and reduced motion |
| Smoothed scrolling, only when the design needs it | Lenis, driven from the same ticker as GSAP so there is one frame loop |
| A live viewpoint, an object the visitor turns, a material | Three.js or React Three Fiber |
| A procedural background or material | A fragment shader on one full-screen plane |

One animation system owns each animated property. Two libraries writing the same transform is the
usual cause of jitter.

A fixed camera move does not need real-time 3D. A pre-rendered clip, a video scrubbed by scroll or
pointer, or two layered stills often carry the same scene for a fraction of the cost.

Check the installed version's documentation before writing library code; these APIs change.

## Starting values

Starting points to adjust by eye, not rules.

| Motion | Start with |
| --- | --- |
| Press or hover feedback | 150–200 ms, ease-out, at most 3 px or 1.02 scale |
| Headline reveal | lines masked by an `overflow: hidden` parent, 600–800 ms each, 60–80 ms apart, `cubic-bezier(0.22, 1, 0.36, 1)` |
| Menu or panel | 250–350 ms, items 40–60 ms apart |
| Section entrance | 500–600 ms, 20–30 px rise with opacity, once |
| Item sliding to the next slot | 600–700 ms, plus about 150 ms for each extra slot travelled |
| Scroll scrub | catch-up of 0.3–0.6 s; under scrub, durations are shares of the scroll range |

Entrances are faster than they feel they should be. Nothing the visitor is waiting on runs longer
than about a second. Vary the treatment: a page where every section fades up the same way looks
generated.

## Rules that keep it smooth and usable

- Animate `transform`, `opacity`, `clip-path` and, sparingly, `filter`. Animating `top`, `left`,
  `width` or `height` forces layout on every frame.
- Cap canvas pixel ratio at 2. Pixel cost grows with the square of the ratio.
- Pause canvases and videos that are off-screen or in a hidden tab. Dispose of WebGL resources on
  unmount.
- The largest element in the first viewport loads eagerly. Lazy-load only what is below it.
- Media that a scroll animation depends on must not be lazy-loaded.
- `prefers-reduced-motion: reduce` gets the settled state at once: no parallax, no pinning, no
  autoplaying scene. Content and controls are all still there.
- Movement that starts on its own and runs longer than five seconds needs a visible pause control.
- On touch screens: no custom cursor, no hover-only reveals, no sideways-pinned scroll that traps
  the page. Give pointer effects a tap or keyboard equivalent.
- Headline split into spans for animation keeps its full text available to screen readers.
