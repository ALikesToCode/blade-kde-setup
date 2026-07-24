# Plasma panels and widgets

The Blade layout adapts the strongest ideas from a highly visual Quickshell
desktop to Plasma 6 without replacing KDE's working services. Plasma's complete
Breeze Dark surface assets provide stable near-black, rounded panels and
popups; the Artix color scheme keeps blue as the primary accent and green for
memory and healthy-state telemetry.

Each display receives a bottom application panel with:

- the custom multicolor **A** launcher and Candy icons;
- icon-only application tasks and numbered workspaces;
- Plasma's native media controller;
- compact pastel-blue CPU, pastel-green memory, and cyan GPU donut monitors;
- a two-line cyan/green display of live download and upload speeds;
- always-available Wi-Fi, Bluetooth, audio, battery, and notification controls;
- the Blade Event Calendar clock with a full calendar and agenda popup.

The task manager keeps existing pins and ensures the Blade default set is
available on both displays: Konsole, Dolphin, Zen Browser, Zed, Antigravity,
and System Settings. Tasks are grouped, stay scoped to their physical screen,
and retain audio activity indicators.

The Event Calendar is a pinned Plasma 6 package with a Blade-owned overlay:
near-black rounded Material cards, a restrained blue/cyan/green accent rail,
blue time, green date, rounded day selection, dot event badges, and a spacious
two-column calendar/agenda view. Weather, timer, Google Calendar, local Plasma
calendar plugins, and iCalendar remain available, but the default popup keeps
weather and timer hidden until they are configured.

The primary panel remains visible. Panels created for additional displays use
auto-hide and reveal at the bottom edge, so each monitor has full application
controls without permanently consuming space.

Each desktop also receives the custom `org.mysterious.bladeclock` plasmoid. It
echoes the login composition with a large blue hour, green minutes, and compact
dark date pill over the wallpaper's quiet upper-left field. The apply script
adds a missing clock per display but preserves any instance the user has moved
or resized.

## Applying safely

The default command configures one panel per screen, adds missing widgets, and
does not remove panels or duplicate matching widget types:

```bash
./scripts/apply-panels.sh
```

Preview it without contacting Plasma:

```bash
./scripts/apply-panels.sh --dry-run
./scripts/apply-desktop-clock.sh --dry-run
./scripts/install-event-calendar.sh --dry-run
```

For a clean, exact rebuild of every panel, explicitly acknowledge the
replacement. The existing Plasma applet configuration is backed up first:

```bash
./scripts/apply-panels.sh --replace-existing --yes
```

The exact mode removes existing panels, so it is intentionally never selected
by the normal installer.

After reviewing the change, replace the native Digital Clock widgets with
Event Calendar on both panels using the separately acknowledged command:

```bash
./scripts/apply-panels.sh --replace-clock --yes
```

## GPU sensor selection

The current Blade workstation exposes its discrete GPU as `gpu/gpu1`. Systems
with another sensor identifier can override it without editing the repository:

```bash
BLADE_GPU_SENSOR_PREFIX=gpu/gpu0 \
BLADE_GPU_TITLE='Discrete GPU' \
./scripts/apply-panels.sh
```
