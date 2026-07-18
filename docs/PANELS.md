# Plasma panels and widgets

The Blade layout adapts the strongest ideas from a highly visual Quickshell
desktop to Plasma 6 without replacing KDE's working services. Its custom Plasma
surface theme supplies near-black, rounded panel and popup foundations; blue
remains the primary accent and green is reserved for memory and healthy-state
telemetry.

Each display receives a bottom application panel with:

- the custom multicolor **A** launcher and Candy icons;
- icon-only application tasks and numbered workspaces;
- Plasma's native media controller;
- blue CPU, green memory, and blue GPU donut monitors;
- always-available Wi-Fi, Bluetooth, audio, battery, and notification controls;
- a date-bearing clock whose popup is the native KDE calendar.

The primary panel remains visible. Panels created for additional displays use
auto-hide and reveal at the bottom edge, so each monitor has full application
controls without permanently consuming space.

## Applying safely

The default command configures one panel per screen, adds missing widgets, and
does not remove panels or duplicate matching widget types:

```bash
./scripts/apply-panels.sh
```

Preview it without contacting Plasma:

```bash
./scripts/apply-panels.sh --dry-run
```

For a clean, exact rebuild of every panel, explicitly acknowledge the
replacement. The existing Plasma applet configuration is backed up first:

```bash
./scripts/apply-panels.sh --replace-existing --yes
```

The exact mode removes existing panels, so it is intentionally never selected
by the normal installer.

## GPU sensor selection

The current Blade workstation exposes its discrete GPU as `gpu/gpu1`. Systems
with another sensor identifier can override it without editing the repository:

```bash
BLADE_GPU_SENSOR_PREFIX=gpu/gpu0 \
BLADE_GPU_TITLE='Discrete GPU' \
./scripts/apply-panels.sh
```
