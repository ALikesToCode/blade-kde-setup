# Design contract template

Copy to `design/contract.md` and fill every part. Short is fine; blank is not.

```markdown
# <Page name>

## Brief
Subject: · Audience: · The one action we want: · Copy source: · Existing design system:

## Thesis
<One sentence. What the visitor sees and feels, and why that suits this subject.>

## First viewport
Desktop 1440×900: focal subject, what overlaps what, headline position, action position.
Phone 390×844: what moves, what is cropped, what is dropped.
Scaling: the design frame and the unit sizes derive from, for example `min(100vw/1440, 100vh/900)`.
The cue someone would remember with the logo hidden:

## Type
| Role | Family | Weight | Size range | Why |
| display | | | | |
| text | | | | |

## Colour
| Role | Value | Used for | Why |
| ground | | | |
| ink | | | |
| accent | | | |

## Sections
| # | Visitor's question | Content | Layout idea |

## Media
| Id | What it is | Source or how made | Desktop crop | Phone crop | Still fallback | Bytes budget |

## Motion
| Id | Purpose for the visitor | Target | Trigger | From | To | Duration or scroll range | Easing | On interrupt | Phone | Reduced motion |

## References
| URL | Captured | Principle taken | How this page applies it differently | Not taken |
```

Rules for the motion table:

- One signature beat. More than two large movements competing in one viewport reads as noise.
- "Purpose for the visitor" must name a change it explains: a selection, a continuity between two
  states, depth, cause and effect. "Looks premium" is not a purpose.
- Every row has a settled end state that is correct with the animation removed.
