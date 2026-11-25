# The main asset

## Choose the medium by what the visitor does with it

| Visitor's interaction | Medium |
| --- | --- |
| Looks at it | One strong still, cropped separately for desktop and phone |
| Watches ambient movement | A 4–8 s loop, muted, with a poster frame |
| Drives it by scrolling or moving the pointer | A short clip scrubbed by input, or frames drawn to a canvas |
| Several objects drift at different depths | Transparent cut-outs on separate layers |
| Turns it, or the camera must respond live | A GLB model in Three.js, textures 2K at most |

Use the cheapest medium that keeps the main interaction. A layered still can score as well as WebGL.

## Making it on this machine

- `lmedia` runs local image, video, 3D, cut-out and upscaling models under a GPU lock. Read its
  skill for which tool does what, and run `lmedia doctor` and `blade-agents hardware` for free VRAM
  before starting. Other agents share the GPU, so run asset jobs one at a time.
- For video, generate or pick the still first, then animate that still. The still fixes composition
  and style; the prompt only describes camera, subject and environment movement.
- Blender runs headless (`blender -b --python scene.py`) for product renders, turntables and GLB
  export. Start OpenGL programs that need the NVIDIA GPU with `prime-run`.
- Record how each asset was made (tool, model, seed, inputs) in the contract's media table.
- Look at every output before using it: edges of cut-outs, the loop seam, a calm area where text
  will sit, and the phone crop.

## Delivery

```bash
# loop for the web: no audio, plays while downloading
ffmpeg -i in.mp4 -an -c:v libx264 -crf 24 -preset slow -pix_fmt yuv420p -movflags +faststart out.mp4
# poster from the first frame
ffmpeg -i out.mp4 -frames:v 1 -q:v 3 poster.jpg
```

Budgets to start from, per page: poster up to 250 KB, everything needed for the first view up to
600 KB, optional phone video up to 1.5 MB more. State any larger budget in the contract.

Serve a smaller clip or only the poster to phones. Ship the poster as the reduced-motion and
failed-load state. Self-host fonts and media; do not hotlink a reference site's files.

## Rights

Use only media you made, generated, or have a licence for. A file being publicly reachable is not
permission to reuse it.
