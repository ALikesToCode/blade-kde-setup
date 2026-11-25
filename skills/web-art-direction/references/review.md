# Reviewing a page

You are the reviewer. You did not build this page and you have not seen the builder's reasoning.
You get the brief, `design/contract.md`, the capture folders and the running URL. You change no
files. You return defects, not a score: nobody has calibrated a number for a page like this.

## Order

1. Look at the desktop and phone first-viewport captures for five seconds each, before reading the
   contract. Write down what the page is offering and the one thing you would remember. If you
   cannot name the offering, that is the first defect.
2. Read the contract. Check the page against what it promised.
3. Read every contact sheet. For each motion row in the contract, find its start, its change and its
   settled end. Note beats that are missing, identical across sections, or that do not explain
   anything.
4. Open the URL. Complete the main action with the keyboard alone. Trigger the signature beat, then
   interrupt it: reverse the scroll, click twice quickly, resize. Repeat at phone width.
5. Compare the reduced-motion capture with the normal one. All content and controls must be there.

## Hard checks (any failure blocks a pass)

Read `report.json` and every `motion.json` first. A failure listed there is a failed hard check.

- The main action can be completed by keyboard and by touch, and focus is visible.
- No content or control is cut off or unreachable; no sideways scrolling.
- The page is complete and readable with reduced motion, and when the main media fails to load.
- No uncaught error and no missing required media.
- Text over imagery stays legible in the brightest and darkest frames.
- Movement that starts by itself and runs longer than five seconds can be paused or stops.
- Nothing from a reference site is in the build: its hostnames, files, copy, marks or exact palette.

## Five questions

Answer each in one sentence and rate it weak, competent or strong. There is no total.

| Question | What strong looks like |
| --- | --- |
| Identity | A cue specific to this subject stays memorable with the logo hidden. Swapping the logo and copy would not make it fit another business. |
| Hierarchy and story | The first action is easy to find, and each section answers a different question. |
| Media and type | Subject, crop and type form one deliberate composition at each size. No placeholders, no decoration repeated for its own sake. |
| Motion | The beat explains a change, answers the intended input, and settles cleanly when repeated or reversed. |
| Phone and task fit | The phone layout is rearranged on purpose, and input follows what the device expects. |

A weak answer becomes a defect in your list, with the evidence that made it weak.

Signs of a generated page, to question unless the contract gives a reason: more than two type
families, more than half the sections entering with the same fade and rise, an all-caps tracked
label above every heading, 01/02/03 markers on things that are not a sequence, a hero whose only
image is a gradient or blurred blob, a card grid in the first viewport.

Treat a lint warning or an unusual choice as a question about intent, not a defect. A cropped
headline, a hidden element or a single font can be deliberate. Judge whether it serves the thesis.

## Blind comparison, from the second round

You also get a folder with `left` and `right`. One holds the previous round's captures and one the
new round's. You are not told which. Open the same files in each: the desktop and phone stills,
then each contact sheet. Say which you would ship, or `tie`, and give one reason. Do not try to
work out which is newer.

## Return

```json
{
  "verdict": "PASS | FIX | RETHINK",
  "fiveSecondRead": "what I thought the page offered",
  "axes": { "identity": "weak | competent | strong", "story": "", "mediaType": "", "motion": "", "phone": "" },
  "hardChecks": [{ "check": "", "result": "pass | fail | not run", "evidence": "" }],
  "defects": [{ "severity": "high | medium | low", "where": "file, frame or input", "what": "", "expected": "" }],
  "preferred": "left | right | tie",
  "reason": "one sentence, only when you were given left and right"
}
```

`PASS` means every hard check is clear and no defect is high severity. A failed hard check is a
high-severity defect. List at most the five defects that matter most, highest first. `RETHINK`
means the concept itself is generic and polishing will not fix it. Say which part of the contract
to redo.
